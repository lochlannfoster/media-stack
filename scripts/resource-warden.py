#!/usr/bin/env python3
# Load / RAM / swap / iowait watchdog -> ntfy admin. Cron ~5 min; 30-min re-warn cooldown.
import os, time
from warden_lib import push, load_state, save_state

NCPU = os.cpu_count() or 4
load1 = os.getloadavg()[0]
mem = {}
for line in open("/proc/meminfo"):
    k, v = line.split(":", 1); mem[k] = int(v.strip().split()[0])
swap_total = mem.get("SwapTotal", 0)
swap_used = 100 * (swap_total - mem.get("SwapFree", 0)) / swap_total if swap_total else 0
mem_avail = 100 * mem.get("MemAvailable", 0) / mem.get("MemTotal", 1)

def cpu(): return list(map(int, open("/proc/stat").readline().split()[1:]))
a = cpu(); time.sleep(2); b = cpu(); dt = sum(b) - sum(a)
iowait = 100 * (b[4] - a[4]) / dt if dt else 0

alerts = []
if load1 > NCPU * 1.5: alerts.append(f"load {load1:.1f} ({NCPU} cores)")
if swap_used > 50: alerts.append(f"swap {swap_used:.0f}% used")
if mem_avail < 8: alerts.append(f"only {mem_avail:.0f}% RAM free")
if iowait > 60: alerts.append(f"iowait {iowait:.0f}%")

st = load_state("resource"); now = time.time()
if alerts:
    if not st.get("active") or (now - st.get("last", 0)) > 1800:
        push("admin", "High resource usage", "Host strained: " + "; ".join(alerts), tags="warning,chart_with_upwards_trend", priority="high")
        save_state("resource", {"active": True, "last": now})
    else:
        save_state("resource", {"active": True, "last": st.get("last", now)})
else:
    if st.get("active"):
        push("admin", "Resources normal", "Load/memory/IO recovered.", tags="white_check_mark", priority="low")
    save_state("resource", {"active": False, "last": now})
