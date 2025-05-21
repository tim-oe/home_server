#!/bin/bash
#
# script to recycle nginx
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
#

START=`date "+%Y-%m-%d %T"`
echo "restarting nginx $START"

pushd /mnt/raid/services/nginx
docker compose down
docker compose up -d
popd

END=`date "+%Y-%m-%d %T"`
echo "complete nginx restart $END"
