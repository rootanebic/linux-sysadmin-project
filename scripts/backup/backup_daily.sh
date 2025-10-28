#!/bin/bash
# backup_daily.sh - Daily backup script

DATE=$(date +'%Y-%m-%d')
BACKUP_DIR="/backups/$DATE"
SOURCE_DIRS="/etc /var/www /home /srv/db_backups"
REMOTE_USER="user"
REMOTE_HOST="192.168.1.156"
REMOTE_DIR="/home/user/backups/$(hostname)"

mkdir -p "$BACKUP_DIR"
echo "[INFO] Starting backup at $(date)"

tar -czf "$BACKUP_DIR/system_backup.tar.gz" $SOURCE_DIRS

if [ $? -eq 0 ]; then
    echo "[OK] Local backup completed successfully."
else
    echo "[ERROR] Local backup failed!"
    exit 1
fi

# Sync to remote backup server
rsync -avz -e "ssh -i /home/adminuser/.ssh/id_ed25519" --delete "$BACKUP_DIR" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"

echo "[INFO] Backup finished at $(date)"
