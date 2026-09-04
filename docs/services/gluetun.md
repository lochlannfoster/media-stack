# gluetun

Optional VPN tunnel. Security tier, written into the generated override when opted in, container `gluetun`. It publishes the ports of the services routed through it; those services publish nothing of their own.

**What it does.** Creates one VPN tunnel and lends its network namespace to the services you choose. Their outbound traffic — API calls, the indexers you added, subtitle providers — leaves through your VPN provider instead of your ISP connection. It also owns the firewall for those containers: **when the tunnel drops they have no network at all**, which is the reason to use a shared namespace rather than a per-container proxy.

**What it does not do.** It does not route Jellyfin or Jellyseerr, and there is no option to. Jellyfin serves LAN clients and does its own local playback; Jellyseerr talks to TMDB. Tunnelling either adds failure modes and buys nothing. It also does not forward any port inbound — nothing in this stack needs one.

**Which services are routable.** Radarr, Sonarr and Bazarr: the three that make outbound calls to third parties. If you have not added an indexer yet (this stack ships none — see [SERVICES.md ▸ what this stack does not include](../SERVICES.md#what-this-stack-does-not-include)), the tunnel still covers Bazarr's subtitle providers and the arrs' metadata lookups. An overlay may add services of its own.

**Setting it up.**

1. Choose any provider gluetun supports — [the list is in its wiki](https://github.com/qdm12/gluetun-wiki), around fifty of them. Your existing subscription almost certainly works.
2. Write `vpn.env` next to `docker-compose.yml`. It is passed to the container verbatim, so the variable names are gluetun's own, not this stack's. WireGuard:

   ```sh
   VPN_SERVICE_PROVIDER=<your provider>
   VPN_TYPE=wireguard
   WIREGUARD_PRIVATE_KEY=<from your provider's config>
   WIREGUARD_ADDRESSES=10.2.0.2/32
   SERVER_COUNTRIES=Netherlands
   ```

   OpenVPN:

   ```sh
   VPN_SERVICE_PROVIDER=<your provider>
   VPN_TYPE=openvpn
   OPENVPN_USER=<username>
   OPENVPN_PASSWORD=<password>
   SERVER_COUNTRIES=Netherlands
   ```

   The file is gitignored and never written by the installer — it is yours, and its contents are never copied into `.env`.
3. `./install.sh` → *VPN* → yes. The installer checks the file exists and sets `VPN_SERVICE_PROVIDER`; if either is missing it says so and leaves the VPN off rather than starting a broken tunnel.
4. Confirm: `docker logs gluetun` ends with the tunnel up, and `docker compose exec radarr wget -qO- https://ipinfo.io/ip` shows your provider's address, not yours.

**How it fits.** `cap_add: [NET_ADMIN]`, `/dev/net/tun`, `env_file: [./vpn.env]`, `autoheal=true`. Routed services get `network_mode: "service:gluetun"` and have their `ports` and `dns` reset — Docker refuses `dns` alongside `network_mode: service:`, and their ports move to gluetun, which is why they are unreachable if you edit the override by hand and forget one.

**A tunnel with nothing behind it is never created.** If `VPN_ROUTE` ends up empty the installer disables the VPN and says so. An idle VPN container protects nothing.

**Common issues.**
- Radarr, Sonarr or Bazarr unreachable after enabling → the tunnel is down, so they have no network. `docker logs gluetun`; the usual causes are a wrong key, an expired subscription or a country with no server.
- `gluetun` unhealthy at startup → wrong credentials or `VPN_SERVICE_PROVIDER` misspelled; gluetun names the provider it expected in its log.
- Slow subtitle or metadata fetches → normal; pick a nearer `SERVER_COUNTRIES`.
- You want a routed service back on the LAN directly → re-run `./install.sh` and answer no; the override is regenerated and the ports return to the services.

Related: [SERVICES.md](../SERVICES.md) · [CONFIGURATION.md ▸ vpn.env](../CONFIGURATION.md#vpnenv)
