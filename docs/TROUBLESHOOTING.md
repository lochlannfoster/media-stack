# Troubleshooting

Symptom → one check → one fix. The mechanism behind each fix lives in the linked doc; each service's own page under [`services/`](services/) lists its usual failures.

Related: [INSTALL.md](INSTALL.md) · [SERVICES.md](SERVICES.md) · [AUTOMATION.md](AUTOMATION.md) · [BACKUP-RESTORE.md](BACKUP-RESTORE.md)

## Read the logs first

1. **Installer:** `tail -n 50 "$(ls -t install-*.log | head -1)"`; `grep -nE '\[(ERROR|WARN)\]|RUN-FAIL' install-*.log`. Every command and API response is there; the terminal shows almost nothing.
2. **Cron jobs:** `active/<name>.log` (empty is normal — a clean run writes nothing); `grep -l Traceback active/*.log`. Deleting `CONFIG_DIR/.<name>-state.json` resets that job safely.
3. **Containers:** the panel's **System** strip shows every container's state, what it is doing and its last log line without SSH; for the rest, `docker ps -a` (look for `(unhealthy)`) and `docker logs --tail 50 <container>`.

## The control panel

| Symptom | Check | Fix |
|---|---|---|
| **Locked out** — the install password is rejected | `users.json` exists: the env password only seeded it | `sudo rm CONFIG_DIR/controllarr/users.json && docker restart controllarr` (reseeds `admin` from the current `CONTROLLARR_PASSWORD`; other accounts are lost). A new password first needs a `./install.sh` re-run so `controllarr.env` carries it. |
| **No login, everyone is admin** | `CONTROLLARR_PASSWORD` is empty | re-run `./install.sh` and set one |
| **Sign everyone out** | sessions live 30 days on disk | `sudo rm CONFIG_DIR/controllarr/sessions.json && docker restart controllarr` |
| **Container restarting, `/app` empty** | the clone is missing or half-fetched | `rm -rf controllarr && ./install.sh` |
| **A Settings group is empty or errors** | that app is down or starting (Needs attention shows it) | wait for healthy, reopen; a rejected Apply shows the app's message |
| **Changed `.env` but the panel ignores it** | `controllarr.env` is read once at start | re-run `./install.sh` (regenerates it and restarts the panel) |
| **Wrong panel version** | `CONTROLLARR_REF` in `.env` | set the tag or commit you want and re-run |
| **Who did what?** | — | `docker logs controllarr --since 1h \| grep action=` |

## Tailscale

| Symptom | Cause | Fix |
|---|---|---|
| the tailscale container is *unhealthy* | not logged in: the auth key was rejected or expired (`docker logs tailscale`) | new key in the admin console, re-run `./install.sh` ([services/tailscale.md](services/tailscale.md)) |
| reachable by tailnet IP, not by name | MagicDNS off | enable it in the admin console |
| the node keeps asking to re-authenticate | node key expiry | *Disable key expiry* for the machine in the admin console |

## The VPN

Everything routed through gluetun shares its network namespace, so a symptom that looks like three broken services is one broken tunnel. Check `docker logs gluetun` before anything else.

| Symptom | Cause | Fix |
|---|---|---|
| Radarr, Sonarr or Bazarr unreachable right after enabling the VPN | the tunnel never came up, so they have no network | `docker logs gluetun` — usually a wrong key, a lapsed subscription or a country with no server ([services/gluetun.md](services/gluetun.md)) |
| the gluetun container is *unhealthy* | bad credentials, or `VPN_SERVICE_PROVIDER` misspelled in `vpn.env` | gluetun's log names the provider it expected; fix `vpn.env` and `docker compose up -d gluetun` |
| the installer says the VPN is **not** enabled | `vpn.env` is missing, or sets no `VPN_SERVICE_PROVIDER` | write it ([services/gluetun.md](services/gluetun.md)) and re-run `./install.sh` — it will not start a tunnel it cannot verify |
| *Nothing would go through the VPN* | every routable service was declined | answer yes to at least one, or leave the VPN off: an empty tunnel protects nothing |
| a routed service should be back on the LAN directly | — | re-run `./install.sh` and answer no; the override is regenerated and the ports return to the services |
| metadata and subtitles got slow | the exit server is far away | a nearer `SERVER_COUNTRIES` in `vpn.env` |

