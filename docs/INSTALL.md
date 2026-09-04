# Installing

`./install.sh` asks a series of questions, writes `.env` + `secrets.env`, fetches the control panel, starts the containers, configures every app over its API, installs the host cron jobs and prints `INSTALL-SUMMARY.txt`. Re-running it is the normal way to change anything it asked; previous answers are the defaults and passwords are kept. The terminal shows one line per step; everything else goes to `install-<timestamp>.log`.

Related: [CONFIGURATION.md](CONFIGURATION.md) (every variable and file) · [SERVICES.md](SERVICES.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md) · [UNINSTALL.md](UNINSTALL.md)

## Requirements

- Linux with **Docker Engine** + the **`docker compose` plugin** (2.20+ for the override's tags); `docker info` must work without `sudo`.
- `python3`, `curl` and `git` (the control panel is cloned from its own repository). Optional, warned about if missing: `crontab`, `gpg` (encrypted backups).
- Disk: the preflight warns under 10 GB free; plan for hundreds.
- Optional: a GPU at `/dev/dri` (wired into Jellyfin automatically); a Tailscale auth key ([services/tailscale.md](services/tailscale.md)).
- **Windows:** WSL2 + Docker Desktop (WSL integration on). Keep config and data on the Linux filesystem, never `/mnt/c` (slow, no hardlinks); enable cron with `[boot] systemd=true` in `/etc/wsl.conf`; there is no `/dev/dri`, so keep *Prefer h264* on.

Ports are checked right after `.env` is written; a clash is a warning — set the service's `*_PORT` in `.env` and re-run.

## The prompts

`[value]` is the default (Enter accepts). Password prompts hide input; *blank = auto-generate* makes a random 16-character password that lives only in `secrets.env`. On a re-run every default is the previous answer.

| Section | Prompt | Sets | Default |
|---|---|---|---|
| Basic | Host IP/name for URLs | `SERVER_HOST` — the address baked into every URL and notification link | auto-detected |
| | Timezone · File owner UID / GID | `TZ`, `PUID`/`PGID` (who owns the files) | detected / your id |
| | Config directory · Data directory | `CONFIG_DIR` (backed up), `DATA_DIR` (the library). Both insist on an absolute path. | `/srv/media/config`, `/srv/media/data` |
| Core | *(no choice — Jellyfin, Jellyseerr, Radarr, Sonarr, Bazarr, autoheal and Controllarr always install)* Control-panel admin password (hidden; blank = no login) | `CONTROLLARR_PASSWORD` — asked once, then kept. Blank = every visitor is an admin. | blank |
| Optional | Install phone notifications (ntfy)? | the `notify` profile in `COMPOSE_PROFILES` | yes |
| Remote access | Add Tailscale? · node name · auth key | `TAILSCALE_ENABLED`, `TAILSCALE_HOSTNAME`, `tailscale.env`. A blank key with no earlier login = *NOT enabled*. | no · `mediastack` · — |
| Credentials | Keep the existing service logins? (re-runs) · Use ONE shared admin login? · username / password | the four service UI logins in `secrets.env` | yes · yes · `admin` / generated |
| Media users | How many media user accounts? · username / password · Can 'name' auto-approve their own requests? | `MEDIAUSER_N` — Jellyfin + Jellyseerr accounts; **#1 is the admin** | 1 · `userN` / generated · no |
| Content | Audio language · Subtitle languages · OpenSubtitles account? | `AUDIO_LANGUAGE`, `SUBTITLE_LANGS`, `OPENSUBS_*` — [SERVICES.md ▸ Selection rules](SERVICES.md#selection-rules). Sizes and codec preferences are not asked: they are TRaSH Guides', applied from the panel. | Original · en · no |
| Notifications *(with ntfy)* | Quiet-hours START / END hour | `NOTIFY_QUIET_START` / `_END` (media topic silent) | 0 / 9 |
| Automation | Enable self-healing automation? · nightly encrypted config backups? · Backup directory | `ENABLE_WARDENS`, `ENABLE_BACKUPS`, `BACKUP_DIR` (always written) | yes · yes · `/srv/media/backups` |

An overlay may add prompts of its own between *Optional* and *Remote access* ([DEVELOPMENT.md ▸ Overlays](DEVELOPMENT.md#5-overlays)). Never prompted, carried forward from `.env`: `*_PORT`, `CONTROLLARR_REFRESH`, `CONTROLLARR_REF`, `STACK_NAME`, `NTFY_URL`.

## What it does, in order

1. **Writes `.env` and `secrets.env`** (single-quoted values; `secrets.env` mode 600), then warns about taken ports.
2. **Fetches Controllarr** into `./controllarr` at `CONTROLLARR_REF` (a shallow clone, or a fetch when it is already there) and reports the commit.
3. **Creates directories** — `CONFIG_DIR/<app>`, `DATA_DIR/media/{movies,tv}`, and `touch`es `CONFIG_DIR/controllarr/settings.local` (Radarr and Sonarr bind-mount it; Docker would otherwise create a directory).
4. **Writes the override** — `/dev/dri` when the host has a GPU, the Tailscale stanza when enabled, plus anything an overlay adds. Overwritten on every run.
5. **Retires containers whose profile went off, then `docker compose up -d --remove-orphans`** (first run pulls 1–2 GB).
6. **Wires the services** (`lib/wiring.py`, 2–10 min): Radarr and Sonarr root folders and quality/size/language rules through the panel's `settings_ops.py` (the same code its Settings page uses); Bazarr connections, providers and languages; Jellyfin wizard (fresh installs), libraries, VAAPI, users, Intro Skipper, and the arr connections that scan on import and on delete; Jellyseerr sign-in, servers, users and permissions. **Nothing touches an indexer or a download client.** Idempotent: existing objects are never duplicated.
7. **Installs the automation**: `active/` copies of `scripts/`, `warden.env` for the cron jobs, `controllarr.env` for the panel, the notify hooks inside Radarr and Sonarr, the Jellyfin API key, the crontab ([AUTOMATION.md](AUTOMATION.md)).
8. **Restarts the panel** (it reads its config once at start) and prints the summary.

## Re-running

- Previous answers are the defaults; secrets are never rotated behind your back; a blank Tailscale key keeps the old login.
- `CONTROLLARR_REF` in `.env` pins the panel's version — change it and re-run to move up or roll back. It
  defaults to a **tag**, so the panel you get is the one this release was tested against; setting it to
  `main` tracks the tip instead, and two installs a week apart will differ. A ref that does not exist
  fails the install rather than quietly falling back to the default branch.
- Turning a profile off retires its container but keeps `CONFIG_DIR/<app>`.
- The `.env` content knobs are pushed into Radarr/Sonarr again, **overwriting** a size cap changed in Settings — set the value in `.env` first, or re-save in Settings afterwards.
- `warden.env`, `controllarr.env`, the notify hooks and the crontab are regenerated; `settings.local`, `users.json` and `sessions.json` are never touched.

## After it finishes

Open Controllarr at `http://<server-ip>:3002` (log in as `admin`): the Line should be green. Give Radarr and Sonarr an indexer and a download client in their own settings — that part is yours. Then request something in Jellyseerr and watch it move to Available.

## When it fails

The log has every command and API response: `tail -n 50 "$(ls -t install-*.log | head -1)"`. Preflight failures are environment problems. *Could not fetch Controllarr* → check the network, or point `CONTROLLARR_REPO` at a local clone. *docker compose failed* → `docker compose --env-file .env ps -a` (usually a port). *Wiring failed* → an app was still starting; re-run. Everything else: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
