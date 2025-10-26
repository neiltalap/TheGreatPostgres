#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source environment variables
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# S3 configuration
AWS_ARGS=""
if [ -n "${HETZNER_S3_ENDPOINT}" ]; then
    AWS_ARGS="--endpoint-url ${HETZNER_S3_ENDPOINT}"
fi

show_help() {
    echo -e "${BLUE}PostgreSQL Backup Management${NC}"
    echo "=============================="
    echo ""
    echo "Commands:"
    echo "  backup                    - Create immediate backup"
    echo "  list [daily|weekly|monthly] - List available backups"
    echo "  restore <filename>        - Restore from specific backup"
    echo "  restore-latest           - Restore from latest backup"
    echo "  start-backup-service     - Start automated backup service"
    echo "  stop-backup-service      - Stop automated backup service"
    echo "  logs                     - Show backup service logs"
    echo "  setup                    - Initial S3 setup and test"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 list daily"
    echo "  $0 restore myapp_2024-06-13T02:00:00Z.sql.gz"
    echo "  $0 restore-latest"
}

create_backup() {
    echo -e "${YELLOW}Creating immediate backup...${NC}"
    
    # Check if backup container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "postgres-backup"; then
        echo -e "${YELLOW}Backup service not running, starting it first...${NC}"
        docker compose --profile backup up -d postgres-backup
        
        # Wait for container to be ready
        echo -e "${YELLOW}Waiting for backup service to initialize...${NC}"
        sleep 10
        
        # Check if it's actually running
        if ! docker ps --format "table {{.Names}}" | grep -q "postgres-backup"; then
            echo -e "${RED}Failed to start backup service${NC}"
            exit 1
        fi
    fi
    
    # Execute backup script directly in the running container
    echo -e "${YELLOW}Running backup script in container...${NC}"
    docker exec postgres-backup /backup/scripts/backup.sh
    
    echo -e "${GREEN}✓ Backup completed${NC}"
}

list_backups() {
    local backup_type="${1:-daily}"
    
    echo -e "${BLUE}Available ${backup_type} backups:${NC}"
    echo ""
    
    aws ${AWS_ARGS} s3 ls "s3://${HETZNER_S3_BUCKET}/${S3_PREFIX:-backup}/${backup_type}/" | \
        grep "\.sql\.gz$" | \
        sort -r | \
        head -20 | \
        while read -r line; do
            date=$(echo "$line" | awk '{print $1" "$2}')
            size=$(echo "$line" | awk '{print $3}')
            filename=$(echo "$line" | awk '{print $4}')
            printf "%-20s %-10s %s\n" "$date" "$size" "$filename"
        done
}

restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo -e "${RED}Error: Backup filename required${NC}"
        echo "Usage: $0 restore <filename>"
        return 1
    fi
    
    echo -e "${YELLOW}Restoring from backup: ${backup_file}${NC}"
    echo -e "${RED}WARNING: This will overwrite the current database!${NC}"
    read -p "Type 'yes' to confirm: " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        return 0
    fi
    
    RESTORE_BACKUP_FILE="$backup_file" docker compose run --rm postgres-restore
    
    echo -e "${GREEN}✓ Restore completed${NC}"
}

restore_latest() {
    echo -e "${YELLOW}Restoring from latest backup...${NC}"
    echo -e "${RED}WARNING: This will overwrite the current database!${NC}"
    read -p "Type 'yes' to confirm: " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        return 0
    fi
    
    RESTORE_BACKUP_FILE="latest" docker compose run --rm postgres-restore
    
    echo -e "${GREEN}✓ Restore completed${NC}"
}

start_backup_service() {
    echo -e "${YELLOW}Starting automated backup service...${NC}"
    
    docker compose --profile backup up -d postgres-backup
    
    echo -e "${GREEN}✓ Backup service started${NC}"
    echo "The service will run scheduled backups at 2 AM daily"
    echo "View logs with: $0 logs"
}

stop_backup_service() {
    echo -e "${YELLOW}Stopping backup service...${NC}"
    
    docker compose stop postgres-backup
    docker compose rm -f postgres-backup
    
    echo -e "${GREEN}✓ Backup service stopped${NC}"
}

