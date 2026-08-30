#!/usr/bin/env bash
# Print INSTALL-SUMMARY.txt: all URLs + credentials + next steps.  summary.sh ENV SECRETS
set -uo pipefail
# shellcheck disable=SC1090
set -a; . "$1"; . "$2"; set +a
H="$SERVER_HOST"
HERE="$(cd "$(dirname "$1")" && pwd)"
has() { case ",$COMPOSE_PROFILES," in *,$1,*) return 0;; *) return 1;; esac }

cat <<EOT
========================================================================
  media-stack — install summary   ($(date))
========================================================================

  Controllarr (control panel)  http://$H:${CONTROLLARR_PORT:-3002}   <- run everything from here
  Jellyfin (watch)             http://$H:${JELLYFIN_PORT:-8096}
  Jellyseerr (request)         http://$H:${JELLYSEERR_PORT:-5055}
  Radarr                       http://$H:${RADARR_PORT:-7878}
  Sonarr                       http://$H:${SONARR_PORT:-8989}
  Bazarr                       http://$H:${BAZARR_PORT:-6767}
EOT
has notify && echo "  ntfy                         http://$H:${NTFY_PORT:-8090}  (topics: ${NTFY_TOPIC_MEDIA:-media} = content, ${NTFY_TOPIC_ADMIN:-admin} = ops)"
[ "${TAILSCALE_ENABLED:-false}" = true ] && echo "  Tailscale: ON — from another device on your tailnet, open http://${TAILSCALE_HOSTNAME:-mediastack}:${JELLYFIN_PORT:-8096}"
[ -f "$HERE/overlay-summary.txt" ] && { echo; cat "$HERE/overlay-summary.txt"; }

echo
echo "LOGINS"
echo "  Service admin: ${RADARR_USER:-see secrets.env} / (see secrets.env)"
for i in $(seq 1 "${MEDIAUSER_COUNT:-1}"); do
  v="MEDIAUSER_$i"; IFS='|' read -r u _p aa first <<< "${!v:-}"
  adm=""; [ "${first:-false}" = true ] && adm=", admin"
  [ -n "$u" ] && echo "  User account: $u  (auto-approve: ${aa:-false}${adm})"
done
echo "  (Full credentials are in secrets.env — chmod 600, not committed.)"

if has notify; then
cat <<EOT

PHONE NOTIFICATIONS
  Install the "ntfy" app -> Add subscription -> Use another server
    Server: http://$H:${NTFY_PORT:-8090}
    Everyone subscribes to: ${NTFY_TOPIC_MEDIA:-media}   (content)
    Admin only subscribes to: ${NTFY_TOPIC_ADMIN:-admin} (ops)
  Media notifications are silent between ${NOTIFY_QUIET_START:-0}:00 and ${NOTIFY_QUIET_END:-9}:00.
EOT
fi

cat <<EOT

WHAT NEXT
  1. Open Controllarr and sign in as 'admin'. The Line should be green.
  2. Give Radarr and Sonarr somewhere to fetch from — an indexer and a download client of your choosing.
     Until then they will track titles but never grab one.
  3. Request something in Jellyseerr and watch it move across the Line to Available.
  - Re-run ./install.sh anytime; it's idempotent (previous answers are the defaults, passwords are kept).
  - Uninstall with ./uninstall.sh.
========================================================================
EOT
