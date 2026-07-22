#!/usr/bin/env bash
set -euo pipefail

ROOT="/srv/storage/steam"
ENV_FILE="/etc/palworld/palworld.env"
STEAMCMD_DIR="$ROOT/steamcmd"
PALWORLD_DIR="$ROOT/servers/palworld"
GAME_DIR="$PALWORLD_DIR/game"
MANIFEST_FILE="$GAME_DIR/steamapps/appmanifest_2394010.acf"
BACKUP_SCRIPT="$ROOT/bin/palworld-backup.sh"
API_BIN="$ROOT/bin/palworld-api.sh"
ANNOUNCE_SCRIPT="$ROOT/bin/palworld-announce.sh"
SERVICE_NAME="palworld.service"
WELCOME_SERVICE_NAME="palworld-welcome.service"
APP_ID="2394010"
MAINTENANCE_LOCK="$PALWORLD_DIR/.maintenance.lock"
DEFER_STATE_FILE="$PALWORLD_DIR/update-deferred.state"
API_WAIT_ATTEMPTS="${PALWORLD_UPDATE_API_WAIT_ATTEMPTS:-60}"
API_WAIT_SECONDS="${PALWORLD_UPDATE_API_WAIT_SECONDS:-2}"
RETRY_DELAY_SECONDS="${PALWORLD_UPDATE_RETRY_DELAY_SECONDS:-1800}"
COUNTDOWN_STEPS="${PALWORLD_UPDATE_COUNTDOWN_STEPS:-300 60 30}"
DEFER_IF_PLAYERS="${PALWORLD_UPDATE_DEFER_IF_PLAYERS:-true}"
UPDATE_WAS_ACTIVE=0
UPDATE_INSTALLED=0
MAINTENANCE_ARMED=0
CURRENT_BUILD="unknown"
TARGET_BUILD="unknown"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

emit_event() {
  local event_type="$1"
  local title="$2"
  local message="$3"
  local encoded_title encoded_message

  encoded_title="$(printf '%s' "$title" | base64 -w0)"
  encoded_message="$(printf '%s' "$message" | base64 -w0)"
  printf 'GAYLEMON_EVENT\t%s\t%s\t%s\n' "$event_type" "$encoded_title" "$encoded_message"
}

load_env() {
  if [ -r "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
  fi

  API_WAIT_ATTEMPTS="${PALWORLD_UPDATE_API_WAIT_ATTEMPTS:-$API_WAIT_ATTEMPTS}"
  API_WAIT_SECONDS="${PALWORLD_UPDATE_API_WAIT_SECONDS:-$API_WAIT_SECONDS}"
  RETRY_DELAY_SECONDS="${PALWORLD_UPDATE_RETRY_DELAY_SECONDS:-$RETRY_DELAY_SECONDS}"
  COUNTDOWN_STEPS="${PALWORLD_UPDATE_COUNTDOWN_STEPS:-$COUNTDOWN_STEPS}"
  DEFER_IF_PLAYERS="${PALWORLD_UPDATE_DEFER_IF_PLAYERS:-$DEFER_IF_PLAYERS}"
}

validate_positive_integer() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    log "$name must be a positive integer; received '$value'."
    return 1
  fi
}

validate_settings() {
  local previous=2147483647
  local step

  validate_positive_integer PALWORLD_UPDATE_API_WAIT_ATTEMPTS "$API_WAIT_ATTEMPTS"
  validate_positive_integer PALWORLD_UPDATE_API_WAIT_SECONDS "$API_WAIT_SECONDS"
  validate_positive_integer PALWORLD_UPDATE_RETRY_DELAY_SECONDS "$RETRY_DELAY_SECONDS"
  for step in $COUNTDOWN_STEPS; do
    validate_positive_integer PALWORLD_UPDATE_COUNTDOWN_STEPS "$step"
    if [ "$step" -ge "$previous" ]; then
      log "PALWORLD_UPDATE_COUNTDOWN_STEPS must be strictly descending."
      return 1
    fi
    previous="$step"
  done
  if [ "$previous" -eq 2147483647 ]; then
    log "PALWORLD_UPDATE_COUNTDOWN_STEPS cannot be empty."
    return 1
  fi
  if [ "$DEFER_IF_PLAYERS" != "true" ] && [ "$DEFER_IF_PLAYERS" != "false" ]; then
    log "PALWORLD_UPDATE_DEFER_IF_PLAYERS must be 'true' or 'false'."
    return 1
  fi
}

