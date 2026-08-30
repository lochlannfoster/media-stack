"""Companion wiring for Bazarr, Jellyfin and Jellyseerr.
Self-contained helpers so it can be imported by wiring.py. Idempotent."""
import json, logging, os, time, urllib.request, urllib.parse, urllib.error, xml.etree.ElementTree as ET

log = logging.getLogger("wiring")

def H(method, url, headers=None, data=None, opener=None, timeout=90, expect_json=True):
    h = dict(headers or {}); body = None
    if data is not None:
        if isinstance(data, (dict, list)): body = json.dumps(data).encode(); h.setdefault("Content-Type", "application/json")
        elif isinstance(data, bytes): body = data
        else: body = str(data).encode()
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    op_open = opener.open if opener is not None else urllib.request.urlopen
    try:
        with op_open(req, timeout=timeout) as r:
            raw = r.read().decode(); return r.status, (json.loads(raw) if expect_json and raw else raw)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]
    except Exception as e:
        return None, str(e)

def wait(url, name, tries=60, headers=None):
    for _ in range(tries):
        st, _ = H("GET", url, headers=headers, expect_json=False, timeout=8)
        if st and st < 500: log.info("%s up", name); return True
        time.sleep(3)
    log.warning("%s not up: %s", name, url); return False

def apikey(cfg, app):
    p = os.path.join(cfg["CONFIG_DIR"], app, "config.xml")
    for _ in range(40):
        if os.path.exists(p):
            try:
                k = ET.parse(p).getroot().findtext("ApiKey")
                if k: return k
            except Exception: pass
        time.sleep(3)
    raise RuntimeError("no api key for " + app)

def port(cfg, k, d): return cfg.get(k, d)

# ---------------- Bazarr ----------------
def wire_bazarr(cfg, sec):
    url = f"http://localhost:{port(cfg,'BAZARR_PORT','6767')}"
    wait(url + "/", "Bazarr")
    # bazarr generates its own api key in config; read from config.yaml
    bk = _bazarr_key(cfg)
    if not bk: log.warning("bazarr api key not found; skipping"); return
    def B(path, pairs, method="POST"):
        body = urllib.parse.urlencode(pairs, doseq=True).encode()
        return H(method, url + path, headers={"X-API-KEY": bk, "Content-Type": "application/x-www-form-urlencoded"},
                 data=body, expect_json=False)
    rk = apikey(cfg, "radarr"); sk = apikey(cfg, "sonarr")
    langs = cfg.get("SUBTITLE_LANGS", "en").split(",")
    providers = ["podnapisi", "tvsubtitles", "yifysubtitles"]
    if sec.get("OPENSUBS_USER"): providers.append("opensubtitlescom")
    B("/api/system/settings", [
        ("settings-general-use_sonarr", "true"), ("settings-sonarr-ip", "sonarr"), ("settings-sonarr-port", "8989"),
        ("settings-sonarr-base_url", "/"), ("settings-sonarr-ssl", "false"), ("settings-sonarr-apikey", sk),
        ("settings-general-use_radarr", "true"), ("settings-radarr-ip", "radarr"), ("settings-radarr-port", "7878"),
        ("settings-radarr-base_url", "/"), ("settings-radarr-ssl", "false"), ("settings-radarr-apikey", rk),
        ("settings-general-enabled_providers", providers),
        ("settings-general-serie_default_enabled", "true"), ("settings-general-movie_default_enabled", "true"),
        ("settings-general-use_embedded_subs", "false"), ("settings-general-upgrade_subs", "true")])
    if sec.get("OPENSUBS_USER"):
        B("/api/system/settings", [("settings-opensubtitlescom-username", sec["OPENSUBS_USER"]),
                                   ("settings-opensubtitlescom-password", sec["OPENSUBS_PASS"]),
                                   ("settings-opensubtitlescom-use_hash", "true")])
    # language profile
    prof = [{"profileId": 1, "name": "Default", "cutoff": None, "originalFormat": False, "tag": None,
             "mustContain": [], "mustNotContain": [],
             "items": [{"id": i + 1, "language": l.strip(), "audio_exclude": "False", "hi": "False",
                        "forced": "False", "audio_only_include": "False"} for i, l in enumerate(langs)]}]
    B("/api/system/settings", [("languages-profiles", json.dumps(prof)),
                               ("settings-general-serie_default_profile", "1"),
                               ("settings-general-movie_default_profile", "1")])
    # form auth
    B("/api/system/settings", [("settings-auth-type", "form"),
                               ("settings-auth-username", sec.get("BAZARR_USER", "admin")),
                               ("settings-auth-password", sec.get("BAZARR_PASS", ""))])
    log.info("Bazarr configured")

