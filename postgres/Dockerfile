FROM timescale/timescaledb:latest-pg17

# Install pgvector for PostgreSQL 17
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-17-pgvector \
 && rm -rf /var/lib/apt/lists/*

# No entrypoint changes; configs are mounted via docker-compose and init scripts run as usual.
