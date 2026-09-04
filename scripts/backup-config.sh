#!/usr/bin/env bash
# Local encrypted nightly backup of the stack config. Reads $WARDEN_ENV. Cron/systemd-timer at ~03:30.
set -uo pipefail
if [ -n "${WARDEN_ENV:-}" ]; then
  # shellcheck source=/dev/null
  . "$WARDEN_ENV"
fi
CONFIG_DIR="${CONFIG_DIR:-/srv/media/config}"
DEST="${BACKUP_DIR:-$(dirname "$CONFIG_DIR")/backups}"   # same default as the installer: a backups/ directory beside CONFIG_DIR
# The passphrase lives OUTSIDE the backup directory, so syncing BACKUP_DIR off-site never ships the key.
# (An older install kept it inside BACKUP_DIR — migrate it once.)
PASS="${BACKUP_PASS_FILE:-$CONFIG_DIR/.backup-passphrase}"
KEEP="${BACKUP_KEEP:-7}"
STAMP=$(date +%Y%m%d-%H%M)
mkdir -p "$DEST" || { echo "backup: cannot create $DEST" >&2; exit 1; }
if [ ! -f "$PASS" ] && [ -f "$DEST/.passphrase" ]; then mv "$DEST/.passphrase" "$PASS"; fi
[ -f "$PASS" ] || { head -c 32 /dev/urandom | base64 > "$PASS"; chmod 600 "$PASS"; }

BASE="$(basename "$CONFIG_DIR")"
EXCL=(--exclude="$BASE/*/log" --exclude="$BASE/jellyfin/transcodes"
      --exclude="$BASE/jellyfin/metadata" --exclude="$BASE/jellyfin/cache" --exclude="$BASE/controllarr/cache")

# Some files under CONFIG_DIR are written by containers running as root (the panel's users.json,
# settings.local). A plain tar as the cron user then fails with "Permission denied" (exit 2) and no
# archive is produced. When anything is unreadable, read the tree through a throwaway root container
# instead (the same trick uninstall.sh uses); otherwise plain tar.
run_tar() {
  if [ -n "$(find "$CONFIG_DIR" ! -readable -print -quit 2>/dev/null)" ] && command -v docker >/dev/null 2>&1; then
    # any small image with busybox tar that is already on the box (the panel's own image is always there
    # when the dashboard profile is on); fall back to pulling alpine:3
    local img; for img in alpine:3 alpine:latest python:3.12-alpine; do docker image inspect "$img" >/dev/null 2>&1 && break; img=; done
    docker run --rm -v "$CONFIG_DIR:/src/$BASE:ro" -w /src "${img:-alpine:3}" tar -cz "${EXCL[@]}" "$BASE"
  else
    tar -C "$(dirname "$CONFIG_DIR")" -cz "${EXCL[@]}" "$BASE"
  fi
}

OUT="$DEST/config-$STAMP.tar.gz.gpg"
run_tar | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase-file "$PASS" -o "$OUT"
rc=("${PIPESTATUS[@]}")
# tar exit 1 = "file changed as we read it" (live databases) — the archive is still complete and usable
if [ "${rc[0]}" -gt 1 ] || [ "${rc[1]}" -ne 0 ]; then
  echo "backup FAILED (tar=${rc[0]} gpg=${rc[1]})" >&2; rm -f "$OUT"; exit 1
fi

ls -1t "$DEST"/config-*.tar.gz.gpg 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f
echo "backup: $OUT"
