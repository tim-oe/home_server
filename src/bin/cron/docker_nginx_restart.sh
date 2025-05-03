#!/bin/bash
#
# script to recycle nginx
# runs from cron.d as root but should be set as follows
# chown root:root
# chmod 755
#

DATE=`date "+%Y%m%d"`
date
echo "restarting nginx $DATE"

pushd /mnt/raid/services/nginx
docker compose down
docker compose up -d
#docker exec -it nginx /bin/bash -c "nginx -s reload"
popd

echo 'complete'
