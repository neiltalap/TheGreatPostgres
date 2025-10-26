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
