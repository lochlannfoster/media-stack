#!/usr/bin/env bash
# Preflight checks + host auto-detection. Sourced by install.sh (after common.sh).

preflight_checks() {
  section "Preflight checks"

  step "Checking Docker"
  command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Engine first (https://docs.docker.com/engine/install/), then re-run."
  run "docker info" docker info || die "Docker is installed but not running or you lack permission. Try: sudo systemctl start docker, and add yourself to the 'docker' group."
  step_ok "Docker is available"

  step "Checking Docker Compose plugin"
  docker compose version >/dev/null 2>&1 || die "The 'docker compose' plugin is missing. Install docker-compose-plugin, then re-run."
  step_ok "Docker Compose is available"

  step "Checking host tools"
  command -v python3 >/dev/null 2>&1 || die "python3 is required (the wiring + wardens are Python). Install it, then re-run."
  command -v curl >/dev/null 2>&1 || die "curl is required. Install it, then re-run."
  command -v crontab >/dev/null 2>&1 || step_warn "crontab not found — the automation and backups won't be scheduled (install cron)"
  command -v gpg >/dev/null 2>&1 || step_warn "gpg not found — encrypted backups will fail (install gnupg) if you enable them"
  step_ok "Host tools present"

  step "Checking free disk space"
  local avail_gb
  avail_gb=$(df -Pk "${DATA_PARENT:-/}" 2>/dev/null | awk 'NR==2{printf "%d", $4/1024/1024}')
  log INFO "free disk at ${DATA_PARENT:-/}: ${avail_gb}GB"
  if [ "${avail_gb:-0}" -lt 10 ]; then step_warn "Only ${avail_gb}GB free — media fills up fast"; else step_ok "Free disk: ${avail_gb}GB"; fi
}

# check_port PORT NAME VAR  -> warn (not fatal) if a port is already listening on this host.
# Ports are never prompted: they come from .env (a previous run) or the defaults, so the advice is to edit .env.
check_port() {
  local port="$1" name="$2" var="${3:-*_PORT}"
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"; then
    warn "Port ${port} (${name}) is already in use on this host — the ${name} container may fail to start. Set ${var} in .env to a free port and re-run ./install.sh."
    log WARN "port ${port} (${name}) in use"
    return 1
  fi
  return 0
}

# check_ports_for_profiles PROFILES  -> run check_port for every port the chosen profiles will publish.
# Called after .env is written (it reads the installer's CFG[] values). A port held by one of the stack's own
# containers is skipped — on a re-run the stack itself is the listener. An overlay's ports are added through
# EXTRA_PORT_SPECS. Non-fatal; silent when `ss` is not installed.
_own_container() { docker container inspect "$1" >/dev/null 2>&1; }
check_ports_for_profiles() {
  local profiles=",${1:-}," spec var def name prof port
  command -v ss >/dev/null 2>&1 || return 0
  for spec in "JELLYFIN_PORT 8096 jellyfin" "RADARR_PORT 7878 radarr" "SONARR_PORT 8989 sonarr" \
              "JELLYSEERR_PORT 5055 jellyseerr" "BAZARR_PORT 6767 bazarr" "NTFY_PORT 8090 ntfy notify" \
              "CONTROLLARR_PORT 3002 controllarr" ${EXTRA_PORT_SPECS:+"${EXTRA_PORT_SPECS[@]}"}; do
    read -r var def name prof <<< "$spec"
    if [ -n "$prof" ] && [[ "$profiles" != *",$prof,"* ]]; then continue; fi
    port="${CFG[$var]:-$def}"
    _own_container "$name" && continue
    check_port "$port" "$name" "$var" || true
  done
  return 0
}

# ---- auto-detection (returns via echo) ----
detect_ip() {
  ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1 \
    || hostname -I 2>/dev/null | awk '{print $1}'
}
detect_tz() {
  if [ -f /etc/timezone ]; then cat /etc/timezone
  elif command -v timedatectl >/dev/null 2>&1; then timedatectl show -p Timezone --value 2>/dev/null
  else readlink -f /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##'; fi
}
has_gpu_dri() { [ -d /dev/dri ]; }
