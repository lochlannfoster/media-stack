#!/usr/bin/env bash
# media-stack installer — interactive, idempotent, single-machine.
# Usage: ./install.sh          (interactive)
#        ./install.sh --help
#
# An overlay (see OVERLAY below) may add services, prompts, wiring and cron jobs of its own; without one
# this installs the stack described in README.md and nothing else.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$HERE/install-$(date +%Y%m%d-%H%M%S).log"
ENV_FILE="$HERE/.env"
SECRETS_FILE="$HERE/secrets.env"
# An optional site overlay: a directory with any of overlay.env (defaults), prompts.sh, compose.yml,
# wiring.sh, cron.sh. MEDIA_STACK_OVERLAY points at it; each hook is sourced or read where it belongs.
OVERLAY="${MEDIA_STACK_OVERLAY:-}"

# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
source "$HERE/lib/preflight.sh"

[ "${1:-}" = "--help" ] && {
  cat <<'H'
media-stack installer.
  ./install.sh            Interactive install (prompts for everything).
  ./install.sh --help     This help.
Everything is logged to install-<timestamp>.log in this directory.
Re-running is safe (idempotent) — it updates rather than duplicates.
MEDIA_STACK_OVERLAY=<dir> adds that overlay's services, prompts, wiring and cron jobs.
H
  exit 0
}

echo "media-stack installer — full log: $LOGFILE"
log INFO "installer started; overlay: ${OVERLAY:-none}"
[ -n "$OVERLAY" ] && [ ! -d "$OVERLAY" ] && die "MEDIA_STACK_OVERLAY=$OVERLAY is not a directory."

# ---------------------------------------------------------------------------
# 1. PREFLIGHT
# ---------------------------------------------------------------------------
DATA_PARENT="/srv"
preflight_checks
command -v git >/dev/null 2>&1 || die "git is required (the control panel is cloned from its own repository)."

