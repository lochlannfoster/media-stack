#!/usr/bin/env bash
# media-stack uninstaller — full teardown. Usage: ./uninstall.sh [--help]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$HERE/uninstall-$(date +%Y%m%d-%H%M%S).log"
ENV_FILE="$HERE/.env"
source "$HERE/lib/common.sh"

[ "${1:-}" = "--help" ] && { echo "Removes containers, cron, automation, and (optionally) config/media. Logs to uninstall-*.log."; exit 0; }

echo "media-stack uninstaller — full log: $LOGFILE"
[ -f "$ENV_FILE" ] || die "No .env found in $HERE — is this an installed media-stack directory?"
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

section "Confirm"
printf "${C_RED}This will STOP and REMOVE the media-stack containers and its automation.${C_RESET}\n"
printf "Type 'yes' to continue: "; read -r ans </dev/tty
[ "$ans" = "yes" ] || { echo "aborted."; exit 0; }

RM_IMAGES=n; yesno "Also remove the downloaded Docker images?" n && RM_IMAGES=y
RM_MEDIA=n;  yesno "Also PURGE the media library (${DATA_DIR})? This deletes everything you have collected." n && RM_MEDIA=y

section "Stopping containers"
step "docker compose down"
# --profile '*': a container whose service sits in a profile that is OFF (ntfy, say)
# is neither active nor an orphan to Compose, so a plain `down --remove-orphans` leaves it running.
# --volumes: there are no named volumes; this drops the anonymous ones some images declare
DOWN_ARGS=(--env-file "$ENV_FILE" --profile '*' down --remove-orphans --volumes)
[ "$RM_IMAGES" = y ] && DOWN_ARGS+=(--rmi all)
( cd "$HERE" && run "compose down" docker compose "${DOWN_ARGS[@]}" )
step_ok "Containers removed"

section "Removing automation"
step "Removing cron entries"
if command -v crontab >/dev/null 2>&1; then
  # no trailing slash: the weekly `find $HERE/active -name '*.log' …` truncate line must go too
  TMP=$(mktemp); crontab -l 2>/dev/null | grep -vF "$HERE/active" > "$TMP" || true
  crontab "$TMP"; rm -f "$TMP"
fi
step_ok "Cron cleaned"
# the cron lines ran under `flock -n /tmp/mediastack-<name>.lock`; the empty lock files outlive them
rm -f /tmp/mediastack-*.lock
rm -rf "$HERE/active"
info "Removed $HERE/active (deployed wardens)."

# generated runtime files: the Tailscale secret and the generated compose override.
# (compose down above already removed the tailscale container via the auto-merged override.)
if [ -f "$HERE/tailscale.env" ] || [ -f "$HERE/docker-compose.override.yml" ]; then
  rm -f "$HERE/tailscale.env" "$HERE/docker-compose.override.yml"
  info "Removed tailscale.env (auth key) and docker-compose.override.yml (generated)."
fi
rm -rf "$HERE/controllarr"   # the control panel's clone; install.sh fetches it again
info "Removed the Controllarr clone."
# warden.env and INSTALL-SUMMARY.txt both carry credentials — they go too
rm -f "$HERE/warden.env" "$HERE/INSTALL-SUMMARY.txt"
info "Removed warden.env and INSTALL-SUMMARY.txt (they contained credentials)."

# Some containers (Jellyseerr, …) write files as root, which a normal
# `rm -rf` can't delete. Fall back to a throwaway root container so teardown is complete.
purge_dir() {
  local d="$1"
  [ -e "$d" ] || return 0
  rm -rf "$d" 2>/dev/null
  if [ -e "$d" ]; then
    run "root-rm $d" docker run --rm -v "$(dirname "$d"):/target" alpine sh -c "rm -rf /target/$(basename "$d")"
  fi
  [ -e "$d" ] && return 1 || return 0
}

section "Removing config"
step "Removing app config ($CONFIG_DIR)"
purge_dir "$CONFIG_DIR" && step_ok "Config removed" || step_warn "Some config could not be removed (see log) — remove $CONFIG_DIR manually"

if [ "$RM_MEDIA" = y ]; then
  step "Purging media data ($DATA_DIR)"
  purge_dir "$DATA_DIR" && step_ok "Media data purged" || step_warn "Some data could not be removed — remove $DATA_DIR manually"
else
  info "Kept media data at $DATA_DIR."
fi

# firewall hook (v1 adds no rules; placeholder for future)
log INFO "no firewall rules were added by the installer; nothing to remove"

section "Done"
echo "media-stack removed. Remaining in $HERE: the repo files, .env, secrets.env (your passwords), and logs."
echo "Delete the whole directory to finish: rm -rf \"$HERE\""
echo "Full log: $LOGFILE"
