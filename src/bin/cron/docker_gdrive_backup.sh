#!/bin/bash
#
# see https://rclone.org/
# script backup data to gdrive
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
#

DATE=`date "+%Y%m%d"`
date
echo "starting backup to gdrive $DATE"

rclone sync --progress /mnt/backup/docker/vaultwarden gdrive:/backup/services/vault
rclone sync --progress /mnt/backup/docker/unifi gdrive:/backup/services/unifi
rclone sync --progress /mnt/backup/weather/db gdrive:/backup/weather/db

echo 'complete'
