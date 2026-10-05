#!/bin/bash
#
# Start services an offen backup stopped and then failed to restart.
# Offen only restarts them if that same run reaches "Restarted N out of N".
# A reboot or a killed sidecar before then leaves them exited, and
# restart: unless-stopped does not start a container Docker itself stopped.
#
# A run whose sidecar is still the process that logged the stop is left
# alone, so a slow archive (array check, large volume) is not interrupted.
# Each repaired run is recorded, so a later manual stop stays down.
#
# runs from cron.d as root
# chown root:root
# chmod 755

set -u

STATE_DIR=/var/lib/backup-service-recover
mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || exit 0
find "$STATE_DIR" -type f -name '*.seen' -mtime +14 -delete

verbose=0
if [ "${VERBOSE:-0}" = 1 ] || [ -t 1 ]; then
  verbose=1
fi

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %T')" "$*"
}

note() {
  if [ "$verbose" = 1 ]; then
    log "$*"
  fi
}

# Load Gotify credentials without printing them. The URL inside containers
# is http://gotify, which does not resolve on the host.
load_gotify() {
  local host_env line key val
  for host_env in /etc/host-environment /etc/environment; do
    [ -r "$host_env" ] || continue
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
        GOTIFY_APP_TOKEN)
          [ -z "${GOTIFY_APP_TOKEN:-}" ] && export GOTIFY_APP_TOKEN="$val"
          ;;
        GOTIFY_TOKEN)
          [ -z "${GOTIFY_TOKEN:-}" ] && export GOTIFY_TOKEN="$val"
          ;;
        GOTIFY_URL)
          [ -z "${GOTIFY_URL:-}" ] && export GOTIFY_URL="$val"
          ;;
      esac
    done < "$host_env"
  done
  case "${GOTIFY_URL:-}" in
    ''|http://gotify|http://gotify/*)
      local ip
      ip=$(docker inspect -f '{{index .NetworkSettings.Networks "share-net" "IPAddress"}}' gotify 2>/dev/null || true)
      if [ -n "$ip" ]; then
        export GOTIFY_URL="http://${ip}"
      fi
      ;;
  esac
}

notify() {
  local title=$1 message=$2 helper
  load_gotify
  helper=$(find /mnt/raid/services -path '*/_common/gotify-notify.sh' -type f 2>/dev/null | head -1)
  if [ -z "$helper" ]; then
    return 0
  fi
  # shellcheck disable=SC1090
  . "$helper"
  gotify_notify 8 "$title" "$message" || true
}

# Seconds-resolution timestamps compare in lexicographic order.
sec() {
  printf '%s' "${1:0:19}"
}

recover_label() {
  local backup=$1 label=$2
  local run_time run_sec started start_sec running stop_n
  local names name status seen started_names

  run_time=$(docker logs "$backup" 2>&1 | sed -n 's/^time=\([^ ]*\) .*Now running script on schedule.*/\1/p' | tail -1)
  if [ -z "$run_time" ]; then
    note "$backup has no backup run in its logs"
    return 0
  fi
  run_sec=$(sec "$run_time")

  stop_n=$(docker logs --since "$run_time" "$backup" 2>&1 | sed -n 's/.*Stopping \([0-9][0-9]*\) out of.*/\1/p' | tail -1)
  if [ -z "${stop_n:-}" ] || [ "$stop_n" = 0 ]; then
    note "$backup last run $run_sec did not stop containers"
    return 0
  fi
  if docker logs --since "$run_time" "$backup" 2>&1 | grep -q 'Restarted .* stopped container'; then
    note "$backup last run $run_sec already restarted its containers"
    return 0
  fi

  started=$(docker inspect -f '{{.State.StartedAt}}' "$backup")
  running=$(docker inspect -f '{{.State.Running}}' "$backup")
  start_sec=$(sec "$started")
  # The sidecar process that issued the stop is still alive.
  if [ "$running" = "true" ] && [[ "$start_sec" < "$run_sec" || "$start_sec" == "$run_sec" ]]; then
    note "$backup run $run_sec still in progress, leaving stopped containers down"
    return 0
  fi

  names=$(docker ps -a --filter "label=docker-volume-backup.stop-during-backup=${label}" --format '{{.Names}}')
  if [ -z "$names" ]; then
    return 0
  fi

  started_names=
  # Databases first so a stack like bookstack can reach its dependency.
  for pass in 1 2; do
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      case "$name" in
        *db*|*mariadb*) [ "$pass" = 1 ] || continue ;;
        *) [ "$pass" = 2 ] || continue ;;
      esac
      status=$(docker inspect -f '{{.State.Status}}' "$name")
      case "$status" in
        running|restarting|paused)
          note "$name is $status"
          continue
          ;;
      esac
      seen="$STATE_DIR/${name}.${run_sec}.seen"
      if [ -f "$seen" ]; then
        note "$name already recovered for run $run_sec"
        continue
      fi
      log "starting $name (backup ${label} run ${run_sec} did not restart it)"
      if docker start "$name" >/dev/null; then
        touch "$seen"
        started_names="${started_names} ${name}"
      else
        log "failed to start $name"
      fi
    done <<< "$names"
  done

  if [ -n "$started_names" ]; then
    notify "backup left services stopped" "Started${started_names} after an interrupted ${label} backup (${run_sec})."
  fi
}

if ! docker info >/dev/null 2>&1; then
  log "docker is not reachable"
  exit 0
fi

while IFS= read -r line; do
  name=${line%% *}
  image=${line#* }
  case "$image" in
    offen/docker-volume-backup:*) ;;
    *) continue ;;
  esac
  label=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" | sed -n 's/^BACKUP_STOP_DURING_BACKUP_LABEL=//p' | head -1)
  if [ -z "$label" ]; then
    note "$name does not stop containers"
    continue
  fi
  recover_label "$name" "$label"
done < <(docker ps -a --format '{{.Names}} {{.Image}}')
