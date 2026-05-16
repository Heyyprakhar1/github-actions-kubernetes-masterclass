#!/bin/bash
# scripts/backup.sh
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"

kubectl exec -n skillpulse mysql-0 -- \
  sh -c 'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE' \
  > "$BACKUP_DIR/skillpulse_$TIMESTAMP.sql"

gzip "$BACKUP_DIR/skillpulse_$TIMESTAMP.sql"
echo "Backup saved: skillpulse_$TIMESTAMP.sql.gz"

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/*.sql.gz | tail -n +8 | xargs -r rm
