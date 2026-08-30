#!/usr/bin/env python3
# Disk-space watchdog -> ntfy admin topic. Cron ~15 min. Config from $WARDEN_ENV.
import os, shutil
from warden_lib import push, load_state, save_state, E

WARN, URGENT, CRIT = 80, 90, 95
_dd = E.get("DATA_DIR", "")
du = shutil.disk_usage(_dd if _dd and os.path.isdir(_dd) else "/")   # the media volume, not the OS disk
used = round(100 * du.used / du.total)
free_gb = du.free / 1e9
st = load_state("disk-alert"); last = st.get("level", 0)

def note(level, title, body, prio, tags):
    push("admin", title, body, tags=tags, priority=prio)
    save_state("disk-alert", {"level": level})

if used >= CRIT and last < CRIT:
    note(CRIT, f"Disk CRITICAL: {used}%", f"Only {free_gb:.0f} GB left. Downloads will fail.", "urgent", "rotating_light")
elif used >= URGENT and last < URGENT:
    note(URGENT, f"Disk high: {used}%", f"{free_gb:.0f} GB left. Consider clearing media.", "high", "warning")
elif used >= WARN and last < WARN:
    note(WARN, f"Disk at {used}%", f"{free_gb:.0f} GB remaining.", "default", "floppy_disk")
elif used < WARN and last >= WARN:
    push("admin", f"Disk OK: {used}%", f"Recovered — {free_gb:.0f} GB free.", tags="white_check_mark", priority="low")
    save_state("disk-alert", {"level": 0})
