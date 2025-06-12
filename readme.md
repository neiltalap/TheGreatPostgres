# Commands

Create backup:  ./backup-now-s3.sh

List backups:   aws s3 ls s3://ptxv3ugg/daily/ --endpoint-url https://hel1.your-objectstorage.com

Restore:        ./restore-from-s3.sh backup_YYYYMMDD_HHMMSS.dump

View logs:      tail -f /var/log/postgres-s3-backup.log
