#!/usr/bin/env bash
# Deploy the cron jobs, the notify hooks and the control panel's configuration.
# Called by install.sh: install-automation.sh HERE ENV SECRETS
set -uo pipefail
HERE="$1"; ENV_FILE="$2"; SECRETS_FILE="$3"
ACTIVE="$HERE/active"
OVERLAY="${MEDIA_STACK_OVERLAY:-}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"   # for sq()
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; . "$SECRETS_FILE"; set +a

akey() { grep -oP '(?<=<ApiKey>)[^<]+' "$CONFIG_DIR/$1/config.xml" 2>/dev/null | head -1; }
RADARR_APIKEY="$(akey radarr)"; SONARR_APIKEY="$(akey sonarr)"

mkdir -p "$ACTIVE"
cp "$HERE"/scripts/*.py "$ACTIVE"/ 2>/dev/null || true
cp "$HERE"/scripts/backup-config.sh "$ACTIVE"/ 2>/dev/null || true
chmod +x "$ACTIVE"/*.sh "$ACTIVE"/*.py 2>/dev/null || true
[ -n "$OVERLAY" ] && [ -d "$OVERLAY/scripts" ] && { cp "$OVERLAY"/scripts/* "$ACTIVE"/ 2>/dev/null || true; chmod +x "$ACTIVE"/* 2>/dev/null || true; }

# ---- what this install runs: the core, plus whatever the profiles and the overlay add ----
SERVICES="radarr,sonarr,bazarr,jellyfin,jellyseerr"
EXPECTED="jellyfin,radarr,sonarr,bazarr,jellyseerr,controllarr,autoheal"
case ",$COMPOSE_PROFILES," in *,notify,*) SERVICES="$SERVICES,ntfy"; EXPECTED="$EXPECTED,ntfy";; esac
[ "${TAILSCALE_ENABLED:-false}" = true ] && EXPECTED="$EXPECTED,tailscale"
# gluetun matters more than most: the services routed through it share its network namespace, so a
# dead tunnel is a dead Radarr/Sonarr/Bazarr and the wardens should say gluetun, not all three.
[ "${VPN_ENABLED:-false}" = true ] && EXPECTED="$EXPECTED,gluetun"
# an overlay contributes its own service and container names
[ -n "$OVERLAY" ] && [ -f "$OVERLAY/services.sh" ] && { # shellcheck disable=SC1090
  source "$OVERLAY/services.sh"; }

# Jellyfin API key: the persistent 'arr-stack' key the wiring step creates, looked up with MEDIAUSER_1.
jellyfin_key() {
  python3 - "${MEDIAUSER_1:-}" "${JELLYFIN_PORT:-8096}" <<'PY' 2>/dev/null
import sys,json,urllib.request,http.cookiejar
mu=(sys.argv[1] or '').split('|'); base='http://localhost:'+sys.argv[2]
if len(mu)<2: print(''); sys.exit()
try:
    op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    hdr={'Content-Type':'application/json','X-Emby-Authorization':'MediaBrowser Client=cli, Device=cli, DeviceId=cli, Version=1'}
    d=json.load(op.open(urllib.request.Request(base+'/Users/AuthenticateByName',data=json.dumps({'Username':mu[0],'Pw':mu[1]}).encode(),headers=hdr)))
    keys=json.load(op.open(urllib.request.Request(base+'/Auth/Keys',headers={'X-Emby-Token':d['AccessToken']})))
    print(next((x['AccessToken'] for x in keys.get('Items',[]) if x.get('AppName')=='arr-stack'),''))
except Exception: print('')
PY
}
JELLYFIN_APIKEY="$(jellyfin_key)"
[ -n "$JELLYFIN_APIKEY" ] || echo "WARNING: could not look up Jellyfin's arr-stack API key — the panel's now-playing view will report the key as missing (re-run ./install.sh once Jellyfin is up)"

# ---- warden.env: everything the cron jobs read (chmod 600) ----
WARDEN_ENV="$HERE/warden.env"
ENABLE_NOTIFY=false; case ",$COMPOSE_PROFILES," in *,notify,*) ENABLE_NOTIFY=true;; esac
cat > "$WARDEN_ENV" <<EOF
SERVER_HOST=$SERVER_HOST
CONFIG_DIR=$CONFIG_DIR
DATA_DIR=$DATA_DIR
RADARR_PORT=${RADARR_PORT:-7878}
SONARR_PORT=${SONARR_PORT:-8989}
BAZARR_PORT=${BAZARR_PORT:-6767}
JELLYFIN_PORT=${JELLYFIN_PORT:-8096}
JELLYSEERR_PORT=${JELLYSEERR_PORT:-5055}
CONTROLLARR_PORT=${CONTROLLARR_PORT:-3002}
STACK_DIR=$HERE
NTFY_PORT=${NTFY_PORT:-8090}
ENABLE_NOTIFY=$ENABLE_NOTIFY
NTFY_TOPIC_MEDIA=${NTFY_TOPIC_MEDIA:-media}
NTFY_TOPIC_ADMIN=${NTFY_TOPIC_ADMIN:-admin}
NOTIFY_QUIET_START=${NOTIFY_QUIET_START:-0}
NOTIFY_QUIET_END=${NOTIFY_QUIET_END:-9}
EXPECTED_CONTAINERS=$EXPECTED
BACKUP_DIR=${BACKUP_DIR:-$(dirname "$CONFIG_DIR")/backups}
BACKUP_KEEP=${BACKUP_KEEP:-7}
ENABLE_BACKUPS=${ENABLE_BACKUPS:-false}
EOF
{ echo "MEDIAUSER_1=$(sq "${MEDIAUSER_1:-}")"
  echo "JELLYFIN_APIKEY=$(sq "${JELLYFIN_APIKEY:-}")"
  echo "SUBTITLE_LANGS=$(sq "${SUBTITLE_LANGS:-en}")"; } >> "$WARDEN_ENV"
[ -n "$OVERLAY" ] && [ -f "$OVERLAY/warden-env.sh" ] && { # shellcheck disable=SC1090
  source "$OVERLAY/warden-env.sh"; }   # appends the overlay's own values
chmod 600 "$WARDEN_ENV"

# ---- controllarr.env: what the control panel reads, once, at start (chmod 600) ----
# CONFIG_DIR is mounted read-only into the panel, so it reads every app's API key live and none is copied here.
CTRL_ENV="$CONFIG_DIR/controllarr/controllarr.env"
mkdir -p "$CONFIG_DIR/controllarr"
cat > "$CTRL_ENV" <<EOF
SERVER_HOST=$SERVER_HOST
CONFIG_DIR=$CONFIG_DIR
MEDIA_DIR=$DATA_DIR
BACKUP_DIR=${BACKUP_DIR:-$(dirname "$CONFIG_DIR")/backups}
ENABLE_BACKUPS=${ENABLE_BACKUPS:-false}
DOCKER_SOCK=/var/run/docker.sock
SERVICES=$SERVICES
EXPECTED_CONTAINERS=$EXPECTED
RADARR_HOST=radarr
RADARR_PORT=${RADARR_PORT:-7878}
RADARR_PORT_INTERNAL=7878
SONARR_HOST=sonarr
SONARR_PORT=${SONARR_PORT:-8989}
SONARR_PORT_INTERNAL=8989
BAZARR_HOST=bazarr
BAZARR_PORT=${BAZARR_PORT:-6767}
BAZARR_PORT_INTERNAL=6767
JELLYFIN_HOST=jellyfin
JELLYFIN_PORT=${JELLYFIN_PORT:-8096}
JELLYFIN_PORT_INTERNAL=8096
JELLYSEERR_HOST=jellyseerr
JELLYSEERR_PORT=${JELLYSEERR_PORT:-5055}
JELLYSEERR_PORT_INTERNAL=5055
NTFY_PORT=${NTFY_PORT:-8090}
NTFY_TOPIC_MEDIA=${NTFY_TOPIC_MEDIA:-media}
NTFY_TOPIC_ADMIN=${NTFY_TOPIC_ADMIN:-admin}
NOTIFY_QUIET_START=${NOTIFY_QUIET_START:-0}
NOTIFY_QUIET_END=${NOTIFY_QUIET_END:-9}
SUBTITLE_LANGS=${SUBTITLE_LANGS:-en}
EOF
[ "$ENABLE_NOTIFY" = true ] && echo "NTFY_HOST=ntfy" >> "$CTRL_ENV"
{ echo "CONTROLLARR_PASSWORD=$(sq "${CONTROLLARR_PASSWORD:-}")"
  echo "JELLYFIN_APIKEY=$(sq "${JELLYFIN_APIKEY:-}")"; } >> "$CTRL_ENV"
[ -n "$OVERLAY" ] && [ -f "$OVERLAY/controllarr-env.sh" ] && { # shellcheck disable=SC1090
  source "$OVERLAY/controllarr-env.sh"; }   # the overlay's own services for the panel
chmod 600 "$CTRL_ENV"
touch "$CONFIG_DIR/controllarr/settings.local"

# ---- render + install the in-container notify hooks + register connections ----
render_notify() {
  local tmpl="$1" out="$2"
  sed -e "s|__RADARR_KEY__|$RADARR_APIKEY|g" -e "s|__SONARR_KEY__|$SONARR_APIKEY|g" \
      -e "s|__SERVER_HOST__|$SERVER_HOST|g" -e "s|__JELLYFIN_PORT__|${JELLYFIN_PORT:-8096}|g" \
      -e "s|__TOPIC_MEDIA__|${NTFY_TOPIC_MEDIA:-media}|g" \
      -e "s|__QUIET_START__|${NOTIFY_QUIET_START:-0}|g" -e "s|__QUIET_END__|${NOTIFY_QUIET_END:-9}|g" \
      "$tmpl" > "$out"
}
if [ "$ENABLE_NOTIFY" = true ]; then
  mkdir -p "$CONFIG_DIR/radarr/scripts" "$CONFIG_DIR/sonarr/scripts"
  render_notify "$HERE/scripts/movie-ready.sh.tmpl" "$CONFIG_DIR/radarr/scripts/movie-ready.sh"
  render_notify "$HERE/scripts/notify-series-complete.sh.tmpl" "$CONFIG_DIR/sonarr/scripts/notify-series-complete.sh"
  chmod +x "$CONFIG_DIR"/radarr/scripts/movie-ready.sh "$CONFIG_DIR"/sonarr/scripts/notify-series-complete.sh
  reg() { # app port key name path onDownload onImportComplete
    curl -s -H "X-Api-Key: $3" "http://localhost:$2/api/v3/notification" | grep -q "$4" && return 0
    schema=$(curl -s -H "X-Api-Key: $3" "http://localhost:$2/api/v3/notification/schema")
    SCHEMA="$schema" python3 - "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json,os,sys,urllib.request
port,key,name,path,onDl,onImp=sys.argv[1:7]
sch=json.loads(os.environ["SCHEMA"]); cs=[s for s in sch if s["implementation"]=="CustomScript"][0]
cs=json.loads(json.dumps(cs)); cs["name"]=name; cs["onDownload"]=onDl=="1"; cs["onUpgrade"]=onDl=="1"
cs["onImportComplete"]=onImp=="1"; cs["onGrab"]=False; cs["onHealthIssue"]=False
for f in cs.get("fields",[]):
    if f["name"]=="path": f["value"]=path
r=urllib.request.Request(f"http://localhost:{port}/api/v3/notification",data=json.dumps(cs).encode(),
    headers={"X-Api-Key":key,"Content-Type":"application/json"},method="POST")
try: urllib.request.urlopen(r); print("registered",name)
except Exception as e: print("reg-fail",e)
PY
  }
  reg radarr "${RADARR_PORT:-7878}" "$RADARR_APIKEY" "Ready (ntfy)" "/config/scripts/movie-ready.sh" 1 0
  reg sonarr "${SONARR_PORT:-8989}" "$SONARR_APIKEY" "Series Complete (ntfy)" "/config/scripts/notify-series-complete.sh" 1 1
fi

# ---- cron ----
# Every job runs under flock (no overlapping runs) and a hard timeout (a hung API call can't pile up slots).
if command -v crontab >/dev/null 2>&1; then
  TMP=$(mktemp); crontab -l 2>/dev/null | grep -vF "$ACTIVE" > "$TMP" || true
  W="WARDEN_ENV=$WARDEN_ENV"
  job() { # job "<schedule>" <script> [timeout-seconds]
    local sched="$1" s="$2" to="${3:-300}" cmd
    case "$s" in *.py) cmd="/usr/bin/python3 $ACTIVE/$s";; *) cmd="$ACTIVE/$s";; esac
    echo "$sched $W flock -n /tmp/mediastack-${s%.*}.lock timeout $to $cmd >>$ACTIVE/${s%.*}.log 2>&1"
  }
  if [ "${ENABLE_WARDENS:-true}" = true ]; then
    {
      job "*/5 * * * *"  availability-warden.py 120
      job "*/5 * * * *"  resource-warden.py 120
      job "0 * * * *"    sub-warden.py 600
      job "*/15 * * * *" disk-check.py 120
      job "0 9 * * *"    daily-digest.py 300
      [ -n "$OVERLAY" ] && [ -f "$OVERLAY/cron.sh" ] && { # shellcheck disable=SC1090
        source "$OVERLAY/cron.sh"; }
    } >> "$TMP"
  fi
  if [ "${ENABLE_BACKUPS:-false}" = true ]; then
    job "30 3 * * *" backup-config.sh 1800 >> "$TMP"
  fi
  echo "0 0 * * 0 find $ACTIVE -name '*.log' -size +5M -exec truncate -s 0 {} \; >/dev/null 2>&1" >> "$TMP"
  crontab "$TMP"; rm -f "$TMP"
  echo "cron installed"
else
  echo "WARNING: crontab not found — cron jobs not scheduled. Install cron or add systemd timers manually."
fi
exit "${RC:-0}"
