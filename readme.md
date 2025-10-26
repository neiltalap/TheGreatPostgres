# The Great Postgres — Secure Postgres + Backups

Secure, containerized Postgres 17 with S3 backups and Cloudflare Tunnel access.

Highlights
- Postgres 17 (alpine), no public port exposure
- Cloudflare Tunnel (TCP) access
- Certificate-only authentication (mTLS) — no passwords
- S3-compatible backups + restore tooling

Quickstart
1) Set up Cloudflare Tunnel TCP hostname for Postgres
   - See docs/cloudflare-tunnel.md
2) Generate TLS certs (CA, server with SAN, client per user)
   - Place files under `certs/` (server, ca) and `client-certs/` (client)
   - See docs/tls-mtls.md
3) Bring up services
   - `docker compose up -d postgres cloudflare-tunnel`
4) Connect from client via Cloudflare + mTLS
   - `cloudflared access tcp --hostname db.ozinozi.com --url 127.0.0.1:15432`
   - `psql "host=127.0.0.1 port=15432 dbname=production_db user=dbuser sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key"`
5) Configure backups
   - Place client certs under `client-certs/` for the backup identity
   - See docs/backup-restore.md

More
- docs/overview.md — high-level summary
- docs/cloudflare-tunnel.md — Cloudflare Tunnel config
- docs/tls-mtls.md — TLS and client cert setup
- docs/backup-restore.md — backups and restores with mTLS
