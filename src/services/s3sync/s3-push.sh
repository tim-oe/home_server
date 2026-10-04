#!/bin/sh
# Restic backup of EST_BACKUP_SRC to the configured S3 bucket. Called from crond.
# Chunks already stored are not uploaded again, so a rerun resumes an interrupted backup.
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
      RESTIC_PASSWORD|KEEP_WEEKLY) export "$key=$val" ;;
      GOTIFY_TOKEN|GOTIFY_APP_TOKEN) export "$key=$val" ;;
    esac
  done < "$host_env"
}
load_host_environment

export GOTIFY_TOKEN="${GOTIFY_APP_TOKEN:-${GOTIFY_TOKEN:-}}"
. /gotify-notify.sh
QUIET_MINUTES="${QUIET_MINUTES:-30}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/cache}"
export RESTIC_CACHE_DIR

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
[ -n "${RESTIC_PASSWORD:-}" ] || fail_config "RESTIC_PASSWORD is required"
case "$KEEP_WEEKLY" in
  ''|*[!0-9]*) fail_config "KEEP_WEEKLY must be a positive number of weeks" ;;
esac
[ "$KEEP_WEEKLY" -ge 1 ] || fail_config "KEEP_WEEKLY must be a positive number of weeks"

export AWS_ACCESS_KEY_ID="$EST_BACKUP_ID"
export AWS_SECRET_ACCESS_KEY="$EST_BACKUP_KEY"
export AWS_DEFAULT_REGION="$EST_BACKUP_AWS_REGION"
export AWS_REGION="$EST_BACKUP_AWS_REGION"
export RESTIC_REPOSITORY="s3:s3.${EST_BACKUP_AWS_REGION}.amazonaws.com/${EST_BACKUP_BUCKET}"
export RESTIC_PASSWORD

# Prune repacks objects, so every restic command that writes uses STANDARD.
# Infrequent Access bills a 30-day minimum and a retrieval fee on those rewrites.
restic_cmd() {
  restic -o s3.storage-class=STANDARD "$@"
}

ensure_repo() {
  if restic_cmd cat config >/dev/null 2>/tmp/restic-open.err; then
    rm -f /tmp/restic-open.err
    echo "s3-push: repository ready"
    return 0
  fi
  err=$(cat /tmp/restic-open.err 2>/dev/null || true)
  rm -f /tmp/restic-open.err
  case "$err" in
    *wrong\ password*|*no\ key\ found*|*ciphertext\ verification\ failed*)
      fail_config "RESTIC_PASSWORD was rejected by the existing repository"
      ;;
  esac
  echo "s3-push: initializing repository ${RESTIC_REPOSITORY}"
  if ! restic_cmd init; then
    fail_config "restic init failed for ${RESTIC_REPOSITORY}"
  fi
}

if [ "${SNAPSHOTS_ONLY:-0}" = 1 ]; then
  restic_cmd snapshots --no-lock --host s3sync
  exit 0
fi

exec 9>/tmp/s3sync.lock
if ! flock -n 9; then
  notify 5 "s3sync skipped" "previous backup still running"
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

ensure_repo

echo "s3-push: restic backup /data -> ${RESTIC_REPOSITORY}"
started=$(date +%s)
set +e
restic_cmd backup /data \
  --exclude-file /filters.txt \
  --host s3sync \
  --tag work
backup_rc=$?
set -e
if [ "$backup_rc" -ne 0 ] && [ "$backup_rc" -ne 3 ]; then
  notify 8 "s3sync failed" "restic backup /data failed (exit ${backup_rc}); rerun resumes uploaded chunks"
  exit "$backup_rc"
fi

# Forget only after a snapshot exists. Prune would otherwise delete chunks from
# an interrupted run that are not referenced yet.
set +e
restic_cmd forget --keep-weekly "$KEEP_WEEKLY" --prune --host s3sync
forget_rc=$?
set -e
if [ "$forget_rc" -ne 0 ]; then
  notify 8 "s3sync failed" "restic forget --keep-weekly ${KEEP_WEEKLY} failed (exit ${forget_rc})"
  exit "$forget_rc"
fi

elapsed=$(( $(date +%s) - started ))
if [ "$backup_rc" -eq 3 ]; then
  notify 5 "s3sync complete with warnings" "snapshot kept some unreadable files; ${elapsed}s, keep-weekly ${KEEP_WEEKLY}"
else
  notify 3 "s3sync complete" "snapshot of /data in ${elapsed}s, keep-weekly ${KEEP_WEEKLY}"
fi
