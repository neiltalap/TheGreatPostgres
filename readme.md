# PostgreSQL Backup System - Complete Guide

A comprehensive PostgreSQL backup solution with automated S3-compatible storage, Docker-based deployment, and flexible restore options.

## 🚀 Features

- **Automated Backups**: Daily backups at 2 AM UTC with weekly and monthly retention
- **S3-Compatible Storage**: Works with AWS S3, Hetzner, MinIO, Cloudflare R2, and other S3 providers
- **PostgreSQL 17 Compatible**: Matches your PostgreSQL 17.5 server version
- **Docker-Based**: Containerized backup and restore services
- **Flexible Scheduling**: Configurable backup schedules via cron
- **Retention Management**: Automatic cleanup of old backups
- **Compression**: Gzip compression to minimize storage costs
- **Easy Management**: Simple command-line interface

## ⚙️ Auto-Tuned PostgreSQL + Extensions

The container now auto-generates `postgresql.conf` and `pg_hba.conf` on startup based on container resources and environment variables. No need to hand-edit config files.

Additionally, the Postgres service uses the official TimescaleDB image (`timescale/timescaledb:latest-pg17`). On first initialization, the init scripts enable `timescaledb` and will also enable `vector` if the image includes pgvector.

- Detection: Reads cgroup limits to detect memory and CPU cores
- Tuning: Sets `shared_buffers`, `effective_cache_size`, `work_mem`, and parallel workers
- Access: Generates `pg_hba.conf` from your network CIDRs; denies all else

Environment overrides (optional):

```
# Resource hints (override auto-detection)
PG_MEMORY_MB=8192

# Connection limits
PG_MAX_CONNECTIONS=400
POSTGRES_MAX_CONNECTIONS=400

# Memory (choose either PG_* in MB or POSTGRES_* with units like 2GB)
PG_SHARED_BUFFERS_MB=2048
PG_EFFECTIVE_CACHE_MB=6144
PG_WORK_MEM_MB=10
PG_MAINTENANCE_WORK_MEM_MB=512
POSTGRES_SHARED_BUFFERS=2GB
POSTGRES_EFFECTIVE_CACHE_SIZE=6GB
POSTGRES_WORK_MEM=10MB
POSTGRES_MAINTENANCE_WORK_MEM=512MB

# SSL and password encryption
PG_SSL=off
POSTGRES_SSL=off
PG_PASSWORD_ENCRYPTION=scram-sha-256

# pg_hba.conf generation
POSTGRES_NETWORK_SUBNET=172.20.0.0/16   # compose bridge subnet
INCLUDE_DEFAULT_DOCKER_SUBNET=true      # also allow 172.17.0.0/16
DEFAULT_DOCKER_SUBNET=172.17.0.0/16
PG_HBA_METHOD=scram-sha-256
PG_HBA_HOST_CIDRS=10.0.0.0/8,192.168.0.0/16  # extra allowed ranges
```

Notes:

- The service runs with `command: ["bash", "/config/render-config.sh"]` and no longer mounts static `postgresql.conf`/`pg_hba.conf` files (these files were removed).
- To lock values precisely, set the `POSTGRES_*` variables with units (e.g., `2GB`).
- Otherwise, the script auto-tunes from memory/CPU limits and `PG_*` MB overrides.
- TimescaleDB is preloaded automatically if present; you can force preload by setting `PG_SHARED_PRELOAD_LIBRARIES`.
- Extensions are created via `init-scripts/10-extensions.sh` when the data directory is initialized. If you already have data, run the `CREATE EXTENSION` statements manually.
- If you require `pgvector` and your image doesn’t include it, switch back to a custom image that installs `postgresql-17-pgvector` or build from source (we previously supported this).

Example to create a hypertable after your app creates a table:

```
-- after creating a regular table with a timestamptz column "time"
SELECT timescaledb_pre_restore(); -- if converting existing table, optional
SELECT create_hypertable('metrics', by_range('time'), if_not_exists => TRUE);
```

## 📋 Prerequisites

- Docker and Docker Compose installed
- PostgreSQL database running
- S3-compatible storage account (AWS S3, Hetzner, MinIO, Cloudflare R2, etc.)
- AWS CLI installed on host machine
- Cloudflare account with a managed domain and a Cloudflare Tunnel token (required for secure pgAdmin access)

## 🔧 Initial Setup

### 1. Environment Configuration

Create a `.env` file with your database and S3 credentials:

