FROM postgres:17-bookworm

# Install TimescaleDB + pgvector for PostgreSQL 17 (Debian-based official image)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      timescaledb-2-postgresql-17 \
      postgresql-17-pgvector \
 && rm -rf /var/lib/apt/lists/*

# No entrypoint changes; configs are mounted via docker-compose and init scripts run as usual.
