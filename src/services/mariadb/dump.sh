#!/bin/sh
set -eu
mkdir -p /dumps
mariadb-dump \
  --user=root \
  --password="${MARIADB_ROOT_PASSWORD}" \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  --hex-blob \
  --result-file=/dumps/all-databases.sql
