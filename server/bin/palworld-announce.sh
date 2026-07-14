#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--base64" ]; then
  shift
  message="$(printf '%s' "${1:-}" | base64 -d)"
else
  message="$*"
fi

if [ -z "$message" ]; then
  echo "Usage: palworld-announce.sh MESSAGE" >&2
  exit 1
fi

payload="$(jq -nc --arg message "$message" '{message:$message}')"
/srv/storage/steam/bin/palworld-api.sh POST /announce "$payload"
printf '\n'
