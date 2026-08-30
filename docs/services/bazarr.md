# Bazarr

Subtitles. Core tier, port **6767**, container `bazarr`.

**What it does.** Watches Radarr and Sonarr for new files, asks the enabled subtitle providers for the languages in its profile, downloads the best-scoring subtitle next to the file, and upgrades it later if a better one appears.

**How to use it.** Languages, hearing-impaired / forced preference, scores, upgrades, embedded-subtitle handling and the provider list are Settings ▸ Subtitles in the panel; an OpenSubtitles.com account (asked at install) gives much better coverage. Per title: **Fetch subs** (search now) and **Manual search…** (pick a candidate) in the drawer; per episode in the episode list. The Library shows a *subs* / *no subs* word on every movie and, inside a show, on every episode.

**How it fits.** Connected to both arrs by API key; one language profile, applied to every title by default. The sub-warden runs a provider-wide search **hourly on purpose** — providers lock accounts that are hammered — and the panel reads Bazarr's wanted lists to label titles and episodes. After a purge the panel asks Bazarr to resync so the title disappears from its lists.

**Common issues.**
- No subtitles after an import → give it 20 minutes; then **Fetch subs**; then check the providers and *Minimum score* in Settings ▸ Subtitles.
- A Settings save is refused → Bazarr 1.6 validates strictly (booleans lowercase, a profile must carry `audio_only_include`); the panel shows its message and `docker logs bazarr` has the traceback.
- A provider stops answering → its account is rate-limited; wait, do not retry in a loop.

Related: [SERVICES.md](../SERVICES.md) · [AUTOMATION.md](../AUTOMATION.md)