def _bazarr_key(cfg):
    p = os.path.join(cfg["CONFIG_DIR"], "bazarr", "config", "config.yaml")
    for _ in range(30):
        if os.path.exists(p):
            for line in open(p):
                m = line.strip()
                if m.startswith("apikey:"): return m.split(":", 1)[1].strip()
        time.sleep(3)
    return None

# ---------------- Jellyfin ----------------
def _jf_auth_header():
    return {"X-Emby-Authorization": 'MediaBrowser Client="installer", Device="cli", DeviceId="inst1", Version="1.0"'}

def wire_jellyfin(cfg, sec):
    url = f"http://localhost:{port(cfg,'JELLYFIN_PORT','8096')}"
    wait(url + "/health", "Jellyfin")
    # first user = admin from MEDIAUSER_1, else fall back to shared jellyfin creds
    users = _media_users(cfg, sec)
    admin = next((u for u in users if u["admin"]), None) or {"user": sec.get("JELLYFIN_USER", "admin"), "pw": sec.get("JELLYFIN_PASS", "")}
    # startup wizard (only runs on fresh install)
    st, _ = H("GET", url + "/Startup/Configuration", headers=_jf_auth_header(), expect_json=False)
    if st == 200:
        H("POST", url + "/Startup/Configuration", headers=_jf_auth_header(),
          data={"UICulture": "en-US", "MetadataCountryCode": "US", "PreferredMetadataLanguage": "en"}, expect_json=False)
        H("GET", url + "/Startup/User", headers=_jf_auth_header(), expect_json=False)
        H("POST", url + "/Startup/User", headers=_jf_auth_header(),
          data={"Name": admin["user"], "Password": admin["pw"]}, expect_json=False)
        H("POST", url + "/Startup/RemoteAccess", headers=_jf_auth_header(),
          data={"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False}, expect_json=False)
        H("POST", url + "/Startup/Complete", headers=_jf_auth_header(), data=b"", expect_json=False)
        log.info("Jellyfin wizard complete (admin %s)", admin["user"])
    # authenticate
    st, auth = H("POST", url + "/Users/AuthenticateByName", headers=_jf_auth_header(),
                 data={"Username": admin["user"], "Pw": admin["pw"]})
    if not isinstance(auth, dict): log.warning("Jellyfin admin auth failed; skipping rest"); return
    tok = auth["AccessToken"]; T = {"X-Emby-Token": tok}
    # libraries (idempotent: skip any that already exist, else re-running duplicates them as Movies2/Shows2…)
    st, existing = H("GET", url + "/Library/VirtualFolders", headers=T)
    have = {l.get("Name") for l in existing} if isinstance(existing, list) else set()
    for name, ctype, path in (("Movies", "movies", "/data/media/movies"), ("Shows", "tvshows", "/data/media/tv")):
        if name in have:
            log.info("Jellyfin library %s already exists", name); continue
        H("POST", url + f"/Library/VirtualFolders?name={urllib.parse.quote(name)}&collectionType={ctype}&paths={urllib.parse.quote(path)}&refreshLibrary=false",
          headers=T, data=b"", expect_json=False)
    # hardware transcode if /dev/dri present
    if os.path.exists("/dev/dri"):
        st, enc = H("GET", url + "/System/Configuration/encoding", headers=T)
        if isinstance(enc, dict):
            enc["HardwareAccelerationType"] = "vaapi"; enc["VaapiDevice"] = "/dev/dri/renderD128"
            enc["EnableHardwareEncoding"] = True
            H("POST", url + "/System/Configuration/encoding", headers=T, data=enc, expect_json=False)
    # extra users
    st, existing = H("GET", url + "/Users", headers=T)
    have = {u["Name"] for u in (existing or [])}
    for u in users:
        if u["admin"] or u["user"] in have: continue
        st, nu = H("POST", url + "/Users/New", headers=T, data={"Name": u["user"], "Password": u["pw"]})
        if isinstance(nu, dict):
            H("POST", url + f"/Users/{nu['Id']}/Password", headers=T, data={"CurrentPw": "", "NewPw": u["pw"]}, expect_json=False)
            log.info("Jellyfin user %s created", u["user"])
    # Intro Skipper (best-effort)
    _install_intro_skipper(url, T, cfg)
    _connect_arrs_to_jellyfin(url, T, cfg)
    log.info("Jellyfin configured")

def _wants_delete_events(cs):
    """Turn on every on*Delete trigger the connection offers (a purged title must leave Jellyfin as fast as an import
    reaches it; upgrades excluded — that scan follows the import anyway). True when something changed."""
    changed = False
    for k in list(cs):
        if k.startswith("on") and "Delete" in k and "ForUpgrade" not in k and cs.get(k) is False:
            cs[k] = True; changed = True
    return changed

def _connect_arrs_to_jellyfin(url, T, cfg):
    """Register a Jellyfin 'Connect' in Radarr + Sonarr so each import — and each deletion — triggers a
    targeted Jellyfin library scan. Without this, imported files only appear on Jellyfin's next
    scheduled scan (its real-time watcher usually can't see changes across a Docker bind mount) and a
    purged title lingers there until then."""
    st, keys = H("GET", url + "/Auth/Keys", headers=T)          # get-or-create a persistent key
    items = keys.get("Items", []) if isinstance(keys, dict) else []
    jkey = next((k["AccessToken"] for k in items if k.get("AppName") == "arr-stack"), None)
    if not jkey:
        H("POST", url + "/Auth/Keys?App=arr-stack", headers=T, data=b"", expect_json=False)
        st, keys = H("GET", url + "/Auth/Keys", headers=T)
        items = keys.get("Items", []) if isinstance(keys, dict) else []
        jkey = next((k["AccessToken"] for k in items if k.get("AppName") == "arr-stack"), None)
    if not jkey:
        log.warning("could not obtain a Jellyfin API key; skipping arr->Jellyfin connect"); return
    for app, penv, dport in (("radarr", "RADARR_PORT", "7878"), ("sonarr", "SONARR_PORT", "8989")):
        base = f"http://localhost:{port(cfg, penv, dport)}/api/v3"; Hh = {"X-Api-Key": apikey(cfg, app)}
        st, existing = H("GET", base + "/notification", headers=Hh)
        have = next((n for n in (existing or []) if n.get("name") == "Jellyfin"), None)
        if have:
            if _wants_delete_events(have):   # an older install: turn the delete triggers on
                H("PUT", base + "/notification/%d" % have["id"], headers=Hh, data=have); log.info("%s: Jellyfin connection now scans on delete too", app)
            else: log.info("%s already has a Jellyfin connection", app)
            continue
        st, sch = H("GET", base + "/notification/schema", headers=Hh)
        mb = [s for s in (sch or []) if s.get("implementation") == "MediaBrowser"]
        if not mb: log.warning("%s has no MediaBrowser notification type", app); continue
        cs = json.loads(json.dumps(mb[0])); cs["name"] = "Jellyfin"
        for t in ("onDownload", "onUpgrade", "onRename", "onImportComplete"):
            if t in cs: cs[t] = True
        for t in ("onGrab", "onHealthIssue"):
            if t in cs: cs[t] = False
        _wants_delete_events(cs)
        for f in cs.get("fields", []):
            if f["name"] == "host": f["value"] = "jellyfin"
            elif f["name"] == "port": f["value"] = 8096
            elif f["name"] == "apiKey": f["value"] = jkey
            elif f["name"] == "updateLibrary": f["value"] = True
        st, _ = H("POST", base + "/notification", headers=Hh, data=cs)
        log.info("%s -> Jellyfin library-scan connection added (%s)", app, st)

def _install_intro_skipper(url, T, cfg):
    st, plugins = H("GET", url + "/Plugins", headers=T)
    if any("ntro" in p.get("Name", "") for p in (plugins or [])): return
    st, repos = H("GET", url + "/Repositories", headers=T)
    repos = repos if isinstance(repos, list) else []
    if not any("iamparadox" in r.get("Url", "") for r in repos):
        repos.append({"Name": "Intro Skipper", "Url": "https://www.iamparadox.dev/jellyfin/plugins/manifest.json", "Enabled": True})
        H("POST", url + "/Repositories", headers=T, data=repos, expect_json=False); time.sleep(8)
    st, pkgs = H("GET", url + "/Packages", headers=T)
    isk = next((p for p in (pkgs or []) if p.get("guid") == "c83d86bba1e04c35a113e2101cf4ee6b"), None)
    if isk:
        ver = isk["versions"][0]["version"]
        H("POST", url + f"/Packages/Installed/Intro%20Skipper?AssemblyGuid=c83d86bba1e04c35a113e2101cf4ee6b&Version={ver}",
          headers=T, data=b"", expect_json=False)
        log.info("Intro Skipper install triggered (restart Jellyfin to load)")

# ---------------- Jellyseerr ----------------
def wire_jellyseerr(cfg, sec):
    import http.cookiejar
    url = f"http://localhost:{port(cfg,'JELLYSEERR_PORT','5055')}"
    wait(url + "/api/v1/status", "Jellyseerr")
    cj = http.cookiejar.CookieJar(); op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    users = _media_users(cfg, sec)
    admin = next((u for u in users if u["admin"]), None)
    if not admin: return
    st, _ = H("POST", url + "/api/v1/auth/jellyfin", data={"username": admin["user"], "password": admin["pw"],
              "hostname": "jellyfin", "port": 8096, "useSsl": False, "urlBase": "", "serverType": 2}, opener=op)
    # enable libraries + initialize
    H("GET", url + "/api/v1/settings/jellyfin/library?sync=true", opener=op, expect_json=False)
    st, libs = H("GET", url + "/api/v1/settings/jellyfin/library", opener=op)
    if isinstance(libs, list) and libs:
        ids = ",".join(l["id"] for l in libs)
        H("GET", url + f"/api/v1/settings/jellyfin/library?enable={ids}", opener=op, expect_json=False)
    H("POST", url + "/api/v1/settings/initialize", opener=op, data=b"", expect_json=False)
    # connect Radarr + Sonarr
    rk = apikey(cfg, "radarr"); sk = apikey(cfg, "sonarr")
    st, servers = H("GET", url + "/api/v1/settings/radarr", opener=op)
    if isinstance(servers, list) and not servers:
        H("POST", url + "/api/v1/settings/radarr", opener=op, data={"name": "Radarr", "hostname": "radarr",
          "port": 7878, "apiKey": rk, "useSsl": False, "baseUrl": "", "activeProfileId": 1, "activeProfileName": "Any",
          "activeDirectory": "/data/media/movies", "is4k": False, "minimumAvailability": "released", "isDefault": True,
          "syncEnabled": True, "preventSearch": False})
    st, servers = H("GET", url + "/api/v1/settings/sonarr", opener=op)
    if isinstance(servers, list) and not servers:
        H("POST", url + "/api/v1/settings/sonarr", opener=op, data={"name": "Sonarr", "hostname": "sonarr",
          "port": 8989, "apiKey": sk, "useSsl": False, "baseUrl": "", "activeProfileId": 1, "activeProfileName": "Any",
          "activeDirectory": "/data/media/tv", "activeAnimeProfileId": 1, "activeAnimeProfileName": "Any",
          "activeAnimeDirectory": "/data/media/tv", "is4k": False, "isDefault": True, "enableSeasonFolders": True,
          "syncEnabled": True, "preventSearch": False})
    # import users + set auto-approve
    st, jfusers = H("GET", url + "/api/v1/settings/jellyfin/users", opener=op)
    ids = [u["id"] for u in (jfusers or [])] if isinstance(jfusers, list) else []
    if ids: H("POST", url + "/api/v1/user/import-from-jellyfin", opener=op, data={"jellyfinUserIds": ids})
    st, allu = H("GET", url + "/api/v1/user?take=100", opener=op)
    umap = {u.get("jellyfinUsername"): u for u in (allu.get("results", []) if isinstance(allu, dict) else [])}
    # 32 REQUEST | 128/256/512 AUTO_APPROVE(+movie/tv) | 2048 REQUEST_4K_MOVIE
    # | 8192 REQUEST_ADVANCED (shows the quality-profile / root-folder options in the request dialog)
    for mu in users:
        ju = umap.get(mu["user"])
        if not ju: continue
        if mu["admin"]:
            # the owner must stay ADMIN (2 = all permissions); never downgrade it to a request-only mask
            H("PUT", url + f"/api/v1/user/{ju['id']}", opener=op, data={"permissions": 2})
        elif mu["autoapprove"]:
            H("PUT", url + f"/api/v1/user/{ju['id']}", opener=op, data={"permissions": 32 | 128 | 256 | 512 | 2048 | 8192})
    log.info("Jellyseerr configured")

# ---------------- shared ----------------
def _media_users(cfg, sec):
    out = []
    for i in range(1, int(cfg.get("MEDIAUSER_COUNT", "1")) + 1):
        v = sec.get(f"MEDIAUSER_{i}")
        if not v: continue
        parts = v.split("|")
        out.append({"user": parts[0], "pw": parts[1], "autoapprove": parts[2] == "true", "admin": parts[3] == "true"})
    return out
