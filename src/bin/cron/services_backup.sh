#!/bin/bash
#
# script backup data to gdrive
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
#

DATE=`date "+%Y%m%d"`
date
echo "starting backup to service folder $DATE"

BACKUP_DIR=/mnt/backup/docker/services
ROOT_DIR=/mnt/raid/services
EXCLUDE_DIRS="./nginx/log/*"

mkdir -p $BACKUP_DIR

pushd $ROOT_DIR
zip -9 -r $BACKUP_DIR/svc-$DATE.zip . -x $EXCLUDE_DIRS
popd

echo 'complete'
