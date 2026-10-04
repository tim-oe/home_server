#!/bin/sh
# Map EST_BACKUP_* from the host environment file into the names Restic expects,
# then start Backrest. Backrest passes this process environment through to Restic.
set -eu
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

host_env=/etc/host-environment
if [ -r "$host_env" ]; then
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
      EST_BACKUP_ID|EST_BACKUP_KEY|EST_BACKUP_BUCKET|EST_BACKUP_AWS_REGION|RESTIC_PASSWORD)
        export "$key=$val"
        ;;
    esac
  done < "$host_env"
fi

if [ -n "${EST_BACKUP_ID:-}" ] && [ -n "${EST_BACKUP_KEY:-}" ] && [ -n "${EST_BACKUP_AWS_REGION:-}" ]; then
  export AWS_ACCESS_KEY_ID="$EST_BACKUP_ID"
  export AWS_SECRET_ACCESS_KEY="$EST_BACKUP_KEY"
  export AWS_DEFAULT_REGION="$EST_BACKUP_AWS_REGION"
  export AWS_REGION="$EST_BACKUP_AWS_REGION"
else
  echo "backrest: EST_BACKUP_ID, EST_BACKUP_KEY, or EST_BACKUP_AWS_REGION missing in /etc/environment" >&2
fi
if [ -z "${RESTIC_PASSWORD:-}" ]; then
  echo "backrest: RESTIC_PASSWORD missing in /etc/environment" >&2
fi

exec /docker-entrypoint "$@"
