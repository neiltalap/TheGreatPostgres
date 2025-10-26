# Backup and Restore with mTLS

The backup and restore services connect to Postgres using client certificates.

Place files on the host:
- client-certs/ca.crt — CA that signed the server and client certs
- client-certs/client.crt — client certificate for the backup/restore identity
- client-certs/client.key — client private key (chmod 600)

Compose mounts these to `/client-certs/` and sets the libpq SSL env vars:
- PGSSLMODE=verify-full
- PGSSLROOTCERT=/client-certs/ca.crt
- PGSSLCERT=/client-certs/client.crt
- PGSSLKEY=/client-certs/client.key

No password is used or accepted (server enforces cert-only auth).

## Backup scope

- Database-only (default): backs up a single database from `POSTGRES_DATABASE` using `pg_dump`.
- Cluster-wide: backs up ALL databases and global roles using `pg_dumpall`.

Enable cluster-wide backups by setting `BACKUP_SCOPE=cluster` (in `.env` or the compose). This produces files named like `cluster_YYYY-mm-ddTHH:MM:SSZ.sql.gz` in the same daily/weekly/monthly folders.

Restores
- Database backup: restore connects to `POSTGRES_DATABASE` and runs the SQL.
- Cluster backup: restore feeds the entire script to `psql` (connected to the bootstrap DB, default `postgres`), which recreates roles, creates databases, and restores data. `DROP_PUBLIC` is ignored for cluster restores.

Important
- The server certificate should include `DNS:postgres` in its SANs so that internal services connecting to host `postgres` can pass hostname verification with `PGSSLMODE=verify-full`. The `generate-certs.sh` helper adds this automatically. If you previously generated certs without it, re-generate with `--force`.
- Alternatively, you can relax internal services to `PGSSLMODE=verify-ca` in `docker-compose.yaml` (still mTLS, but without hostname verification) if you prefer not to include `DNS:postgres` in the server cert.
