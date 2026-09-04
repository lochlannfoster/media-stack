# Services

What runs, where it listens, what it stores, and how the pieces hand work on. Ports are the `.env` defaults. One page per service under [`services/`](services/) says what each does, how to use it and what usually goes wrong.

Related: [AUTOMATION.md](AUTOMATION.md) · [CONFIGURATION.md](CONFIGURATION.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

```
You ─▶ Jellyseerr :5055 ─▶ Radarr :7878 / Sonarr :8989 ─▶ [ your indexer + download client ]
        request              track and pick                       (you supply these)
                                                                            │ import
   Controllarr :3002 drives all of it     Bazarr :6767 subtitles ─▶ Jellyfin :8096 ◀────┘ /data/media
   cron jobs keep it healthy              [ntfy :8090 tells your phone]
```

## Every service

Core services always run; ntfy is a Compose profile (`COMPOSE_PROFILES`), Tailscale comes from the generated override.

| Service | Port | Role | Data |
|---|---|---|---|
| [**Controllarr**](services/controllarr.md) | 3002 | the control panel, installed from [its own repository](https://github.com/lochlannfoster/controllarr) | `CONFIG_DIR/controllarr` |
| [**Jellyfin**](services/jellyfin.md) | 8096 | player, library, users, transcoding (VAAPI via `/dev/dri`) | `CONFIG_DIR/jellyfin`; `DATA_DIR/media` at `/data/media` |
| [**Jellyseerr**](services/jellyseerr.md) | 5055 | requests, approvals, per-user auto-approve | `CONFIG_DIR/jellyseerr` |
| [**Radarr**](services/radarr.md) / [**Sonarr**](services/sonarr.md) | 7878 / 8989 | film / TV automation into `/data/media/{movies,tv}` | `CONFIG_DIR/<app>`; `DATA_DIR` at `/data` |
| [**Bazarr**](services/bazarr.md) | 6767 | subtitle providers, languages, scoring, upgrades | `CONFIG_DIR/bazarr`; `DATA_DIR` at `/data` |
| [**autoheal**](services/autoheal.md) | — | restarts unhealthy containers labelled `autoheal=true` | Docker socket (rw) |
| [**ntfy**](services/ntfy.md) | 8090 | push topics `media` (quiet-hours aware) and `admin` | `CONFIG_DIR/ntfy` |
| [**Tailscale**](services/tailscale.md) | host network | the stack reachable from your own devices, nothing opened on the router | `tailscale.env`; `CONFIG_DIR/tailscale` |
| [**gluetun**](services/gluetun.md) | publishes the routed services' ports | optional VPN tunnel for Radarr, Sonarr and Bazarr's outbound traffic | `vpn.env` |

Services reach each other by container name on the Compose bridge (`http://radarr:7878`). Radarr, Sonarr, Bazarr and Jellyseerr use public DNS (`1.1.1.1`, `9.9.9.9`) so lookups do not depend on the router — except where [gluetun](services/gluetun.md) routes one, which takes over both its DNS and its published port.

## What this stack does not include

**An indexer and a download client.** Radarr and Sonarr are the automation; what they search and what fetches the result are yours to choose and configure in their own settings. Nothing here installs, configures or ships a list of either — and nothing here will touch what you add.

One consequence worth knowing: keep whatever your client writes to on the **same filesystem** as `DATA_DIR/media`, so the arrs import by hardlink — instant, one copy on disk. Across filesystems every import becomes a full copy.

## The library tree

```
DATA_DIR/media/movies    Radarr's root folder
DATA_DIR/media/tv        Sonarr's root folder
```

Mounted at `/data` in Radarr, Sonarr and Bazarr, and at `/data/media` in Jellyfin.

## Selection rules

**Which release is worth having is TRaSH Guides' answer, not this stack's.** Custom formats, their scores, which qualities a profile allows and the size limit per quality come from the guide, and are previewed as a diff and applied on a press in **Settings ▸ Quality & size ▸ TRaSH Guides**. This installer creates no custom format and writes no size limit; nothing here syncs on a schedule.

What the installer and the panel do still set, through the same `settings_ops.py` so they agree:

- **Audio language:** `AUDIO_LANGUAGE` sets the language on Radarr's quality profiles. Sonarr v4 profiles have no language field, so TV has no equivalent — the custom formats that used to fake one are the guide's now.
- **Release threshold:** `MIN_SEEDERS`, per indexer, plus Prowlarr's app profile so its sync does not undo it.
- **Media management:** propers, renaming, hardlinks, the recycle bin and the free-space floor.

## Removing a title

The panel's **Purge** removes a title from every app at once: its files from Radarr or Sonarr, its request and media record from Jellyseerr, then Bazarr and Jellyfin are asked to rescan so it disappears there too. Below the title — a season or ticked episodes — the files go and the episodes are untracked; when that leaves a show with nothing on disk and nothing tracked, the show goes too. The confirmation says exactly this, with real counts, first.

## Mounts of note

| Mount | Into | Why |
|---|---|---|
| `CONFIG_DIR/controllarr/settings.local` (ro) | radarr, sonarr | the notify hooks read panel-set quiet hours and topics |
| `CONFIG_DIR` (ro) + `CONFIG_DIR/controllarr` (rw) | controllarr | reads every app's API key; writes only its own folder |
| `DATA_DIR` (ro), `BACKUP_DIR` (ro) | controllarr | free space on the media volume; the newest backup's age |
| `./controllarr/app` (ro) | controllarr | the panel's code, from its own repository at a pinned version |
| `/var/run/docker.sock` (ro) | controllarr | container state, memory and last log lines. Read-only, but socket access is root-equivalent on the host — a LAN-only trade-off |
| `/var/run/docker.sock` (rw) | autoheal | it restarts containers |
| `/dev/dri` | jellyfin | from the override when the host has a GPU |

## Healthchecks and autoheal

Healthchecks (60 s, 3 retries) and the `autoheal=true` label come as a pair on **jellyfin, jellyseerr, radarr, sonarr, bazarr, controllarr** and tailscale; autoheal restarts one after three failed checks (≈ 3 min). `tests/check_compose.py` enforces the pairing.
