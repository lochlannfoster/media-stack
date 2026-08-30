# Development — how the stack is built, tested and extended

For contributors: how the pieces fit, the invariants that are easy to break, how to test, and how a private overlay adds to the stack without forking it. Operators want [SERVICES.md](SERVICES.md).

Related: [SERVICES.md](SERVICES.md) · [AUTOMATION.md](AUTOMATION.md) · [CONFIGURATION.md](CONFIGURATION.md)

## 1. Layout

| Path | What |
|---|---|
| `install.sh`, `uninstall.sh` | the entry points; interactive (`ask` reads `/dev/tty`) |
| `lib/common.sh`, `preflight.sh`, `summary.sh` | prompt/log helpers, host checks + port clashes, the summary |
| `lib/install-automation.sh` | after the containers are up: `warden.env`, `controllarr.env`, `active/`, notify hooks, the Jellyfin key, the crontab |
| `lib/wiring.py`, `wiring_media.py` | idempotent post-up configuration of Radarr, Sonarr, Bazarr, Jellyfin and Jellyseerr over their APIs |
| `docker-compose.yml` | the stack; `install.sh` generates the gitignored `docker-compose.override.yml` |
| `scripts/*.py`, `*.sh`, `*.tmpl` | the cron jobs, the backup, the two notify hooks |
| `controllarr/` | the control panel, cloned from its own repository (gitignored) |
| `tests/` | the validation pipeline (§4) |
| `docs/services/` | one page per service |

**What runs is a copy:** cron runs `<stack>/active/*`, and the panel runs `./controllarr/app` from a read-only mount. A change under `scripts/` is inert until `install-automation.sh` copies it.

## 2. The control panel is a dependency, not part of this repository

Controllarr lives at [github.com/lochlannfoster/controllarr](https://github.com/lochlannfoster/controllarr). `install.sh` clones it at `CONTROLLARR_REF` and the compose file mounts `./controllarr/app` read-only. Two consequences:

- **`settings_ops.py` is shared.** `lib/wiring.py` imports it from the clone, so a fresh install and a Settings save in the panel write Radarr and Sonarr identically. Changing how quality or size is applied is a change *there*.
- **The panel's own tests are there too.** This repository tests the installer, the compose file and the cron jobs; it does not test the panel.

To develop against a local checkout, point `CONTROLLARR_REPO` at it (`/path/to/controllarr`) and re-run.

## 3. Wiring

Container names on the compose network. Radarr / Sonarr v3: `X-Api-Key` read live from `config.xml`. Bazarr: `X-API-KEY` from `config.yaml`. Jellyfin: the `arr-stack` key the installer mints, written to `warden.env` and `controllarr.env` as `JELLYFIN_APIKEY`. Jellyseerr: key from `settings.json`. Every step is idempotent — existing objects are updated, never duplicated — and none of it touches an indexer or a download client.

## 4. Validation

```bash
tests/run.sh lint      # bash -n (+ shellcheck), ast.parse, ruff, Markdown links
tests/run.sh unit      # tests/unit: the config loader and its settings.local overlay
tests/run.sh compose   # docker compose config + tests/check_compose.py
tests/run.sh all
```

`check_compose.py` enforces the invariants that bite silently: `container_name` equals the service key, a healthcheck and the `autoheal=true` label come as a pair, every `${VAR}` without a default is in `.env.example`, and the panel keeps its read-only socket, its pinned code mount, its `/health` probe and port 3002.

## 5. Overlays

`MEDIA_STACK_OVERLAY=<dir> ./install.sh` lets a separate repository add to this stack without forking it. Each hook is optional; all of them are sourced by `install.sh` or `install-automation.sh` with the installer's own variables in scope (`CFG`, `SEC`, `PROFILES`, `CONFIG_DIR`, `SERVICES`, `EXPECTED`).

| File in the overlay | When | Purpose |
|---|---|---|
| `overlay.env` | prompt defaults | `KEY=value` lines, loaded with the lowest priority |
| `prompts.sh` | after *Optional services* | ask its own questions; append to `PROFILES`, set `CFG`/`SEC` |
| `dirs.sh` | after the directories are made | create any of its own |
| `compose.sh` | writing the override | `printf` its service stanzas into the generated override |
| `services.sh` | automation | append to `SERVICES` (what the panel connects to) and `EXPECTED` (container names) |
| `warden-env.sh`, `controllarr-env.sh` | automation | append lines to `warden.env` / `controllarr.env` |
| `scripts/` | automation | copied into `active/` alongside this repository's |
| `cron.sh` | automation | emit `job "<schedule>" <script> <timeout>` lines |
| `wiring.sh` | after the core wiring | configure its own services |
| `overlay-summary.txt` | the summary | appended to `INSTALL-SUMMARY.txt` |

The rule that keeps the split honest: **this repository never learns what an overlay is for.** It exposes hooks; the overlay supplies everything else.

## 6. Conventions

- **Commits:** `<area>: <lowercase statement>` — areas `installer`, `compose`, `wiring`, `automation`, `docs`, `tests`, `repo` — no trailing full stop; the body says why and how it was verified. A behaviour change updates its docs (and `.env.example` when a knob changes) in the same commit.
- **Docs:** one home per fact — *how it works* in the subsystem doc, *which variable or file* in CONFIGURATION, *what to do when it breaks* in TROUBLESHOOTING, *how to change the code* here; every other mention is one sentence and a link. Before editing, `git grep` the changed symbol across `docs/ README.md .env.example` and fix every copy. British spelling, sentence-case headings, placeholders `<server-ip>`, `~/media-stack`, `/srv/media/…` — never a real host. Cite function and module names, never line numbers.
