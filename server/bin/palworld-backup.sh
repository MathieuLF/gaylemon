#!/usr/bin/env bash
set -euo pipefail

ROOT="/srv/storage/steam"
ENV_FILE="/etc/palworld/palworld.env"
PALWORLD_DIR="$ROOT/servers/palworld"
GAME_SAVED_DIR="$PALWORLD_DIR/game/Pal/Saved"
BACKUP_DIR="$PALWORLD_DIR/backups"
CONFIG_FILE="$PALWORLD_DIR/config/PalWorldSettings.ini"
ACTIVE_CONFIG_FILE="$GAME_SAVED_DIR/Config/LinuxServer/PalWorldSettings.ini"
REST_BASE_URL="${PALWORLD_REST_BASE_URL:-http://127.0.0.1:8212/v1/api}"
RETENTION_DAYS="${PALWORLD_BACKUP_RETENTION_DAYS:-14}"
SAVE_WAIT_SECONDS="${PALWORLD_BACKUP_SAVE_WAIT_SECONDS:-5}"
REQUIRE_WORLD_SAVE="${PALWORLD_BACKUP_REQUIRE_WORLD_SAVE:-0}"
MAINTENANCE_LOCK="$PALWORLD_DIR/.maintenance.lock"

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

  REST_BASE_URL="${PALWORLD_REST_BASE_URL:-$REST_BASE_URL}"
  RETENTION_DAYS="${PALWORLD_BACKUP_RETENTION_DAYS:-$RETENTION_DAYS}"
  SAVE_WAIT_SECONDS="${PALWORLD_BACKUP_SAVE_WAIT_SECONDS:-$SAVE_WAIT_SECONDS}"
  REQUIRE_WORLD_SAVE="${PALWORLD_BACKUP_REQUIRE_WORLD_SAVE:-$REQUIRE_WORLD_SAVE}"
}

read_admin_password() {
  local source_file=""

  if [ -r "$ACTIVE_CONFIG_FILE" ]; then
    source_file="$ACTIVE_CONFIG_FILE"
  elif [ -r "$CONFIG_FILE" ]; then
    source_file="$CONFIG_FILE"
  else
    return 1
  fi

  perl -ne 'if (/AdminPassword="([^"]*)"/) { print $1; exit }' "$source_file"
}

request_world_save() {
  local admin_password=""

  if ! command -v curl >/dev/null 2>&1; then
    if [ "$REQUIRE_WORLD_SAVE" = "1" ]; then
      log "curl is unavailable and REST /save is required for this backup."
      return 1
    fi
    log "curl is unavailable; continuing with file backup without REST /save."
    return 0
  fi

  admin_password="$(read_admin_password || true)"
  if [ -z "$admin_password" ]; then
    if [ "$REQUIRE_WORLD_SAVE" = "1" ]; then
      log "AdminPassword is unavailable and REST /save is required for this backup."
      return 1
    fi
    log "AdminPassword unavailable; continuing with file backup without REST /save."
    return 0
  fi

  log "Requesting Palworld REST /save before archiving."
  if curl -fsS --max-time 20 -X POST \
    -u "admin:${admin_password}" \
    -H "Content-Type: application/json" \
    --data '{}' \
    "${REST_BASE_URL}/save" >/dev/null; then
    log "REST /save accepted; waiting ${SAVE_WAIT_SECONDS}s before archiving."
    sleep "$SAVE_WAIT_SECONDS"
  else
    if [ "$REQUIRE_WORLD_SAVE" = "1" ]; then
      log "REST /save failed and is required for this backup."
      return 1
    fi
    log "REST /save failed; continuing with file backup to avoid missing the scheduled backup."
  fi
}

prepare_maintenance_lock() {
  if [ ! -e "$MAINTENANCE_LOCK" ]; then
    (umask 0007; touch "$MAINTENANCE_LOCK")
  fi
}

main() {
  load_env
  cd "$PALWORLD_DIR"

  if [ "${PALWORLD_MAINTENANCE_LOCK_HELD:-0}" != "1" ]; then
    prepare_maintenance_lock
    exec 9<"$MAINTENANCE_LOCK"
    if ! flock -n 9; then
      log "Another Palworld maintenance operation is active; backup deferred."
      exit 75
    fi
  fi

  if [ ! -d "$GAME_SAVED_DIR/SaveGames" ]; then
    log "No save directory found yet; skipping backup."
    exit 0
  fi

  mkdir -p "$BACKUP_DIR"
  request_world_save

  timestamp="$(date +%F-%H%M%S)"
  archive="$BACKUP_DIR/palworld-backup-$timestamp.tar.zst"

  files=("game/Pal/Saved/SaveGames")
  if [ -f "$ACTIVE_CONFIG_FILE" ]; then
    files+=("game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini")
  fi
  if [ -f "$CONFIG_FILE" ]; then
    files+=("config/PalWorldSettings.ini")
  fi

  log "Writing backup to $archive."
  tar --zstd -cpf "$archive" -C "$PALWORLD_DIR" "${files[@]}"

  log "Applying retention window of ${RETENTION_DAYS} days."
  find "$BACKUP_DIR" -type f -name 'palworld-backup-*.tar.zst' -mtime +"$RETENTION_DAYS" -delete
}

main "$@"
