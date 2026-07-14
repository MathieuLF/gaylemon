#!/usr/bin/env bash
set -euo pipefail

for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  if [ -w "$governor" ]; then
    echo performance > "$governor"
  fi
done

sysctl -w vm.swappiness=10 >/dev/null

pid="$(pidof PalServer-Linux-Shipping 2>/dev/null || true)"
if [ -n "$pid" ]; then
  renice -n -10 -p "$pid" >/dev/null || true
  ionice -c 2 -n 0 -p "$pid" >/dev/null || true
fi

printf 'Palworld performance tuning applied.\n'
