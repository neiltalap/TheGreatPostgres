# Script Commands

This project ships with two main helper scripts: certificate generation and backup management.

## generate-certs.sh

Generates a local CA, a server certificate (with SANs), and one or more client certificates for mTLS. Client certificate CN must equal the Postgres role.

Usage

```
./generate-certs.sh --cn <server-cn> [--san <SAN>] [--client <dbuser>] [--client <dbuser> ...] [--days <n>] [--force]
```

- --cn: Server certificate Common Name (e.g., db.ozinozi.com or 203.0.113.10)
- --san: Subject Alternative Name(s). Repeatable. Examples: `DNS:db.ozinozi.com`, `IP:203.0.113.10`
  - If omitted, defaults to `DNS:<CN>` or `IP:<CN>` when CN is an IPv4 address
- --client: Generate a client cert for this Postgres user (repeat for multiple)
- --days: Validity period (default: 825)
- --force: Overwrite existing CA/server certs

Examples

```
# Minimal: CN=domain, one client user
./generate-certs.sh --cn db.ozinozi.com --client dbuser

# CN + explicit SANs + two client certs
./generate-certs.sh \
  --cn db.ozinozi.com \
  --san DNS:db.ozinozi.com --san IP:203.0.113.10 \
  --client dbuser --client backup
```

Outputs
- Server/CA: `certs/ca.crt`, `certs/ca.key`, `certs/server.crt`, `certs/server.key`
- Clients: `client-certs/<user>.crt`, `client-certs/<user>.key` (+ convenience copies `client-certs/client.crt`, `client.key`)

Apply certs

```
docker compose up -d --force-recreate postgres
```

Connect from clients: see docs/clients.md.

---

## backup-manager.sh

Manages on-demand backups, restores, and the scheduled backup service. Uses mTLS to connect to Postgres; S3-compatible storage for backup files.

Prerequisites
- `.env` filled (copy from `.env.example`).
- S3 credentials valid; bucket accessible.
- Postgres running; certs in `certs/`; backup client certs in `client-certs/`.

Commands

```
./backup-manager.sh backup
```
- Create an immediate backup and upload to S3 (daily folder).

```
./backup-manager.sh list [daily|weekly|monthly]
```
- List recent backups by category (default: daily).

```
./backup-manager.sh restore <filename>
```
- Restore a specific backup (prompts for confirmation).

```
./backup-manager.sh restore-latest
```
- Find the most recent backup across all folders and restore it (prompts).

```
./backup-manager.sh start-backup-service
```
- Start the scheduled backup container (cron defaults to 02:00 UTC daily; weekly/monthly if enabled).

```
./backup-manager.sh stop-backup-service
```
- Stop and remove the scheduled backup container.

```
./backup-manager.sh logs
```
- Tail logs from the backup service.

```
./backup-manager.sh setup
```
- One-time setup: validate env, rebuild images, test S3 connectivity, create S3 folder structure, ensure DB exists, start service, run a test backup.

Notes
- Backup/restore containers authenticate to Postgres with client certs mounted from `client-certs/` (no passwords).
- S3 provider is configurable via `.env` (AWS, Hetzner, MinIO, R2, etc.).
