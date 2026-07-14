#!/usr/bin/env bash
set -euo pipefail

ROOT="/srv/storage/steam"
ENV_FILE="/etc/palworld/palworld.env"
GAME_DIR="$ROOT/servers/palworld/game"
CANONICAL_CONFIG="$ROOT/servers/palworld/config/PalWorldSettings.ini"
TARGET_CONFIG="$GAME_DIR/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"

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

sync_config() {
  if [ -f "$CANONICAL_CONFIG" ]; then
    mkdir -p "$(dirname "$TARGET_CONFIG")"
    install -m 0644 "$CANONICAL_CONFIG" "$TARGET_CONFIG"
  fi
}

main() {
  load_env
  sync_config

  if [ ! -x "$GAME_DIR/PalServer.sh" ]; then
    log "Palworld is not installed yet. Run the update/install step after the 1.0 release."
    exit 0
  fi

  export SteamAppId=2394010
  cd "$GAME_DIR"
  exec ./PalServer.sh ${PALWORLD_ARGS:--port=8211 -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS -logformat=text}
}

main "$@"
