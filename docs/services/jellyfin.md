# Jellyfin

The player. Core tier, port **8096**, container `jellyfin`.

**What it does.** Plays the library on any device (web, phone, TV apps), keeps per-user watch state, transcodes when a client cannot play a file as is.

**How to use it.** `http://<server-ip>:8096`; the installer's *media user #1* is the admin, the others are ordinary users. Libraries *Movies* and *Shows* point at `/data/media/{movies,tv}` and are created by the installer. Hardware transcoding (VAAPI) is switched on when the host has `/dev/dri`; the Intro Skipper plugin is installed and needs one detection run before the skip button appears.

**How it fits.** Radarr and Sonarr carry a *Jellyfin* connection that triggers a targeted library scan on every import **and every deletion**, so a new file plays within seconds and a purged title disappears at once; the panel's **Scan library now** (Settings ▸ Media server) is for files you moved by hand. The panel reads *Now playing* with the `arr-stack` API key the installer mints. Jellyseerr signs its users in against Jellyfin.

**Common issues.**
- No skip-intro button → the plugin's detection task has not run yet; wait or run it in Jellyfin's scheduled tasks.
- Transcoding pegs the CPU → no `/dev/dri`; keep *Prefer h264* on so the CPU decodes cheaply ([INSTALL.md ▸ Requirements](../INSTALL.md#requirements)).
- *Now playing* says *key missing* → re-run `./install.sh` (it writes `JELLYFIN_APIKEY` to `app.env`).
- A purged title still shows → the scan takes a moment; if it stays, Settings ▸ Media server ▸ **Scan library now**.

Related: [SERVICES.md](../SERVICES.md) · [Controllarr](controllarr.md)
