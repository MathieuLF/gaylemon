#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"
BASE_URL="http://127.0.0.1:8212/v1/api"

method="${1:-GET}"
path="${2:-/info}"
body="${3:-}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Palworld settings file not found: $CONFIG_FILE" >&2
  exit 1
fi

admin_password="$(perl -ne 'if (/AdminPassword="([^"]*)"/) { print $1; exit }' "$CONFIG_FILE")"

if [ -z "$admin_password" ]; then
  echo "AdminPassword is not configured." >&2
  exit 1
fi

case "$path" in
  /*) ;;
  *) path="/$path" ;;
esac

if [ "$method" = "GET" ]; then
  curl -fsS -u "admin:${admin_password}" "${BASE_URL}${path}"
else
  curl -fsS -X "$method" \
    -u "admin:${admin_password}" \
    -H "Content-Type: application/json" \
    --data "$body" \
    "${BASE_URL}${path}"
fi
