#!/bin/sh
set -eu

SSH_ALIAS="${GAYLEMON_SSH_ALIAS:-palworld}"
LOCAL_PORT="${GAYLEMON_API_LOCAL_PORT:-8212}"
REMOTE_PORT="${GAYLEMON_API_REMOTE_PORT:-8212}"

validate_port() {
  name="$1"
  value="$2"

  case "$value" in
    "" | *[!0-9]* | ??????*)
      echo "Invalid $name tunnel port: $value" >&2
      exit 64
      ;;
  esac

  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    echo "Invalid $name tunnel port: $value" >&2
    exit 64
  fi
}

validate_port "local" "$LOCAL_PORT"
validate_port "remote" "$REMOTE_PORT"

case "$SSH_ALIAS" in
  "" | -* | *[!A-Za-z0-9._@:-]*)
    echo "Invalid SSH alias for API tunnel: $SSH_ALIAS" >&2
    exit 64
    ;;
esac

if [ ! -d /ssh-src ]; then
  echo "Missing SSH source directory mounted at /ssh-src." >&2
  exit 66
fi

ssh_directory="${HOME}/.ssh"
rm -rf "$ssh_directory"
mkdir -p "$ssh_directory"
cp -R /ssh-src/. "$ssh_directory"/
chmod 700 "$ssh_directory"
find "$ssh_directory" -type d -exec chmod 700 {} \;
find "$ssh_directory" -type f -exec chmod 600 {} \;
find "$ssh_directory" -type f -name "*.pub" -exec chmod 644 {} \;
touch "$ssh_directory/known_hosts"
chmod 600 "$ssh_directory/known_hosts"

exec ssh \
  -N \
  -o BatchMode=yes \
  -o ConnectTimeout=15 \
  -o ExitOnForwardFailure=yes \
  -o ForwardAgent=no \
  -o ForwardX11=no \
  -o PermitLocalCommand=no \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new \
  -L "0.0.0.0:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  "$SSH_ALIAS"
