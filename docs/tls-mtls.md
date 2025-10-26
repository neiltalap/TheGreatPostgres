# TLS (mTLS) for Postgres

This stack enforces certificate-based authentication (no passwords) by configuring Postgres for TLS with client certificate verification.

Server files (place on host):
- certs/server.crt — server certificate (PEM)
- certs/server.key — server private key (PEM, chmod 600)
- certs/ca.crt — CA that signs client certificates

Client files (per user/app):
- client-certs/client.crt — client certificate signed by the same CA
- client-certs/client.key — client private key (keep secure)
- ca.crt — same CA used by the server (for sslrootcert)

Important: The client certificate Common Name (CN) must equal the Postgres username (or set up pg_ident mapping).

## Generate a minimal CA, server cert (with SAN), and client cert

```bash
# 1) Create a Certificate Authority (CA)
mkdir -p certs client-certs
openssl genrsa -out certs/ca.key 4096
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 3650 \
  -subj "/CN=ozinozi-db-ca" -out certs/ca.crt

# 2) Create server key + CSR with SAN
cat > certs/server.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
req_extensions = v3_req

[dn]
CN = db.ozinozi.com

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = db.ozinozi.com
# Add your server's public IP if desired
# IP.1 = 203.0.113.10
EOF

openssl genrsa -out certs/server.key 4096
openssl req -new -key certs/server.key -out certs/server.csr -config certs/server.cnf
openssl x509 -req -in certs/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/server.crt -days 825 -sha256 -extensions v3_req -extfile certs/server.cnf
chmod 600 certs/server.key

# 3) Create a client cert for a Postgres user (CN must equal DB username)
# Example for DB user "dbuser"
cat > client-certs/client.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no

[dn]
CN = dbuser
EOF

openssl genrsa -out client-certs/client.key 4096
openssl req -new -key client-certs/client.key -out client-certs/client.csr -config client-certs/client.cnf
openssl x509 -req -in client-certs/client.csr -CA certs/ca.crt -CAkey certs/ca.key \
  -out client-certs/client.crt -days 825 -sha256
```

Restart Postgres after placing certs:

```bash
docker compose up -d --force-recreate postgres
```

## Connect via Cloudflare Tunnel with mTLS

```bash
# On the client host
cloudflared access tcp --hostname db.ozinozi.com --url 127.0.0.1:15432

# Then connect with client cert + CA verification
psql "host=127.0.0.1 port=15432 dbname=production_db user=dbuser \
      sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key"
```

## Backup/Restore containers

Place a copy of the client certs for the backup/restore identity in `client-certs/` and the CA in `client-certs/`. The compose mounts these into the containers and sets `PGSSLMODE`, `PGSSLROOTCERT`, `PGSSLCERT`, `PGSSLKEY` so the tools authenticate with mTLS automatically.
