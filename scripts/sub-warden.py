#!/usr/bin/env python3
# Keep Bazarr synced + warn when a ready item has no subtitle after a grace period. Cron hourly -> media.
# (Hourly, not every 10 min: each run triggers a provider-wide "wanted" search, and OpenSubtitles-style
#  providers rate-limit / lock accounts that are hammered.)
import os, time, urllib.parse
from warden_lib import http, push, load_state, save_state, E, CONFIG_DIR, HOST

GRACE = 1200
BAZ = f"http://localhost:{E.get('BAZARR_PORT','6767')}"

def bkey():
    p = os.path.join(CONFIG_DIR, "bazarr", "config", "config.yaml")
    try:
        for line in open(p):
            if line.strip().startswith("apikey:"): return line.split(":", 1)[1].strip()
    except Exception: pass
    return ""

BK = bkey()
if not BK: raise SystemExit
HDR = {"X-API-KEY": BK}

def bpost(path, pairs):
    http("POST", BAZ + path, headers={**HDR, "Content-Type": "application/x-www-form-urlencoded"},
         data=urllib.parse.urlencode(pairs, doseq=True).encode(), expect_json=False)
def bget(path):
    st, d = http("GET", BAZ + "/api" + path, headers=HDR); return d if isinstance(d, dict) else {}

def has_sub(item):
    for s in (item.get("subtitles") or []):
        if s.get("path") or s.get("embedded_track_id") is not None: return True
    return False

# evaluate FIRST (what's still missing since last run), then sync + search — the previous order searched and
# immediately re-read pre-search state, so the check never saw the results of its own search
st = load_state("subwarn"); now = time.time(); new = {}; missing = 0
for m in bget("/movies").get("data", []):
    if not m.get("path") or has_sub(m): continue
    missing += 1
    key = f"m{m.get('radarrId')}"; rec = st.get(key, {"first": now, "warned": False}); new[key] = rec
    if not rec["warned"] and (now - rec["first"]) >= GRACE:
        push("media", f"No subtitles: {m.get('title')}", f"{m.get('title')} is ready but no subtitles were found.",
             tags="warning,speech_balloon", priority="high", click=BAZ.replace("localhost", HOST))
        rec["warned"] = True
save_state("subwarn", new)

for t in ("update_movies", "update_series"):
    bpost("/api/system/tasks", [("taskid", t)])
if missing:   # only hit the providers when something is actually wanted
    for t in ("wanted_search_missing_subtitles_movies", "wanted_search_missing_subtitles_series"):
        bpost("/api/system/tasks", [("taskid", t)])