```bash
# PostgreSQL Configuration
POSTGRES_DB=dbname
POSTGRES_USER=admin
POSTGRES_PASSWORD=password

# pgAdmin Configuration (access via Cloudflare Tunnel)
PGADMIN_EMAIL=email@email.com
PGADMIN_PASSWORD=password
PGADMIN_PORT=8080

# Server Information
SERVER_PRIVATE_IP=0.0.0.0
SERVER_PUBLIC_IP=0.0.0.0

# S3-Compatible Storage Configuration (AWS, Hetzner, MinIO, R2, ...)
# Note: Names use the "HETZNER_*" prefix but work with ANY S3-compatible provider.
# docker-compose maps these into the containers as generic S3_* variables.
#
# For AWS S3: leave HETZNER_S3_ENDPOINT empty and set HETZNER_S3_REGION accordingly.
# For other providers: set both region (if applicable) and endpoint URL.
HETZNER_S3_ACCESS_KEY=your-access-key
HETZNER_S3_SECRET_KEY=your-secret-key
HETZNER_S3_ENDPOINT=
HETZNER_S3_REGION=us-east-1
HETZNER_S3_BUCKET=my-backups-bucket

# Cloudflare Tunnel (required for pgAdmin access)
# Create a Tunnel in Cloudflare and copy the connector token here.
CLOUDFLARE_TUNNEL_TOKEN=your-cloudflare-tunnel-token

# Backup Configuration
BACKUP_RETENTION_DAYS=1825  # 5 years retention
BACKUP_SCHEDULE="0 2 * * *"  # Daily at 2 AM
```

Note: No performance tuning variables are required — the Postgres container auto‑tunes memory, parallelism, and connection limits based on available resources.

### 3. Cloudflare Tunnel Setup (pgAdmin)

pgAdmin is not exposed on host ports. Access is provided securely via Cloudflare Tunnel.

Steps:

1) In Cloudflare Dashboard → Zero Trust → Tunnels, create a new tunnel and choose the token/connector method.  
2) Copy the tunnel token into your `.env` as `CLOUDFLARE_TUNNEL_TOKEN` (see above).  
3) In the tunnel’s Public Hostnames, add a hostname (e.g., `pgadmin.yourdomain.com`) and set:  
   - Type: HTTP  
   - URL/Service: `http://pgadmin:80`  
   The `pgadmin` hostname is the Docker service name, resolvable inside the `cloudflared` container.
4) Optionally add an Access policy (SSO) for the hostname in Cloudflare.  
5) Start services: `docker compose up -d pgadmin cloudflare-tunnel` (or bring up the whole stack).  
6) Visit `https://pgadmin.yourdomain.com` and log in with `PGADMIN_EMAIL` / `PGADMIN_PASSWORD`.

Note: The Cloudflare Tunnel is for pgAdmin’s web UI only. Do not expose PostgreSQL (5432) over Cloudflare unless you use Cloudflare Spectrum (paid). Keep the database bound to private interfaces as configured in `docker-compose.yaml`.

### 2. One-Time Setup

Run the setup command to initialize everything:

```bash
./backup-manager.sh setup
```

This command will:

- ✅ Validate S3 credentials and connectivity
- ✅ Rebuild Docker images with latest PostgreSQL client
- ✅ Create S3 folder structure (`daily/`, `weekly/`, `monthly/`)
- ✅ Ensure the target database exists
- ✅ Start the automated backup service
- ✅ Run a test backup to verify everything works

## 📚 Command Reference

### `./backup-manager.sh backup`

**Purpose**: Create an immediate backup of your database

**What it does**:

- Connects to your PostgreSQL database
- Creates a compressed SQL dump using `pg_dump`
- Uploads the backup to S3 in the `daily/` folder
- Verifies the upload was successful
- Cleans up local temporary files

**Example**:

```bash
./backup-manager.sh backup
```

**Output**:

```
Creating immediate backup...
Running backup script in container...
Fri Jun 13 08:43:16 UTC 2025: Starting PostgreSQL backup...
Creating daily backup...
✓ Database connection successful
✓ Database dump created
✓ Backup compressed: 4.2MB
✓ Backup uploaded successfully to daily folder
✓ Local backup cleaned up
Backup completed successfully
```

---

### `./backup-manager.sh list [daily|weekly|monthly]`

**Purpose**: List available backups in S3 storage

**Parameters**:

- `daily` (default): Show daily backups
- `weekly`: Show weekly backups  
- `monthly`: Show monthly backups

**What it does**:

