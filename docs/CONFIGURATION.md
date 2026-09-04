# Configuration reference

Every file the stack writes, which one wins, and every variable.

Related: [INSTALL.md](INSTALL.md) (the prompts that set them) · [AUTOMATION.md](AUTOMATION.md) · [SERVICES.md](SERVICES.md)

## The file map

| File | Where | Written by | Contains | Mode |
|---|---|---|---|---|
| `.env` | install dir | `install.sh` | Non-secret answers: host, paths, profiles, ports, content knobs, the panel's pinned version, Tailscale flags. Read by compose and the wiring step. | 644 |
| `secrets.env` | install dir | `install.sh` | Service logins, media users, `CONTROLLARR_PASSWORD`, OpenSubtitles login. **The only copy of generated passwords.** | 600 |
| `tailscale.env` | install dir | `install.sh` (Tailscale on) | The auth key, node name and state path; loaded by the tailscale container. Deleted when it goes off. | 600 |
| `vpn.env` | install dir | **you** | Your VPN provider's own gluetun settings, passed to the container verbatim. The one file here the installer never writes — it only checks it exists and sets `VPN_SERVICE_PROVIDER`. Gitignored; nothing from it is copied into `.env`. | 600 |
| `docker-compose.override.yml` | install dir | `install.sh` (every run) | `/dev/dri` passthrough, the Tailscale and gluetun stanzas, and anything an overlay adds. Overwritten every run — never edit. | 644 |
| `controllarr/` | install dir | `install.sh` | A shallow clone of the control panel at `CONTROLLARR_REF`. Its `app/` is mounted read-only into the container; the installer also imports `settings_ops.py` from it. Safe to delete — the next run fetches it again. | — |
| `warden.env` | install dir | `install-automation.sh` | The resolved snapshot the cron jobs read: paths, ports, topics, quiet hours, `EXPECTED_CONTAINERS`, `MEDIAUSER_1`, `JELLYFIN_APIKEY`. | 600 |
| `controllarr.env` | `CONFIG_DIR/controllarr/` | `install-automation.sh` | What the panel reads, once, at start: `SERVICES`, each app's host and port, `CONFIG_DIR` (so it reads API keys live — none is copied here), `CONTROLLARR_PASSWORD`, the notification values. | 600 |
| `settings.local` | `CONFIG_DIR/controllarr/` | the panel | `KEY=value` overrides saved in Settings: quiet hours, topics, `NTFY_URL`, `MIN_SEEDERS`, `SUBTITLE_LANGS`, `HEARING_IMPAIRED`, and the profile each arr adds with. Radarr and Sonarr mount it read-only so the notify hooks see quiet hours without a restart. | 644 |
| `users.json`, `sessions.json`, `cache/` | `CONFIG_DIR/controllarr/` | the panel | Accounts (PBKDF2-SHA256, 200 000 iterations), logins for 30 days, proxied posters. | 600 / 600 / — |
| `active/` | install dir | `install-automation.sh` | The copies of `scripts/*` that cron runs, plus one `<name>.log` each. | — |
| `INSTALL-SUMMARY.txt` | install dir | `install.sh` | URLs and logins. | 644 |

**Precedence.** `.env` + `secrets.env` are the installer's truth → the wiring pushes their values **into the apps**, and `install-automation.sh` snapshots them into `warden.env` and `controllarr.env`. `settings.local` is merged on top of both, so a value saved in Settings beats the snapshot. The apps hold the live quality and size values; Settings reads them back from the apps, not from `.env` — and they are put there by TRaSH Guides, not by this installer ([SERVICES.md ▸ Selection rules](SERVICES.md#selection-rules)). `CONTROLLARR_PORT` moves the host port only — the container always listens on 3002.

## `.env`

Values are single-quoted; keep the quotes when editing.

| Variable | Meaning | Default |
|---|---|---|
| `STACK_NAME` | Compose project name | `mediastack` |
| `SERVER_HOST` · `TZ` · `PUID`/`PGID` | LAN address in every URL · timezone · file owner | detected |
| `CONFIG_DIR` · `DATA_DIR` | app data (backed up) · the media library | `/srv/media/config` · `/srv/media/data` |
| `COMPOSE_PROFILES` | `notify` (ntfy). The core has no profile. | `notify` |
| `JELLYFIN_PORT` `RADARR_PORT` `SONARR_PORT` `JELLYSEERR_PORT` `BAZARR_PORT` `NTFY_PORT` `CONTROLLARR_PORT` | published ports | `8096 7878 8989 5055 6767 8090 3002` |
| `CONTROLLARR_REPO` · `CONTROLLARR_REF` | where the control panel comes from · the tag, branch or commit to install | the public repo · `v0.1.0` |
| `CONTROLLARR_REFRESH` | seconds between library scans in the panel | `15` |
| `AUDIO_LANGUAGE` | `Original`/`English`/`Japanese`/`Any`, on Radarr's quality profiles (Sonarr v4 has no such field) | `Original` |
| `SUBTITLE_LANGS` · `MEDIAUSER_COUNT` | Bazarr codes · number of `MEDIAUSER_N` | `en` · `1` |
| `ENABLE_WARDENS` · `NOTIFY_QUIET_START`/`_END` · `NTFY_TOPIC_MEDIA`/`_ADMIN` · `NTFY_URL` | cron jobs · silent hours for the media topic · topic names · external ntfy (blank = the stack's own) | `true` · `0`/`9` · `media`/`admin` · blank |
| `ENABLE_BACKUPS` · `BACKUP_DIR` · `BACKUP_KEEP` | nightly encrypted tarball · destination (always written; the panel mounts it) · how many to keep | `true` · `/srv/media/backups` · `7` |
| `TAILSCALE_ENABLED` · `TAILSCALE_HOSTNAME` | the tailscale container runs · the node's name in the tailnet | `false` · `mediastack` |

## `secrets.env`

`JELLYFIN_USER/PASS`, `RADARR_*`, `SONARR_*`, `BAZARR_*` (service UI logins), `MEDIAUSER_N` = `username|password|autoapprove|isadmin` (`MEDIAUSER_1` is the admin the cron jobs and the panel use for Jellyseerr), `OPENSUBS_USER/PASS`, `CONTROLLARR_PASSWORD`. API keys are never stored here — they are read live from each app's config under `CONFIG_DIR`.

## Changing things later

- **Live values** (quality, size, language, subtitles, request defaults, notifications): **Settings** in the panel. Editing `.env` alone changes nothing running.
- **Anything the installer asked**: re-run `./install.sh`.
- **A port clash**: `*_PORT` in `.env`, then re-run (a bare `compose up` moves the port but not `warden.env` or the hooks).
- **The panel version**: `CONTROLLARR_REF` in `.env`, then re-run.
- **The panel password**: `CONTROLLARR_PASSWORD` only seeds the first `admin`; afterwards change it in **Settings ▸ Users & roles**.
- **The backup passphrase** lives at `CONFIG_DIR/.backup-passphrase` — [BACKUP-RESTORE.md](BACKUP-RESTORE.md#encryption-and-the-passphrase).

## `vpn.env`

Written by you, not the installer, and read only by the `gluetun` container. The variable names are
gluetun's own — this stack passes the file through untouched and never parses it beyond checking that
`VPN_SERVICE_PROVIDER` is set. Examples for WireGuard and OpenVPN, the provider list, and how routing works
are in [services/gluetun.md](services/gluetun.md).

`VPN_ENABLED` and `VPN_ROUTE` in `.env` record *whether* a tunnel exists and *which services* share its
network namespace. An empty `VPN_ROUTE` means no gluetun container is created at all.
