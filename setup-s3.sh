#!/bin/bash

# Simple S3 Setup for PostgreSQL Backups
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Setting up Hetzner S3 for PostgreSQL Backups${NC}"
echo "============================================="

# Check .env file
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Create .env with your S3 credentials first."
    exit 1
fi

# Source environment variables
source .env

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

# Install AWS CLI if needed
if ! command -v aws &> /dev/null; then
    echo -e "${YELLOW}Installing AWS CLI...${NC}"
    sudo apt-get update
    sudo apt-get install -y awscli
fi

# Configure AWS CLI
echo -e "${YELLOW}Configuring AWS CLI...${NC}"
aws configure set aws_access_key_id "$HETZNER_S3_ACCESS_KEY"
aws configure set aws_secret_access_key "$HETZNER_S3_SECRET_KEY"
aws configure set default.region "$HETZNER_S3_REGION"

# Test S3 connection
echo -e "${YELLOW}Testing S3 connection...${NC}"
if aws s3 ls "s3://$HETZNER_S3_BUCKET" --endpoint-url "$HETZNER_S3_ENDPOINT" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ S3 connection successful${NC}"
else
    echo -e "${RED}✗ S3 connection failed${NC}"
    echo "Check your credentials and bucket name."
    echo ""
    echo "Create bucket if needed:"
    echo "aws s3 mb s3://$HETZNER_S3_BUCKET --endpoint-url $HETZNER_S3_ENDPOINT"
    exit 1
fi

# Create S3 folder structure
echo -e "${YELLOW}Creating S3 folder structure...${NC}"
aws s3api put-object --bucket "$HETZNER_S3_BUCKET" --key "daily/" --endpoint-url "$HETZNER_S3_ENDPOINT" >/dev/null 2>&1 || true
aws s3api put-object --bucket "$HETZNER_S3_BUCKET" --key "weekly/" --endpoint-url "$HETZNER_S3_ENDPOINT" >/dev/null 2>&1 || true
aws s3api put-object --bucket "$HETZNER_S3_BUCKET" --key "monthly/" --endpoint-url "$HETZNER_S3_ENDPOINT" >/dev/null 2>&1 || true

echo -e "${GREEN}✓ S3 folder structure created${NC}"

# Setup daily backup cron job
CRON_JOB="0 2 * * * cd $(pwd) && ./backup-now-s3.sh >> /var/log/postgres-s3-backup.log 2>&1"
(crontab -l 2>/dev/null | grep -v backup-now-s3.sh; echo "$CRON_JOB") | crontab -

echo -e "${GREEN}✓ Daily backup cron job scheduled (2:00 AM)${NC}"

# Test backup if PostgreSQL is running
if docker-compose ps postgres | grep -q "Up"; then
    echo -e "${YELLOW}Testing backup...${NC}"
    ./backup-now-s3.sh
    echo -e "${GREEN}✓ Test backup completed${NC}"
else
    echo -e "${YELLOW}PostgreSQL not running. Start with: docker-compose up -d${NC}"
fi

echo ""
echo -e "${GREEN}S3 setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}Commands:${NC}"
echo "Create backup:  ./backup-now-s3.sh"
echo "List backups:   aws s3 ls s3://$HETZNER_S3_BUCKET/daily/ --endpoint-url $HETZNER_S3_ENDPOINT"
echo "Restore:        ./restore-from-s3.sh backup_YYYYMMDD_HHMMSS.dump"
echo "View logs:      tail -f /var/log/postgres-s3-backup.log"
