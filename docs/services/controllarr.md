# Controllarr

The control panel. Core, port **3002**, container `controllarr`.

**What it does.** One page that shows what needs a person (a stuck title, a request waiting, disk filling up, a container down), what is moving, the whole library by stage, and a Settings page for every app — so you rarely open Radarr, Sonarr, Bazarr or a shell.

**How to use it.** `http://<server-ip>:3002`, sign in as `admin` with the password the installer asked for. Read it top to bottom: the Line, System, Needs attention, Downloads, Library, Reference.

**How it fits.** Controllarr is its **own project** — [github.com/lochlannfoster/controllarr](https://github.com/lochlannfoster/controllarr) — and this stack installs it rather than carrying a copy: `install.sh` clones it at the version pinned by `CONTROLLARR_REF` into `./controllarr` and the compose file runs that code read-only. Its full documentation lives in that repository. The stack also borrows one module from it, `settings_ops.py`, so the installer and the panel's Settings write Radarr and Sonarr identically.

It reads every app over its API (keys read live from `CONFIG_DIR`), the Docker socket read-only for container state, and writes only `CONFIG_DIR/controllarr`.

**Common issues.**
- *Locked out* / *no login, everyone is admin* → [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#the-control-panel).
- A Settings group missing → that app is not part of this install.
- To move to a newer panel: set `CONTROLLARR_REF` in `.env` and re-run `./install.sh`.

Related: [SERVICES.md](../SERVICES.md)
