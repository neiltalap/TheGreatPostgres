# Cloudflare Tunnel for Postgres (TCP)

This adds an optional Cloudflare Tunnel to reach Postgres without exposing port 5432 publicly.

There are two common patterns:
- Dashboard‑managed tunnel token (simple): define hostname and TCP access in Cloudflare; compose runs `cloudflared` with a token.
- Local config file: mount a `config.yml` with explicit ingress and run the tunnel from compose.

Important
- For public TCP exposure of Postgres at a DNS hostname, Cloudflare Spectrum is required (Enterprise). Without Spectrum, use Access TCP (end users run a local `cloudflared` client) or WARP private routing.
- The server still enforces mTLS. Cloudflare adds an outer layer but does not replace database TLS.

## 1) Enable the service

- In `.env`, set:
  - `CLOUDFLARE_TUNNEL_TOKEN=<copy-from-Cloudflare>`
- Start the service (profile `tunnel`):
  - `docker compose --profile tunnel up -d cloudflared`

The compose file runs: `cloudflared tunnel --no-autoupdate run --token $CLOUDFLARE_TUNNEL_TOKEN`.

## 2) Cloudflare Zero Trust setup

In the Cloudflare Dashboard (Zero Trust):

A) Create a Tunnel
- Zero Trust → Access → Tunnels → Create Tunnel
- Name it (e.g., `pg-tunnel`) and select Docker → copy the `--token` string.
- Paste that into `.env` as `CLOUDFLARE_TUNNEL_TOKEN`.

B) Choose how clients connect

Option B1 — Access TCP (recommended for admins/devs)
- Create an Access Application (Type: TCP; or Application: PostgreSQL if available in your account).
- Domain: `db.example.com` (CNAME managed by Cloudflare to the tunnel)
- Policies: allow your users/groups
- No origin policy changes needed; cloudflared will route to `postgres:5432` inside the Docker network.

Client usage (port-forward via Access):
- Install cloudflared on the client.
- Start a local listener that forwards to your tunnel hostname:
  - `cloudflared access tcp --hostname db.example.com --listener 127.0.0.1:6543`
- Connect your DB tool to the local port 6543 using mTLS. For verify-full hostname checks, pass both hostaddr and host:
  - psql:
    - `psql "host=db.example.com hostaddr=127.0.0.1 port=6543 dbname=myapp user=appuser sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key"`
  - DataGrip:
    - Host: `db.example.com`, Port: `6543` (connects to the local listener)
    - Advanced (JDBC): add `hostaddr=127.0.0.1`
    - SSL: Mode `verify-full`, CA+client cert/key from `client-certs/`

Option B2 — WARP private routing (for fleets)
- Enable WARP on client devices.
- In the tunnel, enable `Warp Routing` and add a private route that includes the Docker network IP of the `cloudflared` container (or a dedicated internal IP range you serve behind the tunnel).
- Create a private DNS record (e.g., `db.internal.example`) that resolves to a routed private IP, and configure the tunnel to forward TCP 5432 to `postgres:5432`.
- Clients connected to WARP can connect directly to `db.internal.example:5432` while Postgres still enforces mTLS.

Option B3 — Spectrum (public TCP at DNS) [Enterprise]
- If you need a public TCP endpoint `db.example.com:5432` without client cloudflared/WARP, configure Cloudflare Spectrum to proxy to the tunnel/origin. Spectrum is a paid feature.

## 3) Optional: local `config.yml`

If you prefer managing ingress locally, mount `./cloudflared` and create `cloudflared/config.yml`:

```
# ./cloudflared/config.yml
# Requires a locally stored credentials file (from `cloudflared tunnel login` and `tunnel create`).
# Replace <TUNNEL_ID> and hostname accordingly.

tunnel: <TUNNEL_ID>
credentials-file: /etc/cloudflared/<TUNNEL_ID>.json

# For Access TCP, define a public hostname; for local-only testing, you can omit
# and use Access routing defined in the dashboard.
ingress:
  - hostname: db.example.com
    service: tcp://postgres:5432
  - service: http_status:404

# Enable WARP private routing (for option B2)
warp-routing:
  enabled: true
```

Update compose to run without the token if you use a local config:
- In `docker-compose.yaml`, change the cloudflared command to:
  - `command: tunnel --no-autoupdate run`

Place the credentials JSON file under `./cloudflared/` (same `<TUNNEL_ID>.json`).

## 4) Secure the origin

- Close public exposure of port 5432 on your server firewall; if you want to prevent accidental exposure from Docker, you can also restrict the port mapping to localhost or remove it:
  - Change `ports: ["5432:5432"]` to `ports: ["127.0.0.1:5432:5432"]` or remove the mapping.
- Postgres still requires mTLS as configured by `pg_hba.conf` and `postgresql.conf`.

## 5) Notes

- The server certificate should contain your public hostname (e.g., `db.example.com`) in its SANs for `verify-full`. The helper script adds `DNS:postgres` for internal clients and you can add more with `--san`.
- Client cert CN must equal the Postgres role (e.g., appuser, datagrip) unless you configure `pg_ident`.
- Backups/restore run inside the Docker network and do not require the tunnel.

