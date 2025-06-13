#!/bin/sh
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
POSTGRES_HOST_OPTS="-h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER}"

# S3 configuration
if [ "${S3_ENDPOINT}" != "**None**" ] && [ -n "${S3_ENDPOINT}" ]; then
    AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
else
    AWS_ARGS=""
fi

# Generate backup filename with timestamp
BACKUP_DATE=$(date +"%Y-%m-%dT%H:%M:%SZ")
BACKUP_FILE="${POSTGRES_DATABASE}_${BACKUP_DATE}.sql"
COMPRESSED_FILE="${BACKUP_FILE}.gz"

# Determine backup type based on date
DAY_OF_WEEK=$(date +%u)  # 1=Monday, 7=Sunday
DAY_OF_MONTH=$(date +%d)

if [ "${MONTHLY_BACKUP}" = "yes" ] && [ "${DAY_OF_MONTH}" = "01" ]; then
    BACKUP_TYPE="monthly"
    echo "Creating monthly backup..."
elif [ "${WEEKLY_BACKUP}" = "yes" ] && [ "${DAY_OF_WEEK}" = "7" ]; then
    BACKUP_TYPE="weekly"
    echo "Creating weekly backup..."
else
    BACKUP_TYPE="daily"
    echo "Creating daily backup..."
fi

# Create backup directory
mkdir -p /tmp/backup

# Test database connection
echo "Testing database connection..."
if ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}"; then
    echo "Error: Cannot connect to database"
    exit 1
fi

echo "✓ Database connection successful"

# Create database backup
echo "Creating database dump..."
pg_dump ${POSTGRES_HOST_OPTS} \
    -d "${POSTGRES_DATABASE}" \
    ${POSTGRES_EXTRA_OPTS} \
    --verbose \
    --no-owner \
    --no-privileges \
    > "/tmp/backup/${BACKUP_FILE}"

if [ ! -f "/tmp/backup/${BACKUP_FILE}" ] || [ ! -s "/tmp/backup/${BACKUP_FILE}" ]; then
    echo "Error: Backup file creation failed or file is empty"
    exit 1
fi

echo "✓ Database dump created"

# Compress backup
echo "Compressing backup..."
gzip "/tmp/backup/${BACKUP_FILE}"

if [ ! -f "/tmp/backup/${COMPRESSED_FILE}" ]; then
    echo "Error: Backup compression failed"
    exit 1
fi

BACKUP_SIZE=$(du -h "/tmp/backup/${COMPRESSED_FILE}" | cut -f1)
echo "✓ Backup compressed: ${BACKUP_SIZE}"

# Upload to S3
echo "Uploading backup to S3..."
aws ${AWS_ARGS} s3 cp "/tmp/backup/${COMPRESSED_FILE}" "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_TYPE}/${COMPRESSED_FILE}"

# Verify upload
if aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_TYPE}/${COMPRESSED_FILE}" >/dev/null 2>&1; then
    echo "✓ Backup uploaded successfully to ${BACKUP_TYPE} folder"
else
    echo "Error: Backup upload verification failed"
    exit 1
fi

# Cleanup local backup
rm -f "/tmp/backup/${COMPRESSED_FILE}"
echo "✓ Local backup cleaned up"

# Cleanup old backups based on retention policy
if [ "${BACKUP_RETENTION_DAYS}" -gt 0 ]; then
    echo "Cleaning up old ${BACKUP_TYPE} backups older than ${BACKUP_RETENTION_DAYS} days..."
    
    # Calculate cutoff date
    if command -v date >/dev/null 2>&1; then
        # Try GNU date first (Linux)
        CUTOFF_DATE=$(date -d "${BACKUP_RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null) || \
        # Fall back to BSD date (Alpine)
        CUTOFF_DATE=$(date -v-${BACKUP_RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null) || \
        # Skip cleanup if date calculation fails
        CUTOFF_DATE=""
    fi
    
    if [ -n "${CUTOFF_DATE}" ]; then
        # List and delete old backups
        aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_TYPE}/" | \
        while read -r line; do
            backup_date=$(echo "$line" | awk '{print $1}')
            backup_filename=$(echo "$line" | awk '{print $4}')
            
            if [ -n "$backup_filename" ] && [ "$backup_date" \< "$CUTOFF_DATE" ]; then
                echo "Deleting old backup: $backup_filename"
                aws ${AWS_ARGS} s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_TYPE}/$backup_filename"
            fi
        done
        echo "✓ Old backup cleanup completed"
    else
        echo "Warning: Could not calculate cutoff date for cleanup"
    fi
fi

echo "$(date): Backup completed successfully"
echo "Backup details:"
echo "  Type: ${BACKUP_TYPE}"
echo "  File: ${COMPRESSED_FILE}"
echo "  Size: ${BACKUP_SIZE}"
echo "  Location: s3://${S3_BUCKET}/${S3_PREFIX}/${BACKUP_TYPE}/${COMPRESSED_FILE}"