# Overview

- Postgres 17 (alpine) with static configs.
- Public access over TLS (port 5432) with mutual TLS (mTLS).
- Authentication: TLS client certificates only (no passwords).
- Backups to S3-compatible storage; restore tooling included.

Start here:
- docs/cloudflare-tunnel.md — expose DB safely via Cloudflare
- docs/tls-mtls.md — set up server and client certs (mTLS)
- docs/backup-restore.md — use backups/restores with mTLS
