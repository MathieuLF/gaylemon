#!/usr/bin/env bash
set -euo pipefail

ROOT="/srv/storage/steam"
STEAM_USER="steam"
STEAMCMD_DIR="$ROOT/steamcmd"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
PKGS=(
  ca-certificates
  curl
  jq
  libc6-i386
  lib32gcc-s1
  lib32stdc++6
  rsync
  tar
  unzip
  zstd
)

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Run this script as root." >&2
    exit 1
  fi
}

ensure_user() {
  if ! id "$STEAM_USER" >/dev/null 2>&1; then
    useradd -r -m -d "$ROOT" -s /usr/sbin/nologin "$STEAM_USER"
  fi
}

install_packages() {
  log "Installing SteamCMD runtime dependencies."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"
}

install_steamcmd() {
  mkdir -p "$STEAMCMD_DIR"

  if [ ! -x "$STEAMCMD_DIR/steamcmd.sh" ]; then
    log "Downloading SteamCMD."
    tmpdir="$(mktemp -d)"
    curl -fsSL "$STEAMCMD_URL" -o "$tmpdir/steamcmd_linux.tar.gz"
    tar -xzf "$tmpdir/steamcmd_linux.tar.gz" -C "$STEAMCMD_DIR"
    rm -rf "$tmpdir"
  fi

  chown -R "$STEAM_USER:$STEAM_USER" "$STEAMCMD_DIR"
}

prime_steamcmd() {
  log "Priming SteamCMD as the steam user."
  runuser -u "$STEAM_USER" -- "$STEAMCMD_DIR/steamcmd.sh" +quit || true
}

main() {
  require_root
  install_packages
  ensure_user
  install_steamcmd
  prime_steamcmd
  log "SteamCMD installation complete."
}

main "$@"
