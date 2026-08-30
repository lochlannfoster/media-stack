# Tailscale

Private remote access. Security tier, written into the generated override when opted in, container `tailscale`, no published port — it joins the **host's network** so every port of the stack is reachable at the node's tailnet address.

**What it does.** Puts the server on your Tailscale network (a WireGuard mesh between your own devices). From a phone or laptop running Tailscale, `http://<node>:8096` plays Jellyfin, `:5055` requests, `:3002` is the panel — from anywhere, with nothing opened on the router and nothing exposed to the internet.

**How to get the auth key.**
1. A Tailscale account (free for personal use); install the Tailscale app on the devices you will use.
2. login.tailscale.com → **Settings** → **Keys** → **Generate auth key**. *Reusable* is not needed; an expiry of 90 days is fine — the key is only used to join, after that the login persists in `CONFIG_DIR/tailscale`. Tags are optional.
3. `./install.sh` → *Security* → yes to Tailscale, a node name (default `mediastack`), paste the key. The key lands in `tailscale.env` (mode 600, gitignored); on a re-run a blank answer keeps the existing login.
4. Check the node appears in the admin console; with MagicDNS on, `http://mediastack:8096` works from any device on the tailnet.

**How it fits.** `network_mode: host` with `NET_ADMIN` and `/dev/net/tun` (kernel WireGuard, `TS_USERSPACE=false`); state in `CONFIG_DIR/tailscale`, which is in the nightly backup. It changes nothing about how the stack reaches the internet — it only adds a private way in. This is the answer to *watching away from home*.

**Common issues.**
- The container is *unhealthy* → not logged in: the key was rejected or has expired; generate a new one and re-run `./install.sh`. `docker logs tailscale` says which.
- Reachable by IP but not by name → enable MagicDNS in the admin console.
- Key expiry warnings for the node itself → disable key expiry for the server in the admin console (machine → *Disable key expiry*).

Related: [SERVICES.md](../SERVICES.md) · [CONFIGURATION.md ▸ tailscale.env](../CONFIGURATION.md#tailscaleenv)
