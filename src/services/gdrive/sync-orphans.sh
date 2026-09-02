#!/bin/sh
# Push the two backup trees that are not owned by an offen sidecar.
set -eu

rc=0
RCLONE_SRC=/backup/services RCLONE_DEST=gdrive:/backup/docker/services \
  /bin/sh /rclone-sync.sh || rc=$?
RCLONE_SRC=/backup/weather RCLONE_DEST=gdrive:/backup/weather/db \
  /bin/sh /rclone-sync.sh || rc=$?
exit "$rc"