prepare_maintenance_lock() {
  if [ ! -e "$MAINTENANCE_LOCK" ]; then
    runuser -u steam -- touch "$MAINTENANCE_LOCK"
  fi
  chown steam:steam "$MAINTENANCE_LOCK"
  chmod 0660 "$MAINTENANCE_LOCK"
}

installed_build() {
  awk -F\" '/"buildid"/ {print $4; exit}' "$MANIFEST_FILE" 2>/dev/null || true
}

public_build() {
  local steam_output

  steam_output="$(
    cd /tmp
    runuser -u steam -- "$STEAMCMD_DIR/steamcmd.sh" \
      +login anonymous \
      +app_info_update 1 \
      +app_info_print "$APP_ID" \
      +quit 2>/dev/null || true
  )"

  printf '%s\n' "$steam_output" | awk -F\" '
    /"branches"/ { in_branches=1 }
    in_branches && /"public"/ { in_public=1 }
    in_public && /"buildid"/ { print $4; exit }
  '
}

wait_for_api() {
  local attempt

  for ((attempt = 1; attempt <= API_WAIT_ATTEMPTS; attempt++)); do
    if runuser -u steam -- "$API_BIN" GET /metrics >/dev/null 2>&1; then
      return 0
    fi
    sleep "$API_WAIT_SECONDS"
  done

  return 1
}

start_welcome_service() {
  if systemctl cat "$WELCOME_SERVICE_NAME" >/dev/null 2>&1; then
    systemctl start "$WELCOME_SERVICE_NAME" || log "Palworld recovered, but $WELCOME_SERVICE_NAME could not be started."
  fi
}

announce() {
  local message="$1"
  if systemctl is-active --quiet "$SERVICE_NAME" && [ -x "$ANNOUNCE_SCRIPT" ]; then
    runuser -u steam -- "$ANNOUNCE_SCRIPT" "$message" >/dev/null 2>&1 || log "Unable to send in-game announcement: $message"
  fi
}

online_player_count() {
  local payload

  if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    printf '0\n'
    return 0
  fi
  if ! payload="$(runuser -u steam -- "$API_BIN" GET /players 2>/dev/null)"; then
    return 1
  fi

  printf '%s' "$payload" | /usr/bin/python3 -c '
import json
import sys

payload = json.load(sys.stdin)
if isinstance(payload, list):
    players = payload
elif isinstance(payload, dict):
    players = payload.get("players", [])
else:
    players = []
print(len(players) if isinstance(players, (list, dict)) else 0)
' 2>/dev/null
}

schedule_retry() {
  local retry_unit="palworld-update-retry"

  if systemctl is-active --quiet "${retry_unit}.timer"; then
    return 0
  fi
  if /usr/bin/systemd-run \
    --quiet \
    --collect \
    --unit "$retry_unit" \
    --on-active="${RETRY_DELAY_SECONDS}s" \
    /usr/bin/systemctl start palworld-update.service; then
    return 0
  fi
  log "Unable to schedule the automatic update retry."
  return 1
}

write_defer_state() {
  local state="$1"
  printf '%s\n' "$state" > "$DEFER_STATE_FILE"
  chmod 0600 "$DEFER_STATE_FILE"
}

defer_update() {
  local reason="$1"
  local player_count="${2:-0}"
  local state="${TARGET_BUILD}:${reason}"
  local previous_state=""
  local retry_message="La mise à jour sera vérifiée de nouveau au prochain passage planifié."
  local message

  [ -r "$DEFER_STATE_FILE" ] && previous_state="$(cat "$DEFER_STATE_FILE")"
  if schedule_retry; then
    retry_message="Nouvelle tentative automatique dans $((RETRY_DELAY_SECONDS / 60)) minutes."
  fi

  if [ "$reason" = "players-online" ]; then
    message="Mise à jour ${CURRENT_BUILD} vers ${TARGET_BUILD} reportée: ${player_count} aventurier(s) sont encore en ligne. ${retry_message}"
  else
    message="Mise à jour ${CURRENT_BUILD} vers ${TARGET_BUILD} reportée: la présence des joueurs n'a pas pu être vérifiée. ${retry_message}"
  fi

  if [ "$previous_state" != "$state" ]; then
    emit_event "maintenance" "Maintenance reportée" "$message"
    announce "$message"
  fi
  write_defer_state "$state"
  log "$message"
}

