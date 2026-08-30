#!/usr/bin/env python3
# Once-a-day summary -> ntfy admin.
import os, time, shutil
from warden_lib import arr, push, E, HOST

def added_today(app):
    st, h = arr(app, "/history?pageSize=200&sortKey=date&sortDirection=descending&eventType=3")
    if not isinstance(h, dict): return 0
    cut = time.time() - 86400; n = 0
    for r in h.get("records", []):
        try:
            if time.mktime(time.strptime(r.get("date", "")[:19], "%Y-%m-%dT%H:%M:%S")) >= cut: n += 1
        except Exception: pass
    return n

movies = added_today("radarr"); eps = added_today("sonarr")
_dd = E.get("DATA_DIR", "")
du = shutil.disk_usage(_dd if _dd and os.path.isdir(_dd) else "/"); disk = round(100 * du.used / du.total); free = du.free / 1e9
def queued(app):
    st, q = arr(app, "/queue?pageSize=500")
    return len((q or {}).get("records", [])) if isinstance(q, dict) else 0
body = (f"Added today: {movies} movies, {eps} episodes.\nDisk: {disk}% used ({free:.0f} GB free).\n"
        f"In the queue: {queued('radarr') + queued('sonarr')}.")
push("admin", "Daily media digest", body, tags="newspaper", priority="low",
     click=f"http://{HOST}:{E.get('CONTROLLARR_PORT','3002')}")
