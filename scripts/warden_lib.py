"""Shared helpers for the cron jobs. Config comes from $WARDEN_ENV (the scripts themselves are secret-free).
API keys are read live from each app's config.xml so they never need to be stored twice."""
import json, os, shlex, socket, time, urllib.request, urllib.parse, urllib.error
import xml.etree.ElementTree as ET
socket.setdefaulttimeout(30)   # no warden call may hang a cron slot forever (opener.open() has no per-call timeout)

def load_env(path=None):
    path = path or os.environ.get("WARDEN_ENV", "")
    d = {}
    if path and os.path.exists(path):
        for line in open(path):
            line = line.rstrip("\n")
            if line and not line.lstrip().startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                try:
                    v = shlex.split(v)[0] if v.strip() else ""
                except Exception:
                    v = v.strip()
                d[k.strip()] = v
    # merge dashboard overrides (quiet-hours / ntfy topics / subtitle langs set live from the panel)
    cfgdir = d.get("CONFIG_DIR")
    local = os.path.join(cfgdir, "controllarr", "settings.local") if cfgdir else ""
    if local and os.path.exists(local):
        for line in open(local):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1); d[k.strip()] = v.strip()
    return d

E = load_env()
HOST = E.get("SERVER_HOST", "localhost")
CONFIG_DIR = E.get("CONFIG_DIR", "/srv/media/config")

def _port(k, d): return E.get(k, d)

def apikey(app):
    p = os.path.join(CONFIG_DIR, app, "config.xml")
    try:
        return ET.parse(p).getroot().findtext("ApiKey")
    except Exception:
        return E.get(f"{app.upper()}_APIKEY", "")

def http(method, url, headers=None, data=None, opener=None, timeout=60, expect_json=True):
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
        # HTTP error: return None as the body when JSON was expected so callers that iterate the
        # result don't crash on a str; the status code carries the failure
        return e.code, (None if expect_json else e.read().decode()[:300])
    except Exception as e:
        return None, (None if expect_json else str(e))

def arr(app, path, method="GET", data=None):
    ports = {"radarr": _port("RADARR_PORT", "7878"), "sonarr": _port("SONARR_PORT", "8989")}
    return http(method, f"http://localhost:{ports[app]}/api/v3{path}",
                headers={"X-Api-Key": apikey(app)}, data=data)

def state_path(name): return os.path.join(CONFIG_DIR, f".{name}-state.json")
def load_state(name):
    p = state_path(name)
    try: return json.load(open(p))
    except Exception: return {}
def save_state(name, d):
    try: json.dump(d, open(state_path(name), "w"))
    except Exception: pass

def _quiet_now():
    try:
        h = time.localtime().tm_hour
        a = int(E.get("NOTIFY_QUIET_START", "0")); b = int(E.get("NOTIFY_QUIET_END", "9"))
        return a <= h < b if a <= b else (h >= a or h < b)
    except Exception:
        return False

def push(topic, title, body, tags="", priority="default", click="", attach=""):
    """Send an ntfy notification. `topic` is 'media' or 'admin' (mapped via env).
    On the media topic during quiet hours, priority is forced to 'min' (silent)."""
    if E.get("ENABLE_NOTIFY", "true") != "true":
        return
    real = E.get("NTFY_TOPIC_MEDIA", "media") if topic == "media" else E.get("NTFY_TOPIC_ADMIN", "admin")
    base = (E.get("NTFY_URL") or f"http://localhost:{_port('NTFY_PORT', '8090')}").rstrip("/")
    if topic == "media" and _quiet_now():
        priority = "min"
    try: title.encode("latin-1")                      # HTTP headers are latin-1; ntfy accepts RFC 2047 for anything else
    except UnicodeEncodeError:
        import base64; title = "=?UTF-8?B?" + base64.b64encode(title.encode()).decode() + "?="
    headers = {"Title": title, "Tags": tags, "Priority": priority}
    if click: headers["Click"] = click
    if attach: headers["Attach"] = attach
    http("POST", f"{base}/{real}", headers=headers, data=body.encode(), expect_json=False, timeout=15)
