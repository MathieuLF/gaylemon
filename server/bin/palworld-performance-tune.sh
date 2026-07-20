#!/usr/bin/env bash
set -euo pipefail

for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  if [ -w "$governor" ]; then
    echo performance > "$governor"
  fi
done

sysctl -w vm.swappiness=5 >/dev/null

pids="$(pidof PalServer-Linux-Shipping 2>/dev/null || true)"
if [ -n "$pids" ]; then
  for pid in $pids; do
    renice -n -15 -p "$pid" >/dev/null || true
    ionice -c 2 -n 0 -p "$pid" >/dev/null || true
    printf '%s\n' -900 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
  done
fi

printf 'Palworld performance tuning applied.\n'
