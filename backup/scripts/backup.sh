#!/bin/sh
# backup/scripts/backup.sh
set -e
set -o pipefail

echo "$(date): Starting PostgreSQL backup..."

# Validate environment variables
for var in S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_BUCKET POSTGRES_DATABASE POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD; do
    eval value=\$${var}
    if [ "${value}" = "**None**" ] || [ -z "${value}" ]; then
        echo "Error: ${var} environment variable is required"
        exit 1
    fi
done

# Setup AWS environment
export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="${S3_REGION}"

# Setup PostgreSQL environment
export PGPASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_HOST_OPTS="-h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER} ${POSTGRES_EXTRA_OPTS}"

# S3 configuration
if [ "${S3_ENDPOINT}" != "**None**" ] && [ -n "${S3_ENDPOINT}" ]; then
    AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
else
    AWS_ARGS=""
fi

# Generate backup filename with timestamp
TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%SZ")
BACKUP_FILENAME="${POSTGRES_DATABASE}_${TIMESTAMP}.sql.gz"

echo "Creating dump of ${POSTGRES_DATABASE} database from ${POSTGRES_HOST}..."

# Create compressed backup
pg_dump ${POSTGRES_HOST_OPTS} "${POSTGRES_DATABASE}" | gzip > "/tmp/${BACKUP_FILENAME}"

# Check if backup was created successfully
if [ ! -f "/tmp/${BACKUP_FILENAME}" ] || [ ! -s "/tmp/${BACKUP_FILENAME}" ]; then
    echo "Error: Backup file was not created or is empty"
    exit 1
fi

BACKUP_SIZE=$(du -h "/tmp/${BACKUP_FILENAME}" | cut -f1)
echo "✓ Backup created: ${BACKUP_SIZE}"

# Upload to S3 daily folder
echo "Uploading backup to S3..."
aws ${AWS_ARGS} s3 cp "/tmp/${BACKUP_FILENAME}" "s3://${S3_BUCKET}/${S3_PREFIX}/daily/${BACKUP_FILENAME}"
echo "✓ Daily backup uploaded to S3"

# Weekly backup (Sunday)
if [ "${WEEKLY_BACKUP}" = "yes" ] && [ "$(date +%u)" = "7" ]; then
    aws ${AWS_ARGS} s3 cp "/tmp/${BACKUP_FILENAME}" "s3://${S3_BUCKET}/${S3_PREFIX}/weekly/${BACKUP_FILENAME}"
    echo "✓ Weekly backup created"
fi

# Monthly backup (1st of month)
if [ "${MONTHLY_BACKUP}" = "yes" ] && [ "$(date +%d)" = "01" ]; then
    aws ${AWS_ARGS} s3 cp "/tmp/${BACKUP_FILENAME}" "s3://${S3_BUCKET}/${S3_PREFIX}/monthly/${BACKUP_FILENAME}"
    echo "✓ Monthly backup created"
fi

# Cleanup old daily backups
echo "Cleaning up old backups (retention: ${BACKUP_RETENTION_DAYS} days)..."
CUTOFF_DATE=$(date -d "${BACKUP_RETENTION_DAYS} days ago" +%Y-%m-%d || date -v-${BACKUP_RETENTION_DAYS}d +%Y-%m-%d)

# List and delete old backups
aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/daily/" | while read -r line; do
    BACKUP_DATE=$(echo "${line}" | awk '{print $1}')
    if [ -n "${BACKUP_DATE}" ] && [ "${BACKUP_DATE}" \< "${CUTOFF_DATE}" ]; then
        BACKUP_KEY=$(echo "${line}" | awk '{print $4}')
        if [ -n "${BACKUP_KEY}" ]; then
            aws ${AWS_ARGS} s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/daily/${BACKUP_KEY}"
            echo "Deleted old backup: ${BACKUP_KEY}"
        fi
    fi
done

# Cleanup local backup file
rm -f "/tmp/${BACKUP_FILENAME}"

echo "$(date): Backup completed successfully"