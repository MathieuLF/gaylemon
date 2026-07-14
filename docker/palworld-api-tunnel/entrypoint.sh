#!/bin/sh
set -eu

SSH_ALIAS="${GAYLEMON_SSH_ALIAS:-palworld}"
LOCAL_PORT="${GAYLEMON_API_LOCAL_PORT:-8212}"
REMOTE_PORT="${GAYLEMON_API_REMOTE_PORT:-8212}"

case "$LOCAL_PORT:$REMOTE_PORT" in
  *[!0-9:]* | :* | *: | *::*)
    echo "Invalid tunnel ports: local=$LOCAL_PORT remote=$REMOTE_PORT" >&2
    exit 64
    ;;
esac

if [ ! -d /ssh-src ]; then
  echo "Missing SSH source directory mounted at /ssh-src." >&2
  exit 66
fi

rm -rf /root/.ssh
mkdir -p /root/.ssh
cp -R /ssh-src/. /root/.ssh/
chmod 700 /root/.ssh
find /root/.ssh -type d -exec chmod 700 {} \;
find /root/.ssh -type f -exec chmod 600 {} \;
find /root/.ssh -type f -name "*.pub" -exec chmod 644 {} \;
touch /root/.ssh/known_hosts
chmod 600 /root/.ssh/known_hosts

exec ssh \
  -N \
  -o BatchMode=yes \
  -o ConnectTimeout=15 \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new \
  -L "0.0.0.0:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  "$SSH_ALIAS"
