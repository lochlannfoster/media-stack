#!/usr/bin/env python3
# Container availability -> ntfy admin. Expected list comes from EXPECTED_CONTAINERS in $WARDEN_ENV
# (generated from the actually-enabled services, so no false alarms on optional ones).
import subprocess
from warden_lib import push, load_state, save_state, E

expected = [c for c in E.get("EXPECTED_CONTAINERS", "").split(",") if c]
try:
    # `docker ps` also lists restarting/paused containers — only a genuinely running, non-unhealthy one counts
    out = subprocess.check_output(["docker", "ps", "-a", "--format", "{{.Names}}\t{{.State}}\t{{.Status}}"], timeout=30).decode()
    running = set()
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1] == "running" and "(unhealthy)" not in (parts[2] if len(parts) > 2 else ""):
            running.add(parts[0])
except Exception:
    push("admin", "Docker unreachable", "Cannot query Docker on the host.", tags="rotating_light", priority="urgent")
    raise SystemExit

down = [c for c in expected if c not in running]
st = load_state("avail"); prev = set(st.get("down", []))
newly = [c for c in down if c not in prev]
back = [c for c in prev if c not in down]
if newly:
    push("admin", "Service DOWN: " + ", ".join(newly), "Not running: " + ", ".join(newly), tags="rotating_light", priority="high")
if back:
    push("admin", "Service recovered: " + ", ".join(back), "Back up: " + ", ".join(back), tags="white_check_mark", priority="low")
save_state("avail", {"down": down})
