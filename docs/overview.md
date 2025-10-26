# Overview

- Postgres 17 (alpine) with static configs.
- Public access over TLS (port 5432) with mutual TLS (mTLS).
- Authentication: TLS client certificates only (no passwords).
- Backups to S3-compatible storage; restore tooling included.

Start here:
- docs/tls-mtls.md — set up server and client certs (mTLS)
- docs/clients.md — how clients connect with mTLS
- docs/backup-restore.md — use backups/restores with mTLS
