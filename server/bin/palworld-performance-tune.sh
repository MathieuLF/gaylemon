#!/usr/bin/env bash
set -euo pipefail

for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  if [ -w "$governor" ]; then
    echo performance > "$governor"
  fi
done

sysctl -w vm.swappiness=5 >/dev/null
sysctl -w net.core.rmem_max=16777216 >/dev/null
sysctl -w net.core.rmem_default=4194304 >/dev/null
sysctl -w net.core.wmem_max=16777216 >/dev/null
sysctl -w net.core.wmem_default=1048576 >/dev/null
sysctl -w net.core.netdev_max_backlog=5000 >/dev/null
sysctl -w net.ipv4.udp_rmem_min=8192 >/dev/null
sysctl -w net.ipv4.udp_wmem_min=8192 >/dev/null
ip link set dev eno1 txqueuelen 5000 2>/dev/null || true

pids="$(pidof PalServer-Linux-Shipping 2>/dev/null || true)"
if [ -n "$pids" ]; then
  for pid in $pids; do
    renice -n -15 -p "$pid" >/dev/null || true
    ionice -c 2 -n 0 -p "$pid" >/dev/null || true
    printf '%s\n' -900 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
  done
fi

printf 'Palworld performance tuning applied.\n'
