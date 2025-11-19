FROM postgres:17-bookworm

# Install TimescaleDB + pgvector for PostgreSQL 17 (Debian-based official image)
# - Adds TimescaleDB APT repo from packagecloud (bookworm)
# - Uses PGDG (present in base image) for pgvector
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg git build-essential postgresql-server-dev-17; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey \
      | gpg --dearmor -o /etc/apt/keyrings/timescaledb.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/debian/ bookworm main" \
      > /etc/apt/sources.list.d/timescaledb.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      timescaledb-2-postgresql-17 \
      postgresql-17-pgvector; \
    # Build and install pg_cron from source (ensures availability for PG17)
    git clone --depth 1 --branch v1.6.2 https://github.com/citusdata/pg_cron.git /tmp/pg_cron; \
    make -C /tmp/pg_cron; \
    make -C /tmp/pg_cron install; \
    rm -rf /tmp/pg_cron; \
    # Clean up build dependencies and apt cache
    apt-get purge -y --auto-remove build-essential git postgresql-server-dev-17; \
    rm -rf /var/lib/apt/lists/*

# No entrypoint changes; configs are mounted via docker-compose and init scripts run as usual.
