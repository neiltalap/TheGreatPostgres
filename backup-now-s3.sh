#!/bin/bash
# Simple PostgreSQL backup to S3 - Host connection version
set -e

# Source environment
source .env

# Configuration
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/backup_${DATE}.dump"
SQL_FILE="/tmp/backup_${DATE}.sql"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-1825}

echo "Starting PostgreSQL backup to S3..."
echo "Date: $(date)"
echo "Database: $POSTGRES_DB"

# Check PostgreSQL is running
if ! docker compose ps postgres | grep -q "Up"; then
    echo "Error: PostgreSQL not running!"
    exit 1
fi

# Create backups by connecting from host to container
echo "Creating PostgreSQL backups..."

# Export password for pg_dump
export PGPASSWORD="$POSTGRES_PASSWORD"

# Get the private IP from environment or use default
POSTGRES_HOST="${SERVER_PRIVATE_IP:-10.0.0.2}"

# Custom format backup
pg_dump -h "$POSTGRES_HOST" -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --format=custom --compress=9 > "$BACKUP_FILE"

# SQL format backup  
pg_dump -h "$POSTGRES_HOST" -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$SQL_FILE"

echo "✓ Backup files created:"
echo "  Custom: $(du -h $BACKUP_FILE | cut -f1)"
echo "  SQL: $(du -h $SQL_FILE | cut -f1)"

# Upload to S3
echo "Uploading to S3..."
aws s3 cp "$BACKUP_FILE" "s3://$HETZNER_S3_BUCKET/daily/" --endpoint-url "$HETZNER_S3_ENDPOINT"
aws s3 cp "$SQL_FILE" "s3://$HETZNER_S3_BUCKET/daily/" --endpoint-url "$HETZNER_S3_ENDPOINT"
echo "✓ Uploaded to S3"

# Weekly backup (Sunday)
if [ $(date +%u) -eq 7 ]; then
    aws s3 cp "$BACKUP_FILE" "s3://$HETZNER_S3_BUCKET/weekly/" --endpoint-url "$HETZNER_S3_ENDPOINT"
    echo "✓ Weekly backup created"
fi

# Monthly backup (1st of month)
if [ $(date +%d) -eq 01 ]; then
    aws s3 cp "$BACKUP_FILE" "s3://$HETZNER_S3_BUCKET/monthly/" --endpoint-url "$HETZNER_S3_ENDPOINT"
    echo "✓ Monthly backup created"
fi

# Cleanup old backups
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d)
aws s3 ls "s3://$HETZNER_S3_BUCKET/daily/" --endpoint-url "$HETZNER_S3_ENDPOINT" | while read -r line; do
    BACKUP_DATE=$(echo "$line" | awk '{print $4}' | grep -oE '[0-9]{8}' | head -1)
    if [ -n "$BACKUP_DATE" ] && [ "$BACKUP_DATE" -lt "$CUTOFF_DATE" ]; then
        BACKUP_KEY=$(echo "$line" | awk '{print $4}')
        aws s3 rm "s3://$HETZNER_S3_BUCKET/daily/$BACKUP_KEY" --endpoint-url "$HETZNER_S3_ENDPOINT"
        echo "Deleted old backup: $BACKUP_KEY"
    fi
done

# Cleanup local files
rm -f "$BACKUP_FILE" "$SQL_FILE"

echo "✓ Backup completed successfully"
echo "$(date): Backup completed" >> /var/log/postgres-s3-backup.log
