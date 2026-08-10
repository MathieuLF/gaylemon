#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"
BASE_URL="http://127.0.0.1:8212/v1/api"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/srv/storage/steam/bin/gaylemon-curl-config.sh
. "$SCRIPT_DIR/gaylemon-curl-config.sh"

method="${1:-GET}"
path="${2:-/info}"
body="${3:-}"
if [ "$method" != "GET" ] && [ -z "$body" ]; then
  body="{}"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Palworld settings file not found: $CONFIG_FILE" >&2
  exit 1
fi

admin_password="$(perl -ne 'if (/AdminPassword="([^"]*)"/) { print $1; exit }' "$CONFIG_FILE")"

if [ -z "$admin_password" ]; then
  echo "AdminPassword is not configured." >&2
  exit 1
fi

curl_config="$(gaylemon_curl_config_file)"
trap 'rm -f "$curl_config"' EXIT
if ! gaylemon_curl_write_basic "$curl_config" admin "$admin_password"; then
  echo "AdminPassword contains unsupported characters." >&2
  exit 1
fi
unset admin_password

case "$path" in
  /*) ;;
  *) path="/$path" ;;
esac

if [ "$method" = "GET" ]; then
  curl --config "$curl_config" -fsS "${BASE_URL}${path}"
else
  curl --config "$curl_config" -fsS -X "$method" \
    -H "Content-Type: application/json" \
    --data "$body" \
    "${BASE_URL}${path}"
fi
