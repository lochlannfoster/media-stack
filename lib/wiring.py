#!/usr/bin/env python3
"""Idempotent post-up configuration for the media stack.

Reads .env + secrets.env, waits for services, then reproduces the manual wiring: Radarr and Sonarr
(root folders, quality and size rules, UI login), Bazarr, Jellyfin (users, libraries, transcoding,
Intro Skipper, the arr connections that scan on import and on delete) and Jellyseerr.

Whatever fetches releases for the arrs is yours to add — this installer never touches an indexer or a
download client. An overlay may wire its own (install.sh, `wiring.sh`).

Everything is logged at DEBUG to the shared logfile; INFO to console. Re-runnable.
"""
import argparse, json, logging, os, re, shlex, sys, time, urllib.request, urllib.parse, urllib.error, xml.etree.ElementTree as ET
import http.cookiejar as _cookiejar   # aliased: the http() function below shadows the `http` module name
# settings_ops is the ONE writer of quality/size/language settings, and it lives in the control panel's
# repository (install.sh clones it into ./controllarr) — so a fresh install and a Settings save in the
# panel produce identical Radarr/Sonarr configuration, with no second copy to drift.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "controllarr", "app"))
import settings_ops

log = logging.getLogger("wiring")

# ---------------- config loading ----------------
def load_env(path):
    """Parse KEY=VALUE files. Values may be POSIX single-quoted (secrets.env) — shlex unquotes them."""
    d = {}
    if os.path.exists(path):
        for line in open(path):
            line = line.rstrip("\n")
            if line and not line.lstrip().startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                try:
                    v = shlex.split(v)[0] if v.strip() else ""
                except Exception:
                    v = v.strip()
                d[k.strip()] = v
    return d

CFG, SEC = {}, {}
def cfg(k, default=None): return CFG.get(k, default)
def sec(k, default=None): return SEC.get(k, default)

# ---------------- http helpers ----------------
def http(method, url, headers=None, data=None, opener=None, timeout=60, expect_json=True):
    h = dict(headers or {})
    body = None
    if data is not None:
        if isinstance(data, (dict, list)):
            body = json.dumps(data).encode(); h.setdefault("Content-Type", "application/json")
        elif isinstance(data, bytes):
            body = data
        else:
            body = str(data).encode()
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    op_open = opener.open if opener is not None else urllib.request.urlopen
    try:
        with op_open(req, timeout=timeout) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if expect_json and raw else raw)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()[:300]
        log.debug("HTTP %s %s -> %s %s", method, url, e.code, raw)
        return e.code, raw
    except Exception as e:
        log.debug("HTTP %s %s -> ERR %s", method, url, e)
        return None, str(e)

def wait_up(url, name, tries=60, headers=None):
    for _ in range(tries):
        st, _ = http("GET", url, headers=headers, expect_json=False, timeout=8)
        if st and st < 500:
            log.info("%s is up", name); return True
        time.sleep(3)
    log.error("%s did not come up: %s", name, url); return False

HOST = None  # SERVER_HOST
def base(port_env, default):
    return f"http://localhost:{cfg(port_env, default)}"

# ---------------- read arr api keys from config.xml ----------------
def read_apikey(app):
    path = os.path.join(cfg("CONFIG_DIR"), app, "config.xml")
    for _ in range(40):
        if os.path.exists(path):
            try:
                key = ET.parse(path).getroot().findtext("ApiKey")
                if key:
                    SEC[f"{app.upper()}_APIKEY"] = key
                    return key
            except Exception:
                pass
        time.sleep(3)
    raise RuntimeError(f"could not read {app} API key from {path}")

def arr_req(base_url, key, path, method="GET", data=None):
    return http(method, base_url + path, headers={"X-Api-Key": key}, data=data)

def arr(app, path, method="GET", data=None):
    """settings_ops-compatible accessor: reach an arr on the host via its published port."""
    port_env, dflt = {"radarr": ("RADARR_PORT", "7878"), "sonarr": ("SONARR_PORT", "8989")}[app]
    return arr_req(base(port_env, dflt) + "/api/v3", read_apikey(app), path, method, data)