show_logs() {
    echo -e "${BLUE}Backup service logs:${NC}"
    if docker ps --format "table {{.Names}}" | grep -q "postgres-backup"; then
        docker compose logs -f postgres-backup
    else
        echo -e "${YELLOW}Backup service is not running${NC}"
        echo "Start it with: $0 start-backup-service"
    fi
}

setup_s3() {
    echo -e "${BLUE}Setting up S3 for PostgreSQL backups...${NC}"
    
    # Validate S3 configuration
    if [ -z "$HETZNER_S3_ACCESS_KEY" ] || [ -z "$HETZNER_S3_SECRET_KEY" ] || [ -z "$HETZNER_S3_BUCKET" ]; then
        echo -e "${RED}Error: Missing S3 configuration in .env file!${NC}"
        echo "Required variables:"
        echo "- HETZNER_S3_ACCESS_KEY"
        echo "- HETZNER_S3_SECRET_KEY"
        echo "- HETZNER_S3_BUCKET"
        echo "- HETZNER_S3_ENDPOINT"
        exit 1
    fi
    
    # Stop and remove existing backup services
    echo -e "${YELLOW}Stopping existing backup services...${NC}"
    docker compose stop postgres-backup postgres-restore 2>/dev/null || true
    docker compose rm -f postgres-backup postgres-restore 2>/dev/null || true
    
    # Force rebuild backup images
    echo -e "${YELLOW}Rebuilding backup and restore images...${NC}"
    docker compose build --no-cache --pull postgres-backup postgres-restore
    
    # Configure AWS CLI
    aws configure set aws_access_key_id "$HETZNER_S3_ACCESS_KEY"
    aws configure set aws_secret_access_key "$HETZNER_S3_SECRET_KEY"
    aws configure set default.region "${HETZNER_S3_REGION:-eu-central}"
    
    # Test S3 connection
    echo -e "${YELLOW}Testing S3 connection...${NC}"
    if aws ${AWS_ARGS} s3 ls "s3://${HETZNER_S3_BUCKET}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ S3 connection successful${NC}"
    else
        echo -e "${RED}✗ S3 connection failed${NC}"
        echo "Check your credentials and bucket name."
        echo ""
        echo "Create bucket if needed:"
        echo "aws s3 mb s3://${HETZNER_S3_BUCKET} ${AWS_ARGS}"
        exit 1
    fi
    
    # Create S3 folder structure
    echo -e "${YELLOW}Creating S3 folder structure...${NC}"
    aws ${AWS_ARGS} s3api put-object --bucket "$HETZNER_S3_BUCKET" --key "backup/daily/" >/dev/null 2>&1 || true
    aws ${AWS_ARGS} s3api put-object --bucket "$HETZNER_S3_BUCKET" --key "backup/weekly/" >/dev/null 2>&1 || true
    aws ${AWS_ARGS} s3api put-object --bucket "$HETZNER_S3_BUCKET" --key "backup/monthly/" >/dev/null 2>&1 || true
    
    echo -e "${GREEN}✓ S3 folder structure created${NC}"
    
    # Create the production_db database if it doesn't exist
    if docker compose ps postgres | grep -q "Up"; then
        # Start backup service and run a test backup if Postgres is up
        echo -e "${YELLOW}Starting backup service...${NC}"
        docker compose --profile backup up -d postgres-backup
        sleep 5

        echo -e "${YELLOW}Testing backup...${NC}"
        create_backup
        echo -e "${GREEN}✓ Test backup completed${NC}"
    else
        echo -e "${YELLOW}PostgreSQL not running. Start with: docker compose up -d${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}S3 setup completed successfully!${NC}"
}

# Main script logic
case "${1:-help}" in
    backup)
        create_backup
        ;;
    list)
        list_backups "$2"
        ;;
    restore)
        restore_backup "$2"
        ;;
    restore-latest)
        restore_latest
        ;;
    start-backup-service)
        start_backup_service
        ;;
    stop-backup-service)
        stop_backup_service
        ;;
    logs)
        show_logs
        ;;
    setup)
        setup_s3
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac