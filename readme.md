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
   - `./generate-certs.sh --cn db.ozinozi.com --client dbuser`
   - Places files under `certs/` (server, ca) and `client-certs/` (client)
   - Script auto-sets permissions; it also attempts `chown 999:999` on server certs (optional)
   - If you see `Permission denied` for server.key in logs, run: `./fix-certs-perms.sh --restart`
3) Start Postgres
   - `docker compose up -d postgres`
4) Create extra DB users (if you generated additional client certs)
   - `docker exec -it postgres-prod psql -U postgres -c "CREATE ROLE appuser LOGIN;"`
   - The client cert CN must equal the Postgres role name
5) Open firewall to 5432 for your allowed networks (mTLS required regardless)
6) Test client connection (psql example)
   - `psql "host=db.ozinozi.com port=5432 dbname=production_db user=dbuser sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key"`
7) Configure and test backups
   - Put backup identity certs in `client-certs/` (e.g., create `--client backup` with the script)
   - `./backup-manager.sh setup` (validates S3, builds images, runs a test backup)
   - `./backup-manager.sh list` (verify uploaded backup)
8) Optional: run exporter (Prometheus metrics on 9187)
   - `docker compose up -d postgres-exporter`

More
- docs/overview.md — high-level summary
- docs/tls-mtls.md — TLS and client cert setup
- docs/clients.md — how to connect from clients
- docs/backup-restore.md — backups and restores with mTLS
- docs/commands.md — script usage (generate certs + backup manager)