- Connects to your S3 bucket
- Lists the 20 most recent backup files
- Shows file date, size, and filename
- Sorts by date (newest first)

**Examples**:

```bash
# List daily backups (default)
./backup-manager.sh list

# List daily backups explicitly
./backup-manager.sh list daily

# List weekly backups
./backup-manager.sh list weekly

# List monthly backups  
./backup-manager.sh list monthly
```

**Output**:

```
Available daily backups:

2025-06-13 08:43:16  4.2MB      production_db_2025-06-13T08:43:16Z.sql.gz
2025-06-12 02:00:15  4.1MB      production_db_2025-06-12T02:00:15Z.sql.gz
2025-06-11 02:00:12  3.9MB      production_db_2025-06-11T02:00:12Z.sql.gz
```

---

### `./backup-manager.sh restore <filename>`

**Purpose**: Restore database from a specific backup file

**Parameters**:

- `<filename>`: Exact name of the backup file (e.g., `production_db_2025-06-13T08:43:16Z.sql.gz`)

**What it does**:

- Prompts for confirmation (destructive operation)
- Downloads the specified backup from S3
- Decompresses the backup file
- Optionally drops and recreates the public schema
- Restores the database using `psql`
- Verifies the restore was successful
- Cleans up downloaded files

**Example**:

```bash
./backup-manager.sh restore production_db_2025-06-13T08:43:16Z.sql.gz
```

**Interactive flow**:

```
Restoring from backup: production_db_2025-06-13T08:43:16Z.sql.gz
WARNING: This will overwrite the current database!
Type 'yes' to confirm: yes
✓ Downloaded from daily folder
✓ Backup downloaded: 4.2MB
✓ Backup decompressed
✓ Database connection successful
✓ Public schema recreated
✓ Database restore completed
Tables restored: 15
```

---

### `./backup-manager.sh restore-latest`

**Purpose**: Restore database from the most recent backup

**What it does**:

- Automatically finds the latest backup across all folders
- Searches in order: daily → weekly → monthly
- Prompts for confirmation
- Performs the same restore process as specific file restore

**Example**:

```bash
./backup-manager.sh restore-latest
```

**Interactive flow**:

```
Restoring from latest backup...
WARNING: This will overwrite the current database!
Type 'yes' to confirm: yes
Finding latest backup...
Latest backup found: production_db_2025-06-13T08:43:16Z.sql.gz in daily folder
✓ Downloaded from daily folder
✓ Backup downloaded: 4.2MB
[... rest of restore process ...]
```

---

### `./backup-manager.sh start-backup-service`

**Purpose**: Start the automated backup service

**What it does**:

- Starts a Docker container with cron daemon
- Schedules daily backups at 2 AM UTC
- Runs continuously in the background
- Automatically creates weekly backups on Sundays
- Automatically creates monthly backups on the 1st of each month

**Example**:

```bash
./backup-manager.sh start-backup-service
```

**Output**:

```
Starting automated backup service...
✓ Backup service started
The service will run scheduled backups at 2 AM daily
View logs with: ./backup-manager.sh logs
```

**Schedule details**:

- **Daily**: Every day at 2:00 AM UTC
- **Weekly**: Sundays at 2:00 AM UTC (if `WEEKLY_BACKUP=yes`)
- **Monthly**: 1st of month at 2:00 AM UTC (if `MONTHLY_BACKUP=yes`)

---

### `./backup-manager.sh stop-backup-service`

**Purpose**: Stop the automated backup service

**What it does**:

- Stops the backup Docker container
- Removes the container completely
- Stops all scheduled backups
- Manual backups will still work

**Example**:

```bash
./backup-manager.sh stop-backup-service
```

**Output**:

```
Stopping backup service...
✓ Backup service stopped
```

---

### `./backup-manager.sh logs`

**Purpose**: View real-time logs from the backup service

**What it does**:

- Shows current backup service logs
- Follows log output in real-time (Ctrl+C to exit)
- Useful for monitoring backup execution
- Shows any errors or issues

**Example**:

```bash
./backup-manager.sh logs
```

**Output**:

```
Backup service logs:
postgres-backup  | Starting PostgreSQL Backup Service...
postgres-backup  | Configuration:
postgres-backup  |   Database: production_db
postgres-backup  |   Host: postgres:5432
postgres-backup  |   S3 Bucket: your-bucket
postgres-backup  |   Schedule: 0 2 * * *
postgres-backup  |   Retention: 1825 days
postgres-backup  | ✓ Database connection successful
postgres-backup  | ✓ S3 connection successful
postgres-backup  | Starting scheduled backup service...
```

