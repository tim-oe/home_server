#!/bin/bash
#
# script to recycle nginx
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
#

DATE=`date "+%Y%m%d"`
date
echo "restarting tomcat $DATE"

cd /mnt/raid/services/nginx
docker compose restart

echo 'complete'