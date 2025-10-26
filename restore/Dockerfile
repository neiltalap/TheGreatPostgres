FROM alpine:edge

# Install required packages with PostgreSQL 17
RUN apk update && \
    apk add --no-cache \
    postgresql17-client \
    python3 \
    py3-pip \
    gzip \
    coreutils \
    openssl && \
    pip3 install --break-system-packages awscli && \
    rm -rf /var/cache/apk/*

FROM alpine:edge

# Install required packages with PostgreSQL 17
RUN apk update && \
    apk add --no-cache \
    postgresql17-client \
    python3 \
    py3-pip \
    gzip \
    coreutils \
    openssl && \
    pip3 install --break-system-packages awscli && \
    rm -rf /var/cache/apk/*

# Check what PostgreSQL binaries are available and create symlinks
RUN find /usr -name "*pg_*" -type f 2>/dev/null | head -20 && \
    find /usr -name "*psql*" -type f 2>/dev/null | head -10 && \
    ls -la /usr/bin/pg* 2>/dev/null | head -10 || true

# Create symlinks for standard postgresql commands (try different versions)
RUN for ver in 17 16 15; do \
    if [ -f "/usr/bin/pg_dump$ver" ]; then \
    ln -sf "/usr/bin/pg_dump$ver" /usr/bin/pg_dump && \
    ln -sf "/usr/bin/pg_restore$ver" /usr/bin/pg_restore && \
    ln -sf "/usr/bin/psql$ver" /usr/bin/psql && \
    ln -sf "/usr/bin/pg_isready$ver" /usr/bin/pg_isready && \
    if [ -f "/usr/bin/pg_dumpall$ver" ]; then ln -sf "/usr/bin/pg_dumpall$ver" /usr/bin/pg_dumpall; fi && \
    break; \
    fi; \
    done

# Fallback: if no versioned binaries, look for unversioned ones
RUN if [ ! -f /usr/bin/pg_dump ]; then \
    find /usr -name "pg_dump*" -type f -exec ln -sf {} /usr/bin/pg_dump \; 2>/dev/null | head -1; \
    find /usr -name "pg_restore*" -type f -exec ln -sf {} /usr/bin/pg_restore \; 2>/dev/null | head -1; \
    find /usr -name "psql*" -type f -exec ln -sf {} /usr/bin/psql \; 2>/dev/null | head -1; \
    find /usr -name "pg_isready*" -type f -exec ln -sf {} /usr/bin/pg_isready \; 2>/dev/null | head -1; \
    find /usr -name "pg_dumpall*" -type f -exec ln -sf {} /usr/bin/pg_dumpall \; 2>/dev/null | head -1; \
    fi

# Verify symlinks work
RUN ls -la /usr/bin/pg_dump /usr/bin/pg_restore /usr/bin/psql /usr/bin/pg_isready /usr/bin/pg_dumpall && \
    /usr/bin/pg_dump --version || echo "pg_dump not working" && \
    /usr/bin/pg_dumpall --version || echo "pg_dumpall not working" && \
    /usr/bin/psql --version || echo "psql not working"

# Environment variables with defaults
ENV POSTGRES_DATABASE **None**
ENV POSTGRES_HOST **None**
ENV POSTGRES_PORT 5432
ENV POSTGRES_USER **None**
ENV POSTGRES_PASSWORD **None**
ENV S3_ACCESS_KEY_ID **None**
ENV S3_SECRET_ACCESS_KEY **None**
ENV S3_BUCKET **None**
ENV S3_REGION us-west-1
ENV S3_PREFIX 'backup'
ENV S3_ENDPOINT **None**
ENV DROP_PUBLIC 'no'
ENV BACKUP_FILE 'latest'

# Create working directory
WORKDIR /restore

# Copy scripts
COPY restore/scripts/ ./scripts/
RUN chmod +x ./scripts/*.sh

CMD ["./scripts/restore.sh"]