---

### `./backup-manager.sh setup`

**Purpose**: Complete system setup and configuration

**What it does**:

- Validates all environment variables
- Stops any existing backup services
- Force rebuilds Docker images (no cache)
- Tests S3 connectivity and permissions
- Creates S3 folder structure
- Ensures target database exists
- Starts backup service
- Runs test backup to verify everything works

**Example**:

```bash
./backup-manager.sh setup
```

**Complete output flow**:

```
Setting up S3 for PostgreSQL backups...
Stopping existing backup services...
Rebuilding backup and restore images...
[Docker build output...]
Testing S3 connection...
✓ S3 connection successful
Creating S3 folder structure...
✓ S3 folder structure created
Ensuring production_db database exists...
✓ Database already exists
Starting backup service...
✓ Backup service started
Testing backup...
✓ Test backup completed
S3 setup completed successfully!
```

---

### `./backup-manager.sh help`

**Purpose**: Display help information

**What it does**:

- Shows all available commands
- Provides usage examples
- Quick reference guide

## 🔄 Backup Types and Retention

### Backup Categories

1. **Daily Backups**
   - Created every day at 2 AM UTC
   - Stored in `s3://bucket/backup/daily/`
   - Default retention: 1825 days (5 years)

2. **Weekly Backups**
   - Created on Sundays at 2 AM UTC (if enabled)
   - Stored in `s3://bucket/backup/weekly/`
   - Separate retention policy

3. **Monthly Backups**
   - Created on 1st of month at 2 AM UTC (if enabled)
   - Stored in `s3://bucket/backup/monthly/`
   - Longer retention for compliance

### Backup Filename Format

```
{database_name}_{timestamp}.sql.gz
```

Example: `production_db_2025-06-13T08:43:16Z.sql.gz`

- `production_db`: Your database name
- `2025-06-13T08:43:16Z`: ISO 8601 timestamp in UTC
- `.sql.gz`: Compressed SQL dump

## 🛠️ Configuration Options

### Environment Variables

The backup/restore containers use generic `S3_*` variables. The `.env` you edit uses `HETZNER_S3_*` names which are mapped into the containers by `docker-compose.yaml`. This makes the setup provider‑agnostic while keeping the code consistent.

S3 settings inside containers (effective variables):

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `S3_ACCESS_KEY_ID` | S3 access key | - | ✅ |
| `S3_SECRET_ACCESS_KEY` | S3 secret key | - | ✅ |
| `S3_BUCKET` | S3 bucket name | - | ✅ |
| `S3_REGION` | S3 region | `us-west-1` | No |
| `S3_ENDPOINT` | S3 endpoint URL | - | For non-AWS |
| `S3_PREFIX` | S3 path prefix | `backup` | No |

Mapping from `.env` to container variables:

| `.env` key | Container env |
|------------|---------------|
| `HETZNER_S3_ACCESS_KEY` | `S3_ACCESS_KEY_ID` |
| `HETZNER_S3_SECRET_KEY` | `S3_SECRET_ACCESS_KEY` |
| `HETZNER_S3_BUCKET` | `S3_BUCKET` |
| `HETZNER_S3_REGION` | `S3_REGION` |
| `HETZNER_S3_ENDPOINT` | `S3_ENDPOINT` |

Database and scheduling variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `POSTGRES_DB` | Database name | `production_db` | ✅ |
| `POSTGRES_USER` | Database user | `dbuser` | ✅ |
| `POSTGRES_PASSWORD` | Database password | - | ✅ |
| `POSTGRES_HOST` | Database host | `postgres` | No |
| `POSTGRES_PORT` | Database port | `5432` | No |
| `BACKUP_RETENTION_DAYS` | Days to keep backups | `30` | No |
| `WEEKLY_BACKUP` | Enable weekly backups | `yes` | No |
| `MONTHLY_BACKUP` | Enable monthly backups | `yes` | No |

### Backup Schedule Customization

The backup schedule is controlled by the `SCHEDULE` environment variable using standard cron syntax:

```bash
# Daily at 2 AM (default)
SCHEDULE="0 2 * * *"

# Daily at 3:30 AM
SCHEDULE="30 3 * * *" 

# Twice daily (6 AM and 6 PM)
SCHEDULE="0 6,18 * * *"

# Weekly on Sundays at 1 AM
SCHEDULE="0 1 * * 0"
```

## 🚨 Troubleshooting

### Common Issues

