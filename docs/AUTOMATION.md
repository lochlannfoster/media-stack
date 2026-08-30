# Automation

Host-side cron jobs that keep the stack healthy: chase subtitles, watch disk, CPU and containers, and push a notification when a human is needed. Installed by `lib/install-automation.sh` when `ENABLE_WARDENS=true`; backups have their own switch. An overlay can add jobs of its own ([DEVELOPMENT.md ▸ Overlays](DEVELOPMENT.md#5-overlays)).

| Path | What |
|---|---|
| `<stack>/active/` | the copies of `scripts/*` that cron runs, refreshed by every installer run; one `<name>.log` each |
| `<stack>/warden.env` | everything a job needs, passed as `WARDEN_ENV=…` ([CONFIGURATION.md](CONFIGURATION.md#the-file-map)) |
| `CONFIG_DIR/controllarr/settings.local` | live overrides from Settings, merged on top every run |
| `CONFIG_DIR/.<name>-state.json` | each warden's memory between runs; safe to delete |

Scripts are secret-free (API keys are read live from each app's config) and talk to `localhost:<published port>`.

Related: [SERVICES.md](SERVICES.md) · [BACKUP-RESTORE.md](BACKUP-RESTORE.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Notifications

Two ntfy topics (`NTFY_TOPIC_MEDIA` / `_ADMIN`, live from **Settings ▸ Notifications**): **media** for the house — *Ready to watch*, *No subtitles*; **admin** for the operator — service down and recovered, resources, disk, the daily digest. **Quiet hours** (`NOTIFY_QUIET_START/END`, default 0–9, wrap-around allowed) send the media topic at priority `min`; admin alerts never mute. Without the `notify` profile pushes are skipped and the wardens still run. Two hooks inside the arrs (rendered from `scripts/*.tmpl`) push *Ready to watch: title* with the poster (Radarr) and one *series complete* when every episode is on disk (Sonarr); they read `settings.local` for the panel's quiet hours.

## The schedule

Each line runs under `flock -n` (no overlap) and `timeout`, appending to `active/<name>.log`; `warden_lib` adds a 30 s socket timeout so a hung API call cannot hold a slot. Sunday 00:00 truncates any log over 5 MB.

| Job | Cron | Timeout | Topic | Does |
|---|---|---|---|---|
| `availability-warden.py` | `*/5` | 120 s | admin | an `EXPECTED_CONTAINERS` entry not `running` or `(unhealthy)` → *Service DOWN*; back → *recovered*; `docker ps` failing → *Docker unreachable* |
| `resource-warden.py` | `*/5` | 120 s | admin | load > 1.5 × cores, swap > 50 %, MemAvailable < 8 % or iowait > 60 % → *High resource usage*, re-warned every 30 min; *Resources normal* once |
| `disk-check.py` | `*/15` | 120 s | admin | `DATA_DIR` at 80 / 90 / 95 %, once per level (default / high / urgent); *Disk OK* under 80 % |
| `sub-warden.py` | hourly | 600 s | media | a film with a file but no subtitle 20 min after import → *No subtitles* once; sync Bazarr; search providers **only** when something is missing (hourly on purpose — providers lock hammered accounts) |
| `daily-digest.py` | daily 09:00 | 300 s | admin | imported in 24 h, disk, and what is still in the arrs' queues |
| `backup-config.sh` | daily 03:30 | 1800 s | — | `ENABLE_BACKUPS` only: encrypted tarball of `CONFIG_DIR` ([BACKUP-RESTORE.md](BACKUP-RESTORE.md)) |

**State files** (`CONFIG_DIR`): `.avail-state.json`, `.resource-state.json`, `.disk-alert-state.json`, `.subwarn-state.json` — each job's memory between runs, safe to delete.

**Container-side:** `autoheal` restarts labelled containers after three failed healthchecks ([SERVICES.md](SERVICES.md#healthchecks-and-autoheal)).

## Supporting script (not scheduled)

`warden_lib.py` — the shared helpers: the config file plus the panel's `settings.local` overlaid on top, API keys read live, `arr()` and `push()`.

## Turning off, tuning, running by hand

- All of them: `ENABLE_WARDENS=false` in `.env` and re-run `./install.sh`. One job: `crontab -e` (re-runs put it back; edit the `job` list in `lib/install-automation.sh` for good).
- Quiet hours, topics, ntfy server, size cap: **Settings** (wins over `.env`). Thresholds baked into the scripts (80/90/95 %, the resource lines, 20 min): edit `scripts/<name>.py` and re-run the installer.
- Run one now: `WARDEN_ENV=<stack>/warden.env python3 <stack>/active/<name>.py`. Reset its memory: delete its state file.
