# The Great Postgres — Secure Postgres + Backups

Secure, containerized Postgres 17 with S3 backups and mutual TLS (mTLS) access.

Highlights
- Postgres 17 (alpine), public TLS on 5432
- Certificate-only authentication (mTLS) — no passwords
- S3-compatible backups + restore tooling

Quickstart
1) Copy env template and fill values
   - `cp .env.example .env` (set S3 credentials and DB names/users)
2) Generate TLS certs (CA, server with SAN, client per user)
   - Place files under `certs/` (server, ca) and `client-certs/` (client)
   - See docs/tls-mtls.md
3) Bring up Postgres
   - `docker compose up -d postgres`
4) Open firewall to 5432 for your allowed networks (optional; mTLS required regardless)
5) Connect from client over the Internet with mTLS
   - `psql "host=db.ozinozi.com port=5432 dbname=production_db user=dbuser sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key"`
6) Configure backups
   - Place client certs under `client-certs/` for the backup identity
   - See docs/backup-restore.md

More
- docs/overview.md — high-level summary
- docs/tls-mtls.md — TLS and client cert setup
- docs/clients.md — how to connect from clients
- docs/backup-restore.md — backups and restores with mTLS
- docs/commands.md — script usage (generate certs + backup manager)
