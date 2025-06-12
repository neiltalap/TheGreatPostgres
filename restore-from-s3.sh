#!/bin/bash

# Simple PostgreSQL restore from S3
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source environment
source .env

# Check arguments
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <backup_filename> [backup_type]${NC}"
    echo ""
    echo "Available backups:"
    echo ""
    echo -e "${BLUE}Daily:${NC}"
    aws s3 ls "s3://$HETZNER_S3_BUCKET/daily/" --endpoint-url "$HETZNER_S3_ENDPOINT" | grep backup_ | tail -10
    echo ""
    echo -e "${BLUE}Weekly:${NC}"
    aws s3 ls "s3://$HETZNER_S3_BUCKET/weekly/" --endpoint-url "$HETZNER_S3_ENDPOINT" | grep backup_ | tail -5
    echo ""
    echo -e "${BLUE}Monthly:${NC}"
    aws s3 ls "s3://$HETZNER_S3_BUCKET/monthly/" --endpoint-url "$HETZNER_S3_ENDPOINT" | grep backup_ | tail -5
    echo ""
    echo "Examples:"
    echo "  $0 backup_20250612_020000.dump"
    echo "  $0 backup_20250612_020000.sql weekly"
    exit 1
fi

BACKUP_FILE="$1"
BACKUP_TYPE="${2:-daily}"
LOCAL_FILE="/tmp/$BACKUP_FILE"

echo -e "${YELLOW}Restore configuration:${NC}"
echo "File: $BACKUP_FILE"
echo "Type: $BACKUP_TYPE"
echo "Database: $POSTGRES_DB"
echo ""

# Confirmation
echo -e "${RED}WARNING: This will overwrite the current database!${NC}"
read -p "Type 'yes' to confirm: " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Check PostgreSQL is running
if ! docker-compose ps postgres | grep -q "Up"; then
    echo -e "${RED}Error: PostgreSQL not running!${NC}"
    exit 1
fi

# Download from S3
echo -e "${YELLOW}Downloading from S3...${NC}"
aws s3 cp "s3://$HETZNER_S3_BUCKET/$BACKUP_TYPE/$BACKUP_FILE" "$LOCAL_FILE" --endpoint-url "$HETZNER_S3_ENDPOINT"

if [ ! -f "$LOCAL_FILE" ]; then
    echo -e "${RED}Download failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Downloaded: $(du -h $LOCAL_FILE | cut -f1)${NC}"

# Restore based on file type
echo -e "${YELLOW}Restoring...${NC}"

if [[ "$BACKUP_FILE" == *.dump ]]; then
    # Custom format restore
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();" || true
    
    docker-compose exec -T postgres pg_restore \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges < "$LOCAL_FILE"

elif [[ "$BACKUP_FILE" == *.sql ]]; then
    # SQL format restore
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB;" || true
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB;"
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$LOCAL_FILE"

else
    echo -e "${RED}Unsupported file format!${NC}"
    rm -f "$LOCAL_FILE"
    exit 1
fi

# Cleanup
rm -f "$LOCAL_FILE"

echo -e "${GREEN}✓ Restore completed!${NC}"

# Verify
TABLES=$(docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" 2>/dev/null | grep -c "public" || echo "0")
echo "Tables found: $TABLES"

echo ""
echo -e "${BLUE}Connect:${NC}"
echo "docker-compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB"
