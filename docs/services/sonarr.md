# Sonarr

TV automation. Core tier, port **8989**, container `sonarr`.

**What it does.** For every monitored show: tracks which episodes exist, searches whichever indexers you gave it season by season or episode by episode, picks releases by this stack's rules, imports finished files into `/data/media/tv/<show>/Season NN` as hardlinks and tells Jellyfin.

**How to use it.** Requests come from Jellyseerr; the rules from Settings ▸ Quality & size ▸ TV. In the panel a show expands into its episode list — tick episodes for a search, subtitles, tracking or a purge — and the drawer carries series type, root folder, *Monitor all + search*. Its own UI (`http://<server-ip>:8989`) is for manual imports and history.

**How it fits.** Root folder `/data/media/tv`; the indexers and download client are yours to add, as for Radarr. The *series complete* notify hook fires when every episode is on disk; Bazarr follows it for subtitles. The Library's stage for a show is judged on the **first tracked season still missing episodes**, and a show with files and gaps is *Partial*, never *Available*. A purge below the title untracks what it deletes; when nothing on disk and nothing tracked remains, the show is removed everywhere too.

**Common issues.**
- *Can't match releases to this show* → naming; set the series type (anime / daily) or grab by hand.
- A show stays *Partial* → intended: any missing episode in a tracked season; untrack the episodes you do not want.
- A *RemotePathMappingCheck* health warning → the folder your download client reports is not visible to Sonarr at the same path.

Related: [radarr.md](radarr.md) · [SERVICES.md](../SERVICES.md) · [Controllarr](controllarr.md)
