#!/bin/sh
set -e
set -o pipefail

echo "Starting PostgreSQL restore from S3..."

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

# Determine which backup to restore
if [ "${BACKUP_FILE}" = "latest" ]; then
    echo "Finding latest backup..."
    
    # Try daily backups first
    LATEST_BACKUP=$(aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/daily/" | sort | tail -n 1 | awk '{print $4}')
    
    if [ -z "${LATEST_BACKUP}" ]; then
        echo "No backups found in daily folder, checking weekly..."
        LATEST_BACKUP=$(aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/weekly/" | sort | tail -n 1 | awk '{print $4}')
        S3_FOLDER="weekly"
    else
        S3_FOLDER="daily"
    fi
    
    if [ -z "${LATEST_BACKUP}" ]; then
        echo "No backups found in weekly folder, checking monthly..."
        LATEST_BACKUP=$(aws ${AWS_ARGS} s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/monthly/" | sort | tail -n 1 | awk '{print $4}')
        S3_FOLDER="monthly"
    fi
    
    if [ -z "${LATEST_BACKUP}" ]; then
        echo "Error: No backups found in any folder"
        exit 1
    fi
    
    echo "Latest backup found: ${LATEST_BACKUP} in ${S3_FOLDER} folder"
else
    # Use specified backup file
    LATEST_BACKUP="${BACKUP_FILE}"
    S3_FOLDER="daily"  # Default to daily, but will try other folders if not found
    echo "Using specified backup: ${LATEST_BACKUP}"
fi

# Download backup from S3
echo "Downloading backup from S3..."
DOWNLOAD_SUCCESS=false

for folder in daily weekly monthly; do
    if aws ${AWS_ARGS} s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${folder}/${LATEST_BACKUP}" "/tmp/${LATEST_BACKUP}" 2>/dev/null; then
        echo "✓ Downloaded from ${folder} folder"
        DOWNLOAD_SUCCESS=true
        break
    fi
done

if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
    echo "Error: Could not download backup file ${LATEST_BACKUP}"
    exit 1
fi

# Verify download
if [ ! -f "/tmp/${LATEST_BACKUP}" ] || [ ! -s "/tmp/${LATEST_BACKUP}" ]; then
    echo "Error: Downloaded backup file is missing or empty"
    exit 1
fi

BACKUP_SIZE=$(du -h "/tmp/${LATEST_BACKUP}" | cut -f1)
echo "✓ Backup downloaded: ${BACKUP_SIZE}"

# Decompress backup
echo "Decompressing backup..."
gunzip "/tmp/${LATEST_BACKUP}"
DECOMPRESSED_FILE="/tmp/$(basename "${LATEST_BACKUP}" .gz)"

if [ ! -f "${DECOMPRESSED_FILE}" ]; then
    echo "Error: Decompression failed"
    exit 1
fi

echo "✓ Backup decompressed"

# Detect if this is a cluster (pg_dumpall) dump
IS_CLUSTER_DUMP=false
if head -n 5 "${DECOMPRESSED_FILE}" | grep -qi "database cluster dump"; then
    IS_CLUSTER_DUMP=true
fi

# Test database connection
echo "Testing database connection..."
if ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}"; then
    echo "Error: Cannot connect to database"
    exit 1
fi

echo "✓ Database connection successful"

if [ "${IS_CLUSTER_DUMP}" = true ]; then
    echo "Detected cluster dump. Restoring roles, databases, and data..."
    # For cluster dumps, ignore DROP_PUBLIC and feed the entire script to psql.
    # Connect to the bootstrap database (default: postgres) and let pg_dumpall manage CREATE DATABASE and \connect.
    psql ${POSTGRES_HOST_OPTS} -d "${POSTGRES_DATABASE}" -v ON_ERROR_STOP=1 -f "${DECOMPRESSED_FILE}"
else
    # Drop public schema if requested
    if [ "${DROP_PUBLIC}" = "yes" ]; then
        echo "Dropping and recreating public schema..."
        psql ${POSTGRES_HOST_OPTS} -d "${POSTGRES_DATABASE}" -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;" || {
            echo "Warning: Could not drop/recreate public schema"
        }
        echo "✓ Public schema recreated"
    fi

    # Restore single database
    echo "Restoring database from backup..."
    psql ${POSTGRES_HOST_OPTS} -d "${POSTGRES_DATABASE}" -v ON_ERROR_STOP=1 -f "${DECOMPRESSED_FILE}"
fi

echo "✓ Database restore completed"

# Cleanup downloaded files
rm -f "/tmp/${LATEST_BACKUP}" "${DECOMPRESSED_FILE}"
echo "✓ Cleanup completed"

if [ "${IS_CLUSTER_DUMP}" = true ]; then
    echo "Verifying restore (cluster): counting non-template databases..."
    DB_COUNT=$(psql ${POSTGRES_HOST_OPTS} -d postgres -t -c "SELECT count(*) FROM pg_database WHERE datistemplate=false;" | xargs)
    echo "Databases present: ${DB_COUNT}"
else
    # Verify restore
    echo "Verifying restore..."
    TABLE_COUNT=$(psql ${POSTGRES_HOST_OPTS} -d "${POSTGRES_DATABASE}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
    echo "Tables restored: ${TABLE_COUNT}"
fi

echo "$(date): Restore completed successfully"
