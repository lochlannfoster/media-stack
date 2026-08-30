# Jellyseerr

The request app — the one page the household uses. Core tier, port **5055**, container `jellyseerr`.

**What it does.** Search any movie or show, tap *Request*; the request goes to Radarr or Sonarr with the default quality profile and root folder, and Jellyseerr shows its progress until it is playable in Jellyfin.

**How to use it.** `http://<server-ip>:5055`, sign in with your Jellyfin account (users are imported by the installer; the admin is *media user #1*). A user marked *auto-approve* at install skips the approval step; everyone else's requests appear under **Needs attention** in the panel with **Approve** / **Decline**. Defaults for new requests (profile, root folder) live in Settings ▸ Requests.

**How it fits.** Jellyseerr ⇄ Radarr/Sonarr by API key over the Compose network; it marks a title available when Jellyfin has it. A purge in the panel deletes the request **and** the media record, so a re-request starts clean. The reconcile warden declines requests that stayed unavailable for `RECONCILE_GRACE_DAYS`.

**Common issues.**
- A request stays *processing* → nothing was grabbed; the title's stage reason in the Library says why ([TROUBLESHOOTING.md ▸ Downloads and the library](../TROUBLESHOOTING.md#downloads-and-the-library)).
- Settings ▸ Requests refuses to save → its API rejects a body carrying `id`; the panel reports the message.
- *Update available* pill in Reference → pull the image when convenient (`docker compose pull jellyseerr && docker compose up -d jellyseerr` from the install directory).

Related: [SERVICES.md](../SERVICES.md) · [radarr.md](radarr.md) · [sonarr.md](sonarr.md)
