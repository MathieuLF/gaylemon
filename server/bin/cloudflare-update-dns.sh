#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/palworld/palworld.env"
API="https://api.cloudflare.com/client/v4"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

load_env() {
  if [ -r "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi
}

current_public_ip() {
  curl -fsSL https://api.ipify.org
}

ensure_env() {
  : "${CF_API_TOKEN:?CF_API_TOKEN is required}"
  : "${CF_ZONE_ID:?CF_ZONE_ID is required}"
  : "${CF_RECORD_NAME:?CF_RECORD_NAME is required}"
  CF_RECORD_TYPE="${CF_RECORD_TYPE:-A}"
  CF_RECORD_TTL="${CF_RECORD_TTL:-1}"
  CF_RECORD_PROXIED="${CF_RECORD_PROXIED:-false}"
}

cf_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [ -n "$data" ]; then
    curl -fsSL -X "$method" "$API$path" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -fsSL -X "$method" "$API$path" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json"
  fi
}

main() {
  load_env
  ensure_env

  ip="$(current_public_ip)"
  log "Current public IP: $ip"

  records="$(cf_api GET "/zones/$CF_ZONE_ID/dns_records?type=$CF_RECORD_TYPE&name=$CF_RECORD_NAME")"
  record_count="$(printf '%s' "$records" | jq -r '.result | length')"

  payload="$(jq -nc \
    --arg type "$CF_RECORD_TYPE" \
    --arg name "$CF_RECORD_NAME" \
    --arg content "$ip" \
    --argjson ttl "$CF_RECORD_TTL" \
    --argjson proxied "$CF_RECORD_PROXIED" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  if [ "$record_count" -eq 0 ]; then
    log "Record not found. Creating $CF_RECORD_NAME."
    cf_api POST "/zones/$CF_ZONE_ID/dns_records" "$payload" >/dev/null
    log "DNS record created."
    exit 0
  fi

  record_id="$(printf '%s' "$records" | jq -r '.result[0].id')"
  old_ip="$(printf '%s' "$records" | jq -r '.result[0].content')"
  if [ "$old_ip" = "$ip" ]; then
    log "DNS record already matches."
    exit 0
  fi

  log "Updating $CF_RECORD_NAME from $old_ip to $ip."
  cf_api PATCH "/zones/$CF_ZONE_ID/dns_records/$record_id" "$payload" >/dev/null
  log "DNS record updated."
}

main "$@"