#### 1. "Database does not exist" Error

```bash
# Create the database
docker exec postgres-prod psql -U dbuser -c "CREATE DATABASE production_db;"

# Or run setup to auto-create
./backup-manager.sh setup
```

#### 2. "S3 connection failed" Error

- Verify S3 credentials in `.env`
- Check S3 endpoint URL format
- Ensure bucket exists and is accessible
- Test with AWS CLI: `aws s3 ls s3://your-bucket --endpoint-url YOUR_ENDPOINT`

#### 3. "PostgreSQL version mismatch" Error

- Run setup to rebuild images: `./backup-manager.sh setup`
- This will update to matching PostgreSQL client version

#### 4. "Permission denied" Errors

- Ensure script is executable: `chmod +x backup-manager.sh`
- Check Docker permissions for your user

#### 5. Backup Service Not Running

```bash
# Check if service is running
docker ps | grep backup

# Start service
./backup-manager.sh start-backup-service

# Check logs for errors
./backup-manager.sh logs
```

### Verification Commands

```bash
# Check backup service status
docker ps --format "table {{.Names}}\t{{.Status}}" | grep backup

# Test database connectivity
docker exec postgres-prod pg_isready -h postgres -p 5432 -U dbuser

# Test S3 connectivity
aws s3 ls s3://your-bucket --endpoint-url YOUR_ENDPOINT

# Check backup files in S3
aws s3 ls s3://your-bucket/backup/daily/ --endpoint-url YOUR_ENDPOINT

# Monitor real-time logs
./backup-manager.sh logs
```

## 📁 File Structure

```
TheGreatPostgres/
├── backup-manager.sh           # Main management script (host)
├── docker-compose.yaml         # Service definitions
├── readme.md                   # This guide
├── .env                        # Environment configuration (you create this)
├── backup/
│   ├── Dockerfile              # Backup container image
│   └── scripts/
│       ├── backup.sh           # Backup execution script (in container)
│       └── run.sh              # Container startup and scheduling
├── restore/
│   ├── Dockerfile              # Restore container image
│   └── scripts/
│       └── restore.sh          # Restore execution script (in container)
├── config/
│   └── render-config.sh        # Auto-tunes PostgreSQL config at startup
├── init-scripts/
│   └── 10-extensions.sh        # Enables TimescaleDB (+ pgvector if present)
├── pgadmin-servers.json        # Preconfigured pgAdmin connection
└── (data volumes configured in docker-compose)
```

## 🔐 Security Best Practices

1. **Environment Variables**: Keep `.env` file secure and never commit to version control
2. **S3 Permissions**: Use minimal required S3 permissions for backup bucket
3. **Network Security**: Bind PostgreSQL to private network interfaces only
4. **Backup Encryption**: Consider S3 bucket encryption for sensitive data
5. **Access Control**: Restrict access to backup management scripts

## 📊 Monitoring and Alerts

### Check Backup Success

```bash
# View recent backup activity
./backup-manager.sh logs | tail -50

# List recent backups
./backup-manager.sh list daily | head -5

# Check backup file sizes
aws s3 ls s3://your-bucket/backup/daily/ --human-readable --summarize
```

### Automated Monitoring

Consider setting up monitoring alerts for:

- Backup service health checks
- S3 upload failures
- Database connectivity issues
- Backup file size anomalies

## 🔄 Disaster Recovery

### Complete Database Recovery

1. **Prepare clean environment**:

   ```bash
   # Stop applications using the database
   docker compose stop your-app
   ```

2. **Restore from backup**:

   ```bash
   # Restore latest backup
   ./backup-manager.sh restore-latest
   
   # Or restore specific backup
   ./backup-manager.sh restore production_db_2025-06-13T08:43:16Z.sql.gz
   ```

3. **Verify restoration**:

   ```bash
   # Check table count
   docker exec postgres-prod psql -U dbuser -d production_db -c "\dt"
   
   # Verify critical data
   docker exec postgres-prod psql -U dbuser -d production_db -c "SELECT COUNT(*) FROM your_critical_table;"
   ```

4. **Resume operations**:

   ```bash
   # Restart applications
   docker compose up -d your-app
   ```

## 📞 Support

For issues with this backup system:

1. Check the troubleshooting section above
2. Review logs: `./backup-manager.sh logs`
3. Verify configuration: `cat .env`
4. Test components individually using the commands in this guide

The backup system is designed to be reliable and self-healing. Most issues can be resolved by running `./backup-manager.sh setup` to reset and reconfigure everything.
