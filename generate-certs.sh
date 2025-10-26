#!/usr/bin/env bash
set -euo pipefail

# Simple cert generation helper for mTLS Postgres
# - Creates a local CA (if missing)
# - Creates a server cert with SANs
# - Creates one or more client certs (CN must equal Postgres username)

usage() {
  cat <<USAGE
Usage:
  $0 --cn <server-common-name> [--san <SAN>] [--client <dbuser>] [--client <dbuser> ...] [--days <n>] [--force]

Examples:
  # Server CN db.ozinozi.com, SANs DNS:db.ozinozi.com and IP:203.0.113.10, and a client for user dbuser
  $0 --cn db.ozinozi.com --san DNS:db.ozinozi.com --san IP:203.0.113.10 --client dbuser

  # If SAN not provided, it defaults to DNS:<CN> (or IP:<CN> when CN is an IPv4 address)

Output:
  - certs/ca.key, certs/ca.crt
  - certs/server.key, certs/server.crt
  - client-certs/<user>.key, client-certs/<user>.crt
  - Also creates client-certs/client.key and client-certs/client.crt from the first client if not present

Notes:
  - Keys are 4096-bit RSA. Keys are chmod 600.
  - Client CN must equal the Postgres username (or configure pg_ident).
USAGE
}

CN=""
SANS=""        # comma-separated list e.g. "DNS:example.com,IP:1.2.3.4"
CLIENTS=""     # space-separated list of usernames
DAYS=825
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn) CN="$2"; shift 2;;
    --san) SANS="${SANS:+$SANS,}$2"; shift 2;;
    --client) CLIENTS+=" ${2}"; shift 2;;
    --days) DAYS="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl not found. Please install openssl." >&2
  exit 1
fi

mkdir -p certs client-certs

if [[ -z "$CN" ]]; then
  echo "Error: --cn is required (server common name, e.g., db.ozinozi.com)." >&2
  usage
  exit 1
fi

# Default SAN if not provided
if [[ -z "${SANS}" ]]; then
  if [[ "$CN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    SANS="IP:$CN"
  else
    SANS="DNS:$CN"
  fi
fi

SAN_STRING="$SANS"

# 1) Create CA if missing
if [[ ! -f certs/ca.key || ! -f certs/ca.crt || $FORCE -eq 1 ]]; then
  echo "[certs] Generating CA"
  openssl genrsa -out certs/ca.key 4096 >/dev/null 2>&1
  openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days $((DAYS*4)) \
    -subj "/CN=ozinozi-db-ca" -out certs/ca.crt >/dev/null 2>&1
else
  echo "[certs] Using existing CA (certs/ca.crt)"
fi

# 2) Server key + CSR + signed cert with SAN
if [[ -f certs/server.key || -f certs/server.crt ]]; then
  if [[ $FORCE -eq 1 ]]; then
    rm -f certs/server.key certs/server.csr certs/server.crt
  else
    echo "[certs] Server cert exists; use --force to overwrite" >&2
  fi
fi

echo "[certs] Generating server certificate for CN=$CN, SAN=$SAN_STRING"
cat > certs/server.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
req_extensions = v3_req

[dn]
CN = ${CN}

[v3_req]
subjectAltName = ${SAN_STRING}
EOF

openssl genrsa -out certs/server.key 4096 >/dev/null 2>&1
openssl req -new -key certs/server.key -out certs/server.csr -config certs/server.cnf >/dev/null 2>&1
openssl x509 -req -in certs/server.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/server.crt -days "$DAYS" -sha256 -extensions v3_req -extfile certs/server.cnf >/dev/null 2>&1
chmod 600 certs/server.key
echo "[certs] Wrote certs/server.crt and certs/server.key"

# 3) Client certs for provided users
FIRST_CLIENT=""
for user in ${CLIENTS}; do
  [[ -z "$user" ]] && continue
  [[ -z "$FIRST_CLIENT" ]] && FIRST_CLIENT="$user"
  echo "[certs] Generating client certificate for user=$user"
  cat > "client-certs/${user}.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no

[dn]
CN = ${user}
EOF
  openssl genrsa -out "client-certs/${user}.key" 4096 >/dev/null 2>&1
  openssl req -new -key "client-certs/${user}.key" -out "client-certs/${user}.csr" -config "client-certs/${user}.cnf" >/dev/null 2>&1
  openssl x509 -req -in "client-certs/${user}.csr" -CA certs/ca.crt -CAkey certs/ca.key \
    -out "client-certs/${user}.crt" -days "$DAYS" -sha256 >/dev/null 2>&1
  chmod 600 "client-certs/${user}.key"
  echo "[certs] Wrote client-certs/${user}.crt and .key"
done

# 4) Default client symlinks/copies for convenience
if [[ -n "$FIRST_CLIENT" ]]; then
  if [[ ! -f client-certs/client.crt && -f "client-certs/${FIRST_CLIENT}.crt" ]]; then
    cp "client-certs/${FIRST_CLIENT}.crt" client-certs/client.crt
  fi
  if [[ ! -f client-certs/client.key && -f "client-certs/${FIRST_CLIENT}.key" ]]; then
    cp "client-certs/${FIRST_CLIENT}.key" client-certs/client.key
    chmod 600 client-certs/client.key
  fi
fi

echo "[certs] Done. Place files as mounted by docker-compose and restart Postgres:"
echo "  docker compose up -d --force-recreate postgres"