# ---------------- Radarr / Sonarr ----------------
def wire_arr(app, port_env, default_port, root_path, is_tv):
    url = base(port_env, default_port)
    wait_up(url + "/ping", app)
    key = read_apikey(app)
    apiv = "/api/v3"
    def R(path, method="GET", data=None): return arr_req(url + apiv, key, path, method, data)

    # root folder
    st, roots = R("/rootfolder")
    if not any(r.get("path") == root_path for r in (roots or [])):
        R("/rootfolder", "POST", {"path": root_path})
        log.info("%s root folder %s added", app, root_path)

    _wire_arr_content(app, R)
    log.info("%s wired", app)

def _wire_arr_content(app, R):
    """Quality, size, language, media management and the UI login — everything that does not depend on a client."""
    # via the shared settings_ops writer, so the panel and this installer agree.
    # AUDIO_LANGUAGE "Original" = the title's native language (anime -> Japanese, US shows -> English);
    # dubbed releases get a heavy custom-format penalty on both apps.
    content = {"size_cap": cfg("SIZE_CAP_MBPM", "20"), "size_max": cfg("SIZE_MAX_MBPM") or "",
               "audio_language": cfg("AUDIO_LANGUAGE", "Original"),
               "allow_unknown": cfg("ALLOW_UNKNOWN_QUALITY", "false") == "true",
               "prefer_h264": cfg("PREFER_H264", "true") == "true"}
    errs = settings_ops.apply_content(content, arr, apps=(app,), log=log.info)
    for e in errs: log.warning("%s: %s", app, e)
    # media management: import extra files (subs)
    st, mm = R("/config/mediamanagement")
    if mm and not mm.get("importExtraFiles"):
        mm["importExtraFiles"] = True; mm["extraFileExtensions"] = "srt,sub,idx,ass,ssa"
        R("/config/mediamanagement/%d" % mm["id"], "PUT", mm)
    # UI login: the installer asks for RADARR_/SONARR_USER + _PASS; enable forms auth once (a password that is
    # already set is never rotated). Everything else reaches the arrs with the API key, so nothing breaks.
    from wiring_media import _arr_style_auth
    _arr_style_auth(R, "/config/host", sec(f"{app.upper()}_USER"), sec(f"{app.upper()}_PASS"), name=app)

# (quality / size / language live in the control panel's settings_ops.py — one writer for both.
#  Size semantics: SIZE_CAP_MBPM is the *preferred* size; the hard max defaults to max(1.25×cap, 50) MB/min
#  so normal 1080p (30-60 MB/min) still clears.)

# ---------------- orchestration ----------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", required=True); ap.add_argument("--secrets", required=True); ap.add_argument("--logfile", required=True)
    a = ap.parse_args()
    global CFG, SEC, HOST
    CFG = load_env(a.env); SEC = load_env(a.secrets)
    CFG["STACK_DIR"] = os.path.dirname(os.path.abspath(a.env))   # the install directory, for anything an overlay adds
    HOST = cfg("SERVER_HOST")
    logging.basicConfig(level=logging.DEBUG, filename=a.logfile,
                        format="%(asctime)s [wiring:%(levelname)s] %(message)s")
    console = logging.StreamHandler(); console.setLevel(logging.INFO)
    console.setFormatter(logging.Formatter("    %(message)s")); log.addHandler(console)

    try:
        wire_arr("radarr", "RADARR_PORT", "7878", "/data/media/movies", is_tv=False)
        wire_arr("sonarr", "SONARR_PORT", "8989", "/data/media/tv", is_tv=True)
        # Bazarr, Jellyfin and Jellyseerr are wired by a companion module, kept separate to stay readable
        from wiring_media import wire_bazarr, wire_jellyfin, wire_jellyseerr
        wire_bazarr(CFG, SEC)
        wire_jellyfin(CFG, SEC)
        wire_jellyseerr(CFG, SEC)
    except Exception as e:
        log.exception("wiring error: %s", e); sys.exit(1)
    log.info("wiring complete")

if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
