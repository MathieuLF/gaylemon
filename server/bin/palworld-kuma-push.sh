#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/palworld/kuma.env"
API_BIN="/srv/storage/steam/bin/palworld-api.sh"

if [ -r "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

if [ -z "${KUMA_PUSH_URL:-}" ]; then
  echo "KUMA_PUSH_URL is not configured in $ENV_FILE." >&2
  exit 1
fi

push_base="${KUMA_PUSH_URL%%\?*}"

send_push() {
  local status="$1"
  local msg="$2"
  local ping="${3:-}"

  curl -fsS --get "$push_base" \
    --data-urlencode "status=$status" \
    --data-urlencode "msg=$msg" \
    --data-urlencode "ping=$ping" >/dev/null
}

format_uptime() {
  local seconds="${1:-0}"
  local days hours minutes

  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf '%dj%02dh%02dm' "$days" "$hours" "$minutes"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh%02dm' "$hours" "$minutes"
  else
    printf '%dm' "$minutes"
  fi
}

mode="${1:-auto}"
if [ "$mode" = "down" ]; then
  message="${2:-Palworld indisponible}"
  down_push_count="${KUMA_MAINTENANCE_DOWN_PUSH_COUNT:-3}"
  for ((attempt = 1; attempt <= down_push_count; attempt++)); do
    send_push "down" "$message" ""
    if [ "$attempt" -lt "$down_push_count" ]; then
      sleep 1
    fi
  done
  echo "Pushed Palworld DOWN to Uptime Kuma ${down_push_count} times: ${message}."
  exit 0
elif [ "$mode" != "auto" ]; then
  echo "Usage: $0 [down [message]]" >&2
  exit 2
fi

if metrics="$("$API_BIN" GET /metrics 2>&1)"; then
  players="$(printf '%s' "$metrics" | jq -r '.currentplayernum // 0')"
  max_players="$(printf '%s' "$metrics" | jq -r '.maxplayernum // 0')"
  fps="$(printf '%s' "$metrics" | jq -r '.serverfps // 0')"
  fps_average="$(printf '%s' "$metrics" | jq -r '((.serverfpsaverage // 0) * 10 | round / 10)')"
  frame_time="$(printf '%s' "$metrics" | jq -r '((.serverframetime // 0) * 10 | round / 10)')"
  world_days="$(printf '%s' "$metrics" | jq -r '.days // 0')"
  base_camps="$(printf '%s' "$metrics" | jq -r '.basecampnum // 0')"
  uptime_seconds="$(printf '%s' "$metrics" | jq -r '.uptime // 0')"
  uptime_human="$(format_uptime "$uptime_seconds")"
  msg="Palworld OK - joueurs ${players}/${max_players} | FPS ${fps} (avg ${fps_average}) | frame ${frame_time} ms | jour ${world_days} | camps ${base_camps} | uptime ${uptime_human}"

  send_push "up" "$msg" "$frame_time"
  echo "Pushed Palworld UP to Uptime Kuma: ${msg}."
else
  send_push "down" "Palworld API indisponible: ${metrics}" ""
  echo "Pushed Palworld DOWN to Uptime Kuma." >&2
  exit 1
fi
