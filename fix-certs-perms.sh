#!/usr/bin/env bash
set -euo pipefail

# Fix ownership and permissions of TLS certs for Postgres (inside container)
# Ensures server.key is owned by the postgres user in the container and mode 600.

CONTAINER=${CONTAINER:-postgres-prod}
CERTS_DIR=${CERTS_DIR:-certs}
RESTART=0

usage() {
  cat <<USAGE
Usage: $0 [--container <name>] [--certs <dir>] [--restart]

Options:
  --container, -c   Container name (default: postgres-prod)
  --certs, -d       Path to certs directory on host (default: certs)
  --restart         Restart postgres service via docker compose after fixing
  -h, --help        Show this help

Notes:
  - This script sets:
      chown <uid>:<gid> certs/server.key certs/server.crt certs/ca.crt
      chmod 600 certs/server.key
      chmod 644 certs/server.crt certs/ca.crt
      chmod 755 certs
  - UID/GID are detected from the postgres user inside the running container.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container|-c) CONTAINER="$2"; shift 2;;
    --certs|-d) CERTS_DIR="$2"; shift 2;;
    --restart) RESTART=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required" >&2
  exit 1
fi

if [[ ! -d "$CERTS_DIR" ]]; then
  echo "Error: certs directory not found: $CERTS_DIR" >&2
  exit 1
fi

echo "[fix-certs] Detecting postgres UID/GID inside container: $CONTAINER"
UID_IN=$(docker exec "$CONTAINER" id -u postgres 2>/dev/null || true)
GID_IN=$(docker exec "$CONTAINER" id -g postgres 2>/dev/null || true)

if [[ -z "${UID_IN}" || -z "${GID_IN}" ]]; then
  echo "[fix-certs] Container not accessible; attempting fallback image probe"
  UID_IN=$(docker run --rm postgres:17.5-alpine3.22 id -u postgres)
  GID_IN=$(docker run --rm postgres:17.5-alpine3.22 id -g postgres)
fi

echo "[fix-certs] Using UID:GID ${UID_IN}:${GID_IN}"

SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    echo "Error: need write permission to $CERTS_DIR; re-run with sudo" >&2
    exit 1
  fi
fi

missing=0
for f in server.key server.crt ca.crt; do
  if [[ ! -f "$CERTS_DIR/$f" ]]; then
    echo "[fix-certs] Warning: missing $CERTS_DIR/$f"
    missing=1
  fi
done
if [[ $missing -eq 1 ]]; then
  echo "[fix-certs] Some files are missing. Continuing with available files..."
fi

echo "[fix-certs] Setting ownership and permissions"
$SUDO chmod 755 "$CERTS_DIR"
for f in server.crt ca.crt; do
  if [[ -f "$CERTS_DIR/$f" ]]; then
    $SUDO chown ${UID_IN}:${GID_IN} "$CERTS_DIR/$f"
    $SUDO chmod 644 "$CERTS_DIR/$f"
  fi
done
if [[ -f "$CERTS_DIR/server.key" ]]; then
  $SUDO chown ${UID_IN}:${GID_IN} "$CERTS_DIR/server.key"
  $SUDO chmod 600 "$CERTS_DIR/server.key"
fi

echo "[fix-certs] Done."

if [[ "$RESTART" -eq 1 ]]; then
  if command -v docker compose >/dev/null 2>&1; then
    docker compose up -d --force-recreate postgres
  else
    docker-compose up -d --force-recreate postgres
  fi
  echo "[fix-certs] Restarted postgres container. Check logs: docker logs -n 50 ${CONTAINER}"
else
  echo "[fix-certs] You can restart postgres with: docker compose up -d --force-recreate postgres"
fi

