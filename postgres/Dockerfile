FROM postgres:17-bookworm

# Install TimescaleDB + pgvector for PostgreSQL 17 (Debian-based official image)
# - Adds TimescaleDB APT repo from packagecloud (bookworm)
# - Uses PGDG (present in base image) for pgvector
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey \
      | gpg --dearmor -o /etc/apt/keyrings/timescaledb.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/debian/ bookworm main" \
      > /etc/apt/sources.list.d/timescaledb.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      timescaledb-2-postgresql-17 \
      postgresql-17-pgvector; \
    rm -rf /var/lib/apt/lists/*

# No entrypoint changes; configs are mounted via docker-compose and init scripts run as usual.