# ---------------------------------------------------------------------------
# 2. PROMPTS  -> .env (config) + secrets.env (passwords)
# ---------------------------------------------------------------------------
declare -A CFG           # config values -> .env
declare -A SEC           # secrets       -> secrets.env
declare -A OLD           # values from a previous run (.env + secrets.env): prompt defaults + kept secrets
set_cfg() { CFG["$1"]="$2"; }
set_sec() { SEC["$1"]="$2"; }
# Re-runs are idempotent at the CONFIG level too: previous answers become the defaults and existing secrets
# are kept, so re-running never rotates passwords behind the services' backs or wipes hand-set knobs.
load_old() { [ -f "$1" ] || return 0
  while IFS=$'\t' read -r k v; do [ -n "$k" ] && OLD["$k"]="$v"; done < <(python3 - "$1" <<'PY'
import sys, shlex
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if not line or line.lstrip().startswith("#") or "=" not in line: continue
    k, v = line.split("=", 1)
    try: v = shlex.split(v)[0] if v.strip() else ""
    except Exception: v = v.strip()
    print(k.strip() + "\t" + v.replace("\t", " ").replace("\n", " "))
PY
); }
load_old "$ENV_FILE"; load_old "$SECRETS_FILE"
[ -n "$OVERLAY" ] && [ -f "$OVERLAY/overlay.env" ] && load_old "$OVERLAY/overlay.env"   # the overlay's defaults, lowest priority
d()     { printf '%s' "${OLD[$1]:-$2}"; }                                   # d KEY default   -> prompt default
dyn()   { case "${OLD[$1]:-$2}" in true|y|yes|Y) echo y;; *) echo n;; esac; } # dyn KEY y|n     -> yes/no default
dprof() { case ",${OLD[COMPOSE_PROFILES]:-}," in *,"$1",*) echo y;; *) [ -n "${OLD[COMPOSE_PROFILES]:-}" ] && echo n || echo "$2";; esac; }
[ ${#OLD[@]} -gt 0 ] && info "Existing configuration found — previous answers are the defaults; existing passwords are kept."

section "Basic settings"
DEF_IP="$(detect_ip)"; ask SERVER_HOST "Host IP/name for URLs" "$(d SERVER_HOST "${DEF_IP:-127.0.0.1}")"; set_cfg SERVER_HOST "$SERVER_HOST"
DEF_TZ="$(detect_tz)"; ask TZv "Timezone" "$(d TZ "${DEF_TZ:-Etc/UTC}")"; set_cfg TZ "$TZv"
ask PUIDv "File owner UID" "$(d PUID "$(id -u)")"; set_cfg PUID "$PUIDv"
ask PGIDv "File owner GID" "$(d PGID "$(id -g)")"; set_cfg PGID "$PGIDv"
ask_path CONFIG_DIR "Config directory (app data/databases)" "$(d CONFIG_DIR /srv/media/config)" /srv/media/config; set_cfg CONFIG_DIR "$CONFIG_DIR"
ask_path DATA_DIR "Data directory (the media library)" "$(d DATA_DIR /srv/media/data)" /srv/media/data; set_cfg DATA_DIR "$DATA_DIR"

section "Core services"
info "Always installed: Jellyfin, Jellyseerr, Radarr, Sonarr, Bazarr, autoheal and Controllarr (the control panel)."
if [ -n "${OLD[CONTROLLARR_PASSWORD]:-}" ]; then
  set_sec CONTROLLARR_PASSWORD "${OLD[CONTROLLARR_PASSWORD]}"; info "Control-panel password: keeping the existing one"
else
  ask_hidden CONTROLLARR_PW "Control-panel admin password (hidden; blank = no login — every visitor is an admin)"
  set_sec CONTROLLARR_PASSWORD "$CONTROLLARR_PW"
fi
set_cfg CONTROLLARR_REPO "$(d CONTROLLARR_REPO https://github.com/lochlannfoster/controllarr.git)"
set_cfg CONTROLLARR_REF  "$(d CONTROLLARR_REF main)"

section "Optional services"
PROFILES=()
yesno "Install phone notifications (ntfy)?" "$(dprof notify y)" && PROFILES+=("notify"); WITH_NOTIFY=$?

# ---- overlay prompts: may append to PROFILES and set CFG/SEC of its own ----
if [ -n "$OVERLAY" ] && [ -f "$OVERLAY/prompts.sh" ]; then
  # shellcheck disable=SC1090
  source "$OVERLAY/prompts.sh"
fi
set_cfg COMPOSE_PROFILES "$(IFS=,; echo "${PROFILES[*]}")"

section "Remote access (optional, recommended)"
TAILSCALE_ENABLED=false; TS_KEY=""
declare -A OLDTS; if [ -f "$HERE/tailscale.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do case "$line" in ''|'#'*) continue;; esac; [[ "$line" == *=* ]] || continue; OLDTS["${line%%=*}"]="${line#*=}"; done < "$HERE/tailscale.env"
fi
if yesno "Add Tailscale, so you can reach this stack from your own devices without opening a router port?" "$(dyn TAILSCALE_ENABLED n)"; then
  ask TAILSCALE_HOSTNAME "Node name in your tailnet" "$(d TAILSCALE_HOSTNAME mediastack)"
  info "Get an auth key from login.tailscale.com > Settings > Keys > Generate auth key — docs/services/tailscale.md."
  if [ -n "${OLDTS[TS_AUTHKEY]:-}" ] || [ -d "$CONFIG_DIR/tailscale" ]; then
    ask_hidden TS_KEY "Tailscale auth key (hidden; blank = keep the existing login)"
    [ -z "$TS_KEY" ] && TS_KEY="${OLDTS[TS_AUTHKEY]:-}"
  else
    ask_hidden TS_KEY "Tailscale auth key (hidden)"
  fi
  if [ -z "$TS_KEY" ] && [ ! -d "$CONFIG_DIR/tailscale" ]; then
    warn "No auth key given — Tailscale NOT enabled. Re-run ./install.sh once you have one."
  else
    TAILSCALE_ENABLED=true; set_cfg TAILSCALE_ENABLED true; set_cfg TAILSCALE_HOSTNAME "$TAILSCALE_HOSTNAME"
  fi
fi
[ "$TAILSCALE_ENABLED" = true ] || set_cfg TAILSCALE_ENABLED false

section "Credentials"
SERVICES=(jellyfin radarr sonarr bazarr)
if [ -n "${OLD[RADARR_PASS]:-}" ] && yesno "Keep the existing service logins (from the previous run)?" y; then
  for s in "${SERVICES[@]}"; do set_sec "${s^^}_USER" "${OLD[${s^^}_USER]:-admin}"; set_sec "${s^^}_PASS" "${OLD[${s^^}_PASS]:-}"; done
elif yesno "Use ONE shared admin login for all service UIs?" y; then
  ask ADMIN_USER "Shared admin username" "$(d RADARR_USER admin)"
  ask_secret ADMIN_PASS "Shared admin password"
  for s in "${SERVICES[@]}"; do set_sec "${s^^}_USER" "$ADMIN_USER"; set_sec "${s^^}_PASS" "$ADMIN_PASS"; done
else
  for s in "${SERVICES[@]}"; do
    ask u "Username for ${s}" "$(d "${s^^}_USER" admin)"; ask_secret p "Password for ${s}"
    set_sec "${s^^}_USER" "$u"; set_sec "${s^^}_PASS" "$p"
  done
fi

section "Media user accounts (Jellyfin + Jellyseerr)"
ask NUSERS "How many media user accounts?" "$(d MEDIAUSER_COUNT 1)"
for ((i=1;i<=${NUSERS:-1};i++)); do
  if [ -n "${OLD[MEDIAUSER_$i]:-}" ]; then
    set_sec "MEDIAUSER_${i}" "${OLD[MEDIAUSER_$i]}"; info "  Account #$i: keeping '${OLD[MEDIAUSER_$i]%%|*}'"; continue
  fi
  ask uu "  Account #$i username" "user$i"; ask_secret pp "  Account #$i password"
  aa="false"; if yesno "  Can '${uu}' auto-approve their own requests?" n; then aa="true"; fi
  first="false"; [ "$i" = "1" ] && first="true"
  set_sec "MEDIAUSER_${i}" "${uu}|${pp}|${aa}|${first}"   # first account = admin
done
set_cfg MEDIAUSER_COUNT "${NUSERS:-1}"

section "Content preferences"
ask SIZE_CAP_MBPM "Preferred size (MB per minute of runtime; hard max = 1.25x, floor 50)" "$(d SIZE_CAP_MBPM 20)"; set_cfg SIZE_CAP_MBPM "$SIZE_CAP_MBPM"
ask AUDIO_LANGUAGE "Audio language (Original = native language, dubs penalised; or Any/English)" "$(d AUDIO_LANGUAGE Original)"; set_cfg AUDIO_LANGUAGE "$AUDIO_LANGUAGE"
if yesno "Prefer h264 over x265? (yes if the host CPU can't hardware-decode HEVC)" "$(dyn PREFER_H264 y)"; then set_cfg PREFER_H264 true; else set_cfg PREFER_H264 false; fi
ask SUBTITLE_LANGS "Subtitle language codes (comma)" "$(d SUBTITLE_LANGS en)"; set_cfg SUBTITLE_LANGS "$SUBTITLE_LANGS"
if [ -n "${OLD[OPENSUBS_PASS]:-}" ]; then
  set_sec OPENSUBS_USER "${OLD[OPENSUBS_USER]:-}"; set_sec OPENSUBS_PASS "${OLD[OPENSUBS_PASS]}"; info "OpenSubtitles account: keeping the existing one"
elif yesno "Add an OpenSubtitles.com account (better subtitle coverage)?" n; then
  ask osu "  OpenSubtitles username"; ask_secret osp "  OpenSubtitles password"
  set_sec OPENSUBS_USER "$osu"; set_sec OPENSUBS_PASS "$osp"
fi

if [ "$WITH_NOTIFY" = 0 ]; then
  section "Notifications"
  ask NOTIFY_QUIET_START "Quiet-hours START hour (media topic silent, 0-23)" "$(d NOTIFY_QUIET_START 0)"; set_cfg NOTIFY_QUIET_START "$NOTIFY_QUIET_START"
  ask NOTIFY_QUIET_END "Quiet-hours END hour (0-23)" "$(d NOTIFY_QUIET_END 9)"; set_cfg NOTIFY_QUIET_END "$NOTIFY_QUIET_END"
  set_cfg NTFY_TOPIC_MEDIA "$(d NTFY_TOPIC_MEDIA media)"; set_cfg NTFY_TOPIC_ADMIN "$(d NTFY_TOPIC_ADMIN admin)"
fi

section "Automation & backups"
if yesno "Enable self-healing automation (cron jobs that watch the stack)?" "$(dyn ENABLE_WARDENS y)"; then set_cfg ENABLE_WARDENS true; else set_cfg ENABLE_WARDENS false; fi
BACKUP_DEF="$(dirname "$CONFIG_DIR")/backups"
if yesno "Enable nightly encrypted config backups?" "$(dyn ENABLE_BACKUPS y)"; then
  set_cfg ENABLE_BACKUPS true
  ask_path BACKUP_DIR "Backup directory (absolute path)" "$(d BACKUP_DIR "$BACKUP_DEF")" "$BACKUP_DEF"; set_cfg BACKUP_DIR "$BACKUP_DIR"
  set_cfg BACKUP_KEEP "$(d BACKUP_KEEP 7)"
else
  set_cfg ENABLE_BACKUPS false
  # the panel mounts BACKUP_DIR read-only whether or not backups are on, so the path is always written
  case "$(d BACKUP_DIR "$BACKUP_DEF")" in /*) set_cfg BACKUP_DIR "$(d BACKUP_DIR "$BACKUP_DEF")";; *) set_cfg BACKUP_DIR "$BACKUP_DEF";; esac
fi
# knobs that are never prompted but must survive a re-run (ports, refresh interval, ...)
for k in "${!OLD[@]}"; do
  case "$k" in *_PORT|CONTROLLARR_REFRESH|STACK_NAME|SIZE_MAX_MBPM|ALLOW_UNKNOWN_QUALITY|NTFY_URL)
    [ -z "${CFG[$k]:-}" ] && set_cfg "$k" "${OLD[$k]}";; esac
done

# ---- write .env + secrets.env (values single-quoted: safe for docker compose, bash `.` and python shlex) ----
step "Writing configuration"
{ echo "# generated by install.sh $(date) — re-run ./install.sh to change; previous values are the defaults"
  for k in $(printf '%s\n' "${!CFG[@]}" | sort); do printf '%s=%s\n' "$k" "$(sq "${CFG[$k]}")"; done; } > "$ENV_FILE"
{ echo "# secrets — chmod 600, gitignored"; for k in $(printf '%s\n' "${!SEC[@]}" | sort); do printf '%s=%s\n' "$k" "$(sq "${SEC[$k]}")"; done; } > "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"
step_ok "Wrote .env and secrets.env (chmod 600)"
check_ports_for_profiles "${CFG[COMPOSE_PROFILES]:-}"

# ---------------------------------------------------------------------------
# 3. THE CONTROL PANEL, FROM ITS OWN REPOSITORY
# ---------------------------------------------------------------------------
section "Control panel"
step "Fetching Controllarr (${CFG[CONTROLLARR_REF]})"
if [ -d "$HERE/controllarr/.git" ]; then
  ( cd "$HERE/controllarr" && run "controllarr fetch" git fetch --depth 1 origin "${CFG[CONTROLLARR_REF]}" && run "controllarr checkout" git checkout -q FETCH_HEAD )
else
  rm -rf "$HERE/controllarr"
  run "controllarr clone" git clone --depth 1 --branch "${CFG[CONTROLLARR_REF]}" "${CFG[CONTROLLARR_REPO]}" "$HERE/controllarr" \
    || run "controllarr clone" git clone "${CFG[CONTROLLARR_REPO]}" "$HERE/controllarr"
fi
[ -f "$HERE/controllarr/app/controllarr.py" ] || die "Could not fetch Controllarr from ${CFG[CONTROLLARR_REPO]} — check the network, or set CONTROLLARR_REPO in .env to a local clone."
step_ok "Controllarr at $(cd "$HERE/controllarr" && git rev-parse --short HEAD)"

# ---------------------------------------------------------------------------
# 4. GENERATE runtime config (dirs, override)
# ---------------------------------------------------------------------------
section "Preparing directories"
step "Creating config + data directories"
mkdir -p "$CONFIG_DIR"/{jellyfin,radarr,sonarr,bazarr,jellyseerr,controllarr} || die "Cannot create $CONFIG_DIR — check the path and permissions."
mkdir -p "$DATA_DIR"/media/{movies,tv} || die "Cannot create $DATA_DIR — check the path and permissions."
[ "$WITH_NOTIFY" = 0 ] && { mkdir -p "$CONFIG_DIR/ntfy" || die "Cannot create $CONFIG_DIR/ntfy"; }
[ "$TAILSCALE_ENABLED" = true ] && { mkdir -p "$CONFIG_DIR/tailscale" || die "Cannot create $CONFIG_DIR/tailscale"; }
# the notify hooks and the arrs mount this file; create it now so Docker doesn't turn it into a directory
touch "$CONFIG_DIR/controllarr/settings.local"
[ -n "$OVERLAY" ] && [ -f "$OVERLAY/dirs.sh" ] && { # shellcheck disable=SC1090
  source "$OVERLAY/dirs.sh"; }
step_ok "Directories ready"

if [ "$TAILSCALE_ENABLED" = true ]; then
  { echo "TS_STATE_DIR=/var/lib/tailscale"; echo "TS_HOSTNAME=${TAILSCALE_HOSTNAME:-mediastack}"; echo "TS_USERSPACE=false"
    [ -n "$TS_KEY" ] && echo "TS_AUTHKEY=$TS_KEY"; } > "$HERE/tailscale.env"
  chmod 600 "$HERE/tailscale.env"
elif [ -f "$HERE/tailscale.env" ]; then
  rm -f "$HERE/tailscale.env"; info "Tailscale disabled — removed tailscale.env (the auth key)."
fi

# Generated docker-compose.override.yml — GPU passthrough, Tailscale, and anything the overlay adds.
OVR="$HERE/docker-compose.override.yml"; NEED_OVR=false
{
  echo "# generated by install.sh — regenerated on re-run; do not edit by hand"
  echo "services:"
  if has_gpu_dri; then
    NEED_OVR=true
    printf '  jellyfin:\n    devices:\n      - /dev/dri:/dev/dri\n'
  fi
  if [ "$TAILSCALE_ENABLED" = true ]; then
    NEED_OVR=true
    # host networking: the tailnet address reaches every published port of the stack
    printf '  tailscale:\n    image: tailscale/tailscale:latest\n    container_name: tailscale\n    network_mode: host\n'
    printf '    cap_add: [NET_ADMIN, SYS_MODULE]\n    devices: ["/dev/net/tun:/dev/net/tun"]\n    env_file: [./tailscale.env]\n'
    printf '    volumes:\n      - "${CONFIG_DIR}/tailscale:/var/lib/tailscale"\n      - /lib/modules:/lib/modules:ro\n'
    printf '    healthcheck: {test: ["CMD", "tailscale", "status", "--peers=false"], interval: 60s, timeout: 10s, retries: 3, start_period: 60s}\n'
    printf '    labels: [autoheal=true]\n    restart: unless-stopped\n'
  fi
  if [ -n "$OVERLAY" ] && [ -f "$OVERLAY/compose.sh" ]; then
    NEED_OVR=true
    # shellcheck disable=SC1090
    source "$OVERLAY/compose.sh"
  fi
} > "$OVR"
if [ "$NEED_OVR" = true ]; then
  step_ok "Wrote docker-compose.override.yml"
else
  rm -f "$OVR"; info "No override needed."
fi

# ---------------------------------------------------------------------------
# 5. BRING UP + WAIT
# ---------------------------------------------------------------------------
section "Starting the stack"
step "Starting containers (first run downloads ~1-2GB of images — can take a few minutes)"
# A service whose profile was just turned OFF keeps its container: Compose treats it as neither active nor
# an orphan, so `up --remove-orphans` would leave it running. Retire those explicitly.
retire_disabled() {
  local all on s
  all="$(docker compose --env-file "$ENV_FILE" --profile '*' config --services 2>/dev/null)"
  on="$(docker compose --env-file "$ENV_FILE" config --services 2>/dev/null)"
  for s in $all; do
    grep -qx "$s" <<<"$on" && continue
    docker container inspect "$s" >/dev/null 2>&1 || continue
    log INFO "retiring container $s (its profile is off)"
    docker compose --env-file "$ENV_FILE" --profile '*' rm -sf "$s" >>"$LOGFILE" 2>&1 || docker rm -f "$s" >>"$LOGFILE" 2>&1
    info "Stopped and removed $s — its profile is off"
  done
}
( cd "$HERE" && retire_disabled )
( cd "$HERE" && run "compose up" docker compose --env-file "$ENV_FILE" up -d --remove-orphans ) || die "docker compose failed to start the stack."
step_ok "Containers started"

# ---------------------------------------------------------------------------
# 6. WIRING (idempotent API configuration)
# ---------------------------------------------------------------------------
wire_with_progress() {
  local total=6
  python3 "$HERE/lib/wiring.py" --env "$ENV_FILE" --secrets "$SECRETS_FILE" --logfile "$LOGFILE" 2>&1 \
  | { n=0
      while IFS= read -r line; do
        case "$line" in
          *"radarr wired"*|*"sonarr wired"*|*"auth enabled"*|*"Bazarr configured"*|*"Jellyfin configured"*|*"Jellyseerr configured"*|*"wiring complete"*)
            n=$((n+1)); progress_bar "$n" "$total" "${line#"${line%%[![:space:]]*}"}" ;;
        esac
      done; }
  return "${PIPESTATUS[0]}"
}
section "Configuring services (this is the long part)"
step "Configuring Radarr, Sonarr, Bazarr, Jellyfin and Jellyseerr (2-10 min)"
_wire_start=$SECONDS
if wire_with_progress; then
  LAST_RUN_SECS=$((SECONDS - _wire_start)); step_ok "Services wired"
else
  LAST_RUN_SECS=$((SECONDS - _wire_start))
  die "Wiring failed. The stack is up but not fully configured — fix the issue and re-run ./install.sh (it's idempotent)."
fi
if [ -n "$OVERLAY" ] && [ -f "$OVERLAY/wiring.sh" ]; then
  section "Overlay wiring"
  step "Configuring the overlay's services"
  # shellcheck disable=SC1090
  ( source "$OVERLAY/wiring.sh" ) && step_ok "Overlay wired" || step_warn "Overlay wiring had issues (see log)"
fi

# ---------------------------------------------------------------------------
# 7. AUTOMATION + THE PANEL'S CONFIG
# ---------------------------------------------------------------------------
section "Installing automation + the control panel's configuration"
step "Deploying cron jobs, notify hooks and controllarr.env"
MEDIA_STACK_OVERLAY="$OVERLAY" run "automation" bash "$HERE/lib/install-automation.sh" "$HERE" "$ENV_FILE" "$SECRETS_FILE" \
  && step_ok "Automation installed" || step_warn "Automation had issues (see log) — stack still works"
# the panel reads controllarr.env once at start — restart it now that automation has written the final copy
( cd "$HERE" && docker compose --env-file "$ENV_FILE" restart controllarr >/dev/null 2>&1 ) || true

# ---------------------------------------------------------------------------
# 8. SUMMARY
# ---------------------------------------------------------------------------
step "Writing INSTALL-SUMMARY.txt"
bash "$HERE/lib/summary.sh" "$ENV_FILE" "$SECRETS_FILE" > "$HERE/INSTALL-SUMMARY.txt"
step_ok "Summary written"

section "Done"
cat "$HERE/INSTALL-SUMMARY.txt"
echo
echo "Full log: $LOGFILE"
echo "Keep INSTALL-SUMMARY.txt — it has all your URLs and logins."
