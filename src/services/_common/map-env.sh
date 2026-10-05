#!/bin/sh
# Copy selected keys out of the host environment file, then exec the image command.
# Compose does not interpolate /etc/environment, and env_file would replace PATH.
# Usage: map-env.sh DEST=SRC [DEST=SRC:-default] [DEST=prefix|SRC] -- command [args...]
#        map-env.sh --get KEY
# The file is mounted at /etc/host-environment. HOST_ENV overrides that path.
set -eu

host_env=${HOST_ENV:-/etc/host-environment}

lookup() {
  key=$1
  [ -r "$host_env" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      *=*) ;;
      *) continue ;;
    esac
    k=${line%%=*}
    v=${line#*=}
    [ "$k" = "$key" ] || continue
    case "$v" in
      \"*\") v=${v#\"}; v=${v%\"} ;;
      \'*\') v=${v#\'}; v=${v%\'} ;;
    esac
    printf '%s' "$v" | tr -d '\r'
    return 0
  done < "$host_env"
}

if [ "${1:-}" = "--get" ]; then
  lookup "${2:?map-env: --get needs a key}"
  exit 0
fi

while [ "$#" -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    break
  fi
  spec=$1
  shift
  dest=${spec%%=*}
  rest=${spec#*=}
  default_set=0
  default=
  case "$rest" in
    *:-*)
      src=${rest%%:-*}
      default=${rest#*:-}
      default_set=1
      ;;
    *)
      src=$rest
      ;;
  esac
  prefix=
  case "$src" in
    *\|*)
      prefix=${src%%|*}
      src=${src#*|}
      ;;
  esac
  case "$dest" in
    ''|*[!A-Za-z0-9_]*)
      echo "map-env: bad destination name: $dest" >&2
      exit 1
      ;;
  esac
  case "$src" in
    ''|*[!A-Za-z0-9_]*)
      echo "map-env: bad source name: $src" >&2
      exit 1
      ;;
  esac
  val=$(lookup "$src" || true)
  if [ -z "$val" ] && [ "$default_set" -eq 1 ]; then
    val=$default
  fi
  if [ -n "$prefix" ]; then
    if [ -z "$val" ]; then
      continue
    fi
    val="${prefix}${val}"
  fi
  if [ -n "$val" ] || [ "$default_set" -eq 1 ]; then
    export "$dest=$val"
  fi
done

if [ "$#" -eq 0 ]; then
  echo "map-env: missing command" >&2
  exit 1
fi
exec "$@"
