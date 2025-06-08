#!/bin/bash
#
# script backup data to gdrive
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755

DATE=`date "+%Y%m%d"`
START=`date "+%Y-%m-%d %T"`
echo "starting backup to service folder $START"

BACKUP_DIR=/mnt/backup/docker/services
ROOT_DIR=/mnt/raid/services
EXCLUDE_DIRS="./nginx/log/*"

mkdir -p $BACKUP_DIR

pushd $ROOT_DIR
zip -9 -r $BACKUP_DIR/svc-$DATE.zip . /etc/environment -x $EXCLUDE_DIRS
popd

# Remove old backups
find $BACKUP_DIR -maxdepth 1 -name '*.zip' -type f -mtime +15 -exec rm -vf {} \;

END=`date "+%Y-%m-%d %T"`
echo "complete backup to service folder $END"
