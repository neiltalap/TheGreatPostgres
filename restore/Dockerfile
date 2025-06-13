FROM alpine:3.19

# Install required packages
RUN apk update && \
    apk add --no-cache \
    postgresql-client \
    python3 \
    py3-pip \
    gzip \
    coreutils \
    openssl && \
    pip3 install --break-system-packages awscli && \
    rm -rf /var/cache/apk/*

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