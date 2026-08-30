# Radarr

Movie automation. Core tier, port **7878**, container `radarr`.

**What it does.** For every monitored film: searches whichever indexers you gave it, picks a release by this stack's rules (size per minute of runtime, audio language, codec), hands it to your download client, imports the finished file into `/data/media/movies` as a hardlink, renames it, and tells Jellyfin.

**How to use it.** You rarely open it: requests come from Jellyseerr, the rules from Settings ▸ Quality & size ▸ Movies, per-title controls (profile, availability, root folder, search, blocklist, purge) from the panel's drawer. Its own UI (`http://<server-ip>:7878`, login from `secrets.env`) is for the odd manual import or a look at the history.

**How it fits.** Root folder `/data/media/movies`. The installer sets the quality, size and language rules and the UI login, and nothing else: **the indexers and the download client are yours to add**, in Radarr's own Settings. Until you do it tracks titles but never grabs one. Custom formats carry the language and codec preferences ([SERVICES.md ▸ Selection rules](../SERVICES.md#selection-rules)); the notify hook posts *Ready to watch* to ntfy; the panel's purge removes the film with its files and clears it from Jellyseerr, Bazarr and Jellyfin.

**Common issues.**
- *Unavailable — too big / quality not allowed* → the rules did their job; loosen them in Settings ▸ Quality & size, or open the title and grab a release by hand.
- Nothing is ever found → Radarr has no indexer, or no download client to hand it to. Both are yours to add.
- A *RemotePathMappingCheck* health warning → the folder your download client reports is not visible to Radarr at the same path; mount it identically in both.

Related: [sonarr.md](sonarr.md) · [SERVICES.md](../SERVICES.md) · [AUTOMATION.md](../AUTOMATION.md)
