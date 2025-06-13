#!/bin/sh
# backup/scripts/run.sh
set -e

echo "Starting PostgreSQL Backup Service..."
echo "Configuration:"
echo "  Database: ${POSTGRES_DATABASE}"
echo "  Host: ${POSTGRES_HOST}:${POSTGRES_PORT}"
echo "  S3 Bucket: ${S3_BUCKET}"
echo "  Schedule: ${SCHEDULE}"
echo "  Retention: ${BACKUP_RETENTION_DAYS} days"

# Configure AWS CLI
if [ "${S3_ACCESS_KEY_ID}" != "**None**" ]; then
    aws configure set aws_access_key_id "${S3_ACCESS_KEY_ID}"
    aws configure set aws_secret_access_key "${S3_SECRET_ACCESS_KEY}"
    aws configure set default.region "${S3_REGION}"
fi

# Test database connection
echo "Testing database connection..."
export PGPASSWORD="${POSTGRES_PASSWORD}"
if pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}"; then
    echo "✓ Database connection successful"
else
    echo "✗ Database connection failed"
    exit 1
fi

# Test S3 connection
echo "Testing S3 connection..."
if [ "${S3_ENDPOINT}" != "**None**" ]; then
    AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
else
    AWS_ARGS=""
fi

if aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
    echo "✓ S3 connection successful"
else
    echo "✗ S3 connection failed"
    exit 1
fi

# Create S3 folder structure
echo "Setting up S3 folder structure..."
aws ${AWS_ARGS} s3api put-object --bucket "${S3_BUCKET}" --key "${S3_PREFIX}/daily/" >/dev/null 2>&1 || true
aws ${AWS_ARGS} s3api put-object --bucket "${S3_BUCKET}" --key "${S3_PREFIX}/weekly/" >/dev/null 2>&1 || true
aws ${AWS_ARGS} s3api put-object --bucket "${S3_BUCKET}" --key "${S3_PREFIX}/monthly/" >/dev/null 2>&1 || true

# Check if we should run immediately or on schedule
if [ "${SCHEDULE}" = "**None**" ] || [ -z "${SCHEDULE}" ]; then
    echo "Running immediate backup..."
    ./scripts/backup.sh
else
    echo "Starting scheduled backup service..."
    # Update cron with custom schedule
    echo "${SCHEDULE} /backup/scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root
    
    # Start cron daemon
    crond -f -l 2
fi