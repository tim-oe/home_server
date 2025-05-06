#!/bin/bash
#
# script backup data to gdrive
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
# when in doubt
# rsync -av --no-perms --no-owner --no-group <src> <dest>

DATE=`date "+%Y%m%d"`
date
echo "starting backup to service folder $DATE"

BACKUP_DIR=/mnt/backup/docker/services
ROOT_DIR=/mnt/raid/services
EXCLUDE_DIRS="./nginx/log/*"
MAX_BACKUPS=4

mkdir -p $BACKUP_DIR

pushd $ROOT_DIR
zip -9 -r $BACKUP_DIR/svc-$DATE.zip . -x $EXCLUDE_DIRS
popd

# Remove old backups
#OLD_BACKUPS=$(find "$BACKUP_DIR" -type f -printf '%T+ %p\n' | sort | head -n -$MAX_BACKUPS | awk '{print $2}' )
#for backup in $OLD_BACKUPS; do
#    rm -f "$backup"
#done

echo 'complete'
