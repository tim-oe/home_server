#!/bin/sh
# Offsite push for an offen archive directory. Invoked by prune-post (or crond).
# GOTIFY_URL plus GOTIFY_TOKEN or GOTIFY_APP_TOKEN (from host /etc/environment).
set -eu
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SRC="${RCLONE_SRC:?RCLONE_SRC is required}"
DEST="${RCLONE_DEST:?RCLONE_DEST is required}"
GOTIFY_TOKEN="${GOTIFY_TOKEN:-${GOTIFY_APP_TOKEN:-}}"

notify_failure() {
  rc=$1
  msg="rclone sync ${SRC} -> ${DEST} failed (exit ${rc})"
  echo "$msg" >&2
  if [ -z "${GOTIFY_URL:-}" ] || [ -z "${GOTIFY_TOKEN:-}" ]; then
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null \
      --post-data "title=rclone sync failed&message=${msg}&priority=8" \
      "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" || true
  fi
}

echo "rclone sync ${SRC} -> ${DEST}"
rclone sync "$SRC" "$DEST" || {
  rc=$?
  notify_failure "$rc"
  exit "$rc"
}
echo "rclone sync complete"
