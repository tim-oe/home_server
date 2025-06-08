#!/bin/bash
#
# see https://rclone.org/
# script backup data to gdrive
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
# when in doubt
# rsync -av --no-perms --no-owner --no-group <src> <dest>
#

START=`date "+%Y-%m-%d %T"`
echo "starting backup to gdrive $START"

rclone sync --progress /mnt/backup/docker/services gdrive:/backup/docker/services
rclone sync --progress /mnt/backup/docker/vaultwarden gdrive:/backup/services/vault
rclone sync --progress /mnt/backup/docker/unifi gdrive:/backup/services/unifi
rclone sync --progress /mnt/backup/weather/db gdrive:/backup/weather/db

END=`date "+%Y-%m-%d %T"`
echo "complete backup to gdrive $END"
