# shellcheck shell=sh
# Gotify helper for backup scripts. Source from /gotify-notify.sh or ./_common/gotify-notify.sh
# gotify_notify PRIORITY TITLE MESSAGE

_gotify_load_host_environment() {
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
}

_gotify_load_host_environment

# gotify_notify PRIORITY TITLE MESSAGE
gotify_notify() {
  priority=$1
  title=$2
  message=$3
  _gotify_load_host_environment
  token="${GOTIFY_APP_TOKEN:-${GOTIFY_TOKEN:-}}"
  token=$(printf '%s' "$token" | tr -d '\r\n')
  if [ -z "${GOTIFY_URL:-}" ] || [ -z "$token" ]; then
    return 0
  fi
  # Query ?token= breaks when the app token contains +, /, or =; use header auth instead.
  if command -v curl >/dev/null 2>&1; then
    if curl -sfS -m 10 -X POST "${GOTIFY_URL}/message" \
      -H "X-Gotify-Key: ${token}" \
      -F "title=${title}" \
      -F "message=${message}" \
      -F "priority=${priority}" \
      -o /dev/null 2>/dev/null; then
      return 0
    fi
  fi
  if command -v wget >/dev/null 2>&1; then
    if wget -q -O /dev/null --timeout=10 \
      --header="X-Gotify-Key: ${token}" \
      --post-data="title=${title}&message=${message}&priority=${priority}" \
      "${GOTIFY_URL}/message" 2>/dev/null; then
      return 0
    fi
  fi
  echo "gotify notify failed (check GOTIFY_APP_TOKEN)" >&2
  return 1
}
