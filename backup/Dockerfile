FROM alpine:3.19

# Install required packages
RUN apk update && \
    apk add --no-cache \
    postgresql-client \
    python3 py3-pip \
    curl \
    gzip \
    coreutils \
    dcron \
    openssl && \
    pip3 install --upgrade pip && \
    pip3 install awscli && \
    rm -rf /var/cache/apk/*

# Environment variables with defaults
ENV POSTGRES_DATABASE **None**
ENV POSTGRES_HOST **None**
ENV POSTGRES_PORT 5432
ENV POSTGRES_USER **None**
ENV POSTGRES_PASSWORD **None**
ENV POSTGRES_EXTRA_OPTS ''
ENV S3_ACCESS_KEY_ID **None**
ENV S3_SECRET_ACCESS_KEY **None**
ENV S3_BUCKET **None**
ENV S3_REGION us-west-1
ENV S3_PREFIX 'backup'
ENV S3_ENDPOINT **None**
ENV SCHEDULE **None**
ENV BACKUP_RETENTION_DAYS 30
ENV WEEKLY_BACKUP 'no'
ENV MONTHLY_BACKUP 'no'

# Create working directory
WORKDIR /backup

# Copy scripts
COPY backup/scripts/ ./scripts/
RUN chmod +x ./scripts/*.sh

# Setup cron
RUN echo "0 2 * * * /backup/scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

# Create log directory
RUN mkdir -p /var/log && touch /var/log/backup.log

CMD ["./scripts/run.sh"]