## The library

| Symptom | Why | Fix |
|---|---|---|
| **Nothing is ever found or fetched** | Radarr and Sonarr have no indexer, or nothing to hand a release to — this stack configures neither | add an indexer and a download client in Radarr's and Sonarr's own settings ([SERVICES.md](SERVICES.md#what-this-stack-does-not-include)) |
| **Unavailable — too big / quality not allowed** | your own size max or profile | raise **Maximum size** in Settings ▸ Quality & size, or change the profile |
| **A dub was grabbed** | a release without a dub marker slipped past the penalty | Settings ▸ Quality & size ▸ Audio language *Original* + Apply, then grab a clean one by hand |
| **Request stays "processing"** | nothing was grabbed — the title's stage reason says why | see the two rows above |
| **A show is Partial with files** | intended: any missing episode in a tracked season | expand the show, tick the episodes, **Search** or **Untrack** |
| **Imports copy instead of hardlinking** | your download client writes to a different filesystem from `DATA_DIR/media` | put both on one filesystem ([SERVICES.md](SERVICES.md#what-this-stack-does-not-include)) |
| **A purged title is still in Jellyfin or Bazarr** | both are asked to rescan on a purge; a scan takes a moment | wait a minute; Settings ▸ Media server ▸ **Scan library now** |
| **Subtitles missing** | Bazarr has not found one | **Fetch subs** per title or episode; the sub job searches hourly on purpose (providers lock hammered accounts); check providers and *Minimum score* in Settings ▸ Subtitles |

## Host, disk, cron, notifications

- **Disk full** — the disk-check job and Needs attention warn at 80 / 90 / 95 % of `DATA_DIR`; the System strip's *disk filling up* starts at 80 % and says how many GB are left. Purge titles you no longer want, or lower the size cap.
- **No cron lines** (`crontab -l`) — no `crontab` binary (install `cron`/`cronie`, enable it, re-run), `ENABLE_WARDENS=false`, or the wrong user (the one who ran the installer must be in `docker`). Run one by hand: `WARDEN_ENV=$PWD/warden.env python3 active/<name>.py`.
- **No notifications** — the `notify` profile must be on; **Settings ▸ Notifications ▸ Send a test notification** uses the same path as the cron jobs; media-topic pushes are silent (not absent) in quiet hours. If Docker turned `CONFIG_DIR/controllarr/settings.local` into a directory: stop, `rm -r` it, `touch` the file, start.
- **Backups failing** — `active/backup-config.log`; usually `gpg` missing. *file changed as we read it* is tolerated ([BACKUP-RESTORE.md](BACKUP-RESTORE.md)).

## Installer

- *Docker is not installed / not running* → install Docker + the compose plugin, start the daemon, `usermod -aG docker $USER`, log in again.
- *Could not fetch Controllarr* → no network, or a bad `CONTROLLARR_REF`; point `CONTROLLARR_REPO` at a local clone to install offline.
- *Port already in use* → `*_PORT` in `.env`, re-run (a bare `compose up` does not update `warden.env` or the hooks).
- *invalid volume specification* → a directory in `.env` is not an absolute path; re-run, the prompts insist on `/…`.
- *Wiring failed* → an app was still starting; re-run, it is idempotent.
- *Port already in use* on a routed service → gluetun publishes it now, so the clash is with gluetun; the `*_PORT` variable is still the one to change.
- No `/dev/dri` → CPU transcoding; keep *Prefer h264*.

## Still stuck

```bash
tail -n 100 "$(ls -t install-*.log | head -1)"; docker ps -a --format '{{.Names}}\t{{.Status}}'
grep -l . active/*.log | xargs -I{} sh -c 'echo "== {}"; tail -n 20 {}'
```
