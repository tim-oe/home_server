#!/bin/sh
# One-way push of EST_BACKUP_SRC to the configured S3 bucket. Called from crond.
set -eu
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "s3-push: starting $(date -Iseconds 2>/dev/null || date)"

# Docker env_file and crond jobs: busybox crond only gives crontab vars (e.g. PATH) to
# jobs, so credentials are loaded from the mounted host file (handles = in secrets).
load_host_environment() {
  host_env=/etc/host-environment
  [ -r "$host_env" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      *=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    val=$(printf '%s' "$val" | tr -d '\r')
    case "$key" in
      EST_BACKUP_ID) export EST_BACKUP_ID="$val" ;;
      EST_BACKUP_KEY) export EST_BACKUP_KEY="$val" ;;
      EST_BACKUP_BUCKET) export EST_BACKUP_BUCKET="$val" ;;
      EST_BACKUP_AWS_REGION) export EST_BACKUP_AWS_REGION="$val" ;;
      EST_BACKUP_SRC) export EST_BACKUP_SRC="$val" ;;
      GOTIFY_TOKEN|GOTIFY_APP_TOKEN) export "$key=$val" ;;
    esac
  done < "$host_env"
}
load_host_environment

# Same as other rclone stacks: GOTIFY_APP_TOKEN in host /etc/environment, not Grafana's GOTIFY_TOKEN.
export GOTIFY_TOKEN="${GOTIFY_APP_TOKEN:-${GOTIFY_TOKEN:-}}"
. /gotify-notify.sh
QUIET_MINUTES="${QUIET_MINUTES:-30}"
MAX_DELETE="${MAX_DELETE:-50}"

notify() {
  echo "$2: $3"
  gotify_notify "$1" "$2" "$3" || true
}

fail_config() {
  msg=$1
  notify 8 "s3sync config error" "$msg"
  echo "$msg" >&2
  exit 1
}

[ -n "${EST_BACKUP_ID:-}" ] || fail_config "EST_BACKUP_ID is required"
[ -n "${EST_BACKUP_KEY:-}" ] || fail_config "EST_BACKUP_KEY is required"
[ -n "${EST_BACKUP_BUCKET:-}" ] || fail_config "EST_BACKUP_BUCKET is required"
[ -n "${EST_BACKUP_AWS_REGION:-}" ] || fail_config "EST_BACKUP_AWS_REGION is required"

export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER=AWS
export RCLONE_CONFIG_S3_REGION="$EST_BACKUP_AWS_REGION"
export RCLONE_CONFIG_S3_ACCESS_KEY_ID="$EST_BACKUP_ID"
export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="$EST_BACKUP_KEY"
export RCLONE_SRC=/data
export RCLONE_DEST="s3:${EST_BACKUP_BUCKET}"

exec 9>/tmp/s3sync.lock
if ! flock -n 9; then
  notify 5 "s3sync skipped" "previous push still running"
  exit 0
fi

if [ ! -f /data/.s3sync-sentinel ]; then
  src="${EST_BACKUP_SRC:-/mnt/backup/work}"
  notify 8 "s3sync aborted" "missing .s3sync-sentinel on the backup tree; on the host run: touch ${src}/.s3sync-sentinel"
  echo "missing /data/.s3sync-sentinel — create once on the host: touch ${src}/.s3sync-sentinel" >&2
  exit 1
fi

# Full-tree find over VM backups can run for hours. The work job should remove
# .backup-complete at start and touch it when finished; we only stat that file.
QUIET_MARKER="${QUIET_MARKER:-/data/.backup-complete}"
if [ "${SKIP_QUIET:-0}" = 1 ]; then
  echo "s3-push: SKIP_QUIET=1, not checking ${QUIET_MARKER}"
elif [ ! -f "$QUIET_MARKER" ]; then
  notify 5 "s3sync skipped" "missing ${QUIET_MARKER}; work backup in progress or marker not configured"
  exit 0
elif [ -n "$(find "$QUIET_MARKER" -mmin "-${QUIET_MINUTES}" 2>/dev/null)" ]; then
  notify 5 "s3sync skipped" "${QUIET_MARKER} updated within the last ${QUIET_MINUTES} minutes"
  exit 0
fi

RCLONE_FLAGS="--filter-from /filters.txt --max-delete ${MAX_DELETE}"
RCLONE_FLAGS="$RCLONE_FLAGS --transfers 2 --s3-upload-concurrency 4 --s3-chunk-size 64M --s3-disable-checksum"
RCLONE_FLAGS="$RCLONE_FLAGS --s3-storage-class STANDARD_IA --s3-no-check-bucket"
RCLONE_FLAGS="$RCLONE_FLAGS --retries 5 --low-level-retries 20"
RCLONE_FLAGS="$RCLONE_FLAGS -v --stats 5m --stats-one-line"
if [ -n "${BWLIMIT:-}" ]; then
  RCLONE_FLAGS="$RCLONE_FLAGS --bwlimit ${BWLIMIT}"
fi
if [ -n "${RCLONE_EXTRA:-}" ]; then
  RCLONE_FLAGS="$RCLONE_FLAGS ${RCLONE_EXTRA}"
fi
export RCLONE_FLAGS

started=$(date +%s)
if /bin/sh /rclone-sync.sh; then
  elapsed=$(( $(date +%s) - started ))
  notify 3 "s3sync complete" "pushed ${RCLONE_SRC} -> ${RCLONE_DEST} in ${elapsed}s"
else
  exit $?
fi
