# ntfy

Phone notifications. Optional tier, profile **`notify`**, port **8090**, container `ntfy`.

**What it does.** A tiny pub/sub server: the wardens and the arr hooks POST to a topic, the ntfy app on your phone subscribed to that topic rings.

**How to use it.** Install the ntfy app, *Add subscription* → *Use another server* → `http://<server-ip>:8090`. Everyone subscribes to the **media** topic (*Ready to watch*, *No subtitles*, *Grabbed a relaxed copy*); the operator also subscribes to **admin** (service down, disk, stalls, the daily digest). Topic names, quiet hours (media notifications silent between them) and a test button are Settings ▸ Notifications. `NTFY_URL` in `.env` points the stack at an external ntfy server instead.

**How it fits.** Unauthenticated read-write on the LAN by design (`NTFY_AUTH_DEFAULT_ACCESS=read-write`); the wardens push through `warden_lib.push`, the hooks inside Radarr/Sonarr read the panel's quiet hours from `settings.local`. Without this profile the wardens still run; pushes are skipped.

**Common issues.**
- Nothing arrives → the profile is off, the phone is subscribed to the wrong server or topic, or it is quiet hours (media pushes arrive silently, not not at all); **Send a test notification** uses the wardens' exact path.
- It can be annoying → raise the quiet hours, or subscribe to *admin* only.

Related: [AUTOMATION.md ▸ Notifications](../AUTOMATION.md#notifications) · [SERVICES.md](../SERVICES.md)