player_gate_is_clear() {
  local count

  if [ "$DEFER_IF_PLAYERS" != "true" ]; then
    return 0
  fi
  if ! count="$(online_player_count)"; then
    defer_update "player-check-unavailable"
    return 1
  fi
  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    defer_update "player-check-unavailable"
    return 1
  fi
  if [ "$count" -gt 0 ]; then
    defer_update "players-online" "$count"
    return 1
  fi
  return 0
}

format_duration_fr() {
  local seconds="$1"
  if [ "$seconds" -eq 60 ]; then
    printf '1 minute'
  elif [ "$seconds" -gt 60 ] && [ $((seconds % 60)) -eq 0 ]; then
    printf '%d minutes' "$((seconds / 60))"
  elif [ "$seconds" -eq 1 ]; then
    printf '1 seconde'
  else
    printf '%d secondes' "$seconds"
  fi
}

run_countdown() {
  local -a steps
  local index remaining next sleep_seconds label message
  read -r -a steps <<< "$COUNTDOWN_STEPS"

  for ((index = 0; index < ${#steps[@]}; index++)); do
    remaining="${steps[$index]}"
    next=0
    if [ $((index + 1)) -lt "${#steps[@]}" ]; then
      next="${steps[$((index + 1))]}"
    fi
    label="$(format_duration_fr "$remaining")"
    message="Maintenance Palworld dans ${label}: sauvegarde du monde et installation de la build ${TARGET_BUILD}."
    emit_event "maintenance" "Maintenance dans ${label}" "$message"
    announce "$message"
    sleep_seconds=$((remaining - next))
    sleep "$sleep_seconds"
    if ! player_gate_is_clear; then
      return 1
    fi
  done
  return 0
}

recover_service_on_failure() {
  local exit_code=$?

  trap - EXIT
  if [ "$exit_code" -ne 0 ] && [ "$MAINTENANCE_ARMED" -eq 1 ]; then
    if [ "$UPDATE_INSTALLED" -eq 1 ]; then
      emit_event "maintenance" "Reprise incomplète" "La build ${TARGET_BUILD} est installée, mais la disponibilité complète de Palworld n'a pas pu être confirmée."
    elif [ "$UPDATE_WAS_ACTIVE" -eq 1 ] && ! systemctl is-active --quiet "$SERVICE_NAME"; then
      emit_event "maintenance" "Échec de la maintenance" "La mise à jour vers la build ${TARGET_BUILD} a échoué après l'arrêt du jeu. Une récupération automatique est en cours."
    else
      emit_event "maintenance" "Maintenance annulée" "Une étape de sécurité a échoué avant l'arrêt de Palworld. La build ${TARGET_BUILD} n'a pas été appliquée et l'aventure reste ouverte."
    fi
  fi
  if [ "$UPDATE_WAS_ACTIVE" -eq 1 ] && ! systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Update interrupted while Palworld was stopped; attempting automatic recovery."
    if systemctl start "$SERVICE_NAME" && wait_for_api; then
      emit_event "maintenance" "Aventure rétablie" "Palworld a été redémarré automatiquement après l'échec de la mise à jour."
      log "Palworld recovered after the failed update."
    else
      emit_event "maintenance" "Intervention requise" "Palworld n'a pas pu être rétabli automatiquement après l'échec de la mise à jour."
      log "Automatic Palworld recovery failed."
    fi
  fi

  exit "$exit_code"
}

main() {
  local check_only=0
  local installed=""
  local public=""
  local was_active=0
  local previous_state=""

  load_env
  validate_settings

  if [ "${1:-}" = "--check-only" ]; then
    check_only=1
  elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--check-only]" >&2
    exit 2
  fi

  if [ "$EUID" -ne 0 ]; then
    echo "This script must run as root." >&2
    exit 1
  fi

  prepare_maintenance_lock
  exec 9<"$MAINTENANCE_LOCK"
  if ! flock -n 9; then
    log "Another Palworld maintenance operation is active; update skipped."
    exit 75
  fi

  if [ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
    echo "SteamCMD is not installed at $STEAMCMD_DIR." >&2
    exit 1
  fi

  if [ ! -r "$MANIFEST_FILE" ]; then
    log "Installed build is unknown: manifest is not readable at $MANIFEST_FILE. Leaving Palworld untouched."
    exit 1
  fi

  installed="$(installed_build)"
  public="$(public_build)"
  CURRENT_BUILD="${installed:-unknown}"
  TARGET_BUILD="${public:-unknown}"

  if [ -z "$installed" ] || [ -z "$public" ]; then
    log "Build check failed (installed=${installed:-unknown}, public=${public:-unknown}). Leaving Palworld untouched."
    exit 1
  fi

  log "Build check: installed=$installed, Steam public=$public."
  if [ "$installed" = "$public" ]; then
    rm -f "$DEFER_STATE_FILE"
    log "Palworld is already up to date; no backup, stop, or restart is required."
    exit 0
  fi

  if [ "$check_only" -eq 1 ]; then
    log "Palworld update available: $installed -> $public. Check-only mode leaves the server untouched."
    exit 0
  fi

  MAINTENANCE_ARMED=1
  [ -r "$DEFER_STATE_FILE" ] && previous_state="$(cat "$DEFER_STATE_FILE")"
  if [[ "$previous_state" != "${public}:"* ]]; then
    emit_event "maintenance" "Mise à jour disponible" "Une nouvelle build Palworld est prête: ${installed} vers ${public}."
  fi
  log "Palworld update available: $installed -> $public."

  if ! player_gate_is_clear; then
    exit 0
  fi
  rm -f "$DEFER_STATE_FILE"

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    was_active=1
    UPDATE_WAS_ACTIVE=1
    if ! run_countdown; then
      exit 0
    fi
  fi

  if [ ! -x "$BACKUP_SCRIPT" ]; then
    log "Required pre-update backup script is unavailable. Leaving Palworld untouched."
    exit 1
  fi
  emit_event "maintenance" "Sauvegarde pré-maintenance" "Le monde est sauvegardé avant l'installation de la build ${public}."
  log "Requesting an in-game save and writing the required pre-update backup before stopping Palworld."
  if ! runuser -u steam -- env \
    PALWORLD_MAINTENANCE_LOCK_HELD=1 \
    PALWORLD_BACKUP_REQUIRE_WORLD_SAVE=1 \
    "$BACKUP_SCRIPT"; then
    log "Required pre-update backup failed. Leaving Palworld untouched."
    exit 1
  fi
  emit_event "maintenance" "Sauvegarde terminée" "La sauvegarde pré-maintenance est terminée."

  if ! player_gate_is_clear; then
    exit 0
  fi

  if [ "$was_active" -eq 1 ]; then
    log "Stopping $SERVICE_NAME for build $public."
    systemctl stop "$SERVICE_NAME"
    emit_event "maintenance" "Maintenance en cours" "Palworld est arrêté brièvement pour installer la build ${public}."
  fi

  log "Installing Palworld build $public via SteamCMD."
  runuser -u steam -- "$STEAMCMD_DIR/steamcmd.sh" \
    +force_install_dir "$GAME_DIR" \
    +login anonymous \
    +app_update "$APP_ID" validate \
    +quit
  UPDATE_INSTALLED=1

  if [ "$was_active" -eq 1 ]; then
    log "Restarting $SERVICE_NAME after update."
    systemctl start "$SERVICE_NAME"
    if wait_for_api; then
      start_welcome_service
    else
      log "Palworld started, but its REST API did not recover within the expected window."
      exit 1
    fi
  fi

  rm -f "$DEFER_STATE_FILE"
  emit_event "maintenance" "Maintenance terminée" "La build ${public} est installée et l'aventure est de nouveau ouverte."
  log "Update complete: installed build is now $(installed_build)."
}

trap recover_service_on_failure EXIT
main "$@"
