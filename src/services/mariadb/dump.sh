#!/bin/sh
set -eu
mkdir -p /dumps
# archive-pre is a docker exec, so it does not see variables map-env exported
# into the server process. Read the host file the same way the entrypoint does.
root_pw=$(/bin/sh /map-env.sh --get MARIADB_ROOT_PASSWORD)
if [ -z "$root_pw" ]; then
  echo "dump: MARIADB_ROOT_PASSWORD missing in /etc/host-environment" >&2
  exit 1
fi
mariadb-dump \
  --user=root \
  --password="$root_pw" \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  --hex-blob \
  --result-file=/dumps/all-databases.sql
