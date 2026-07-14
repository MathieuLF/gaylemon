$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

$remoteScript = @'
set -uo pipefail

systemctl status palworld.service palworld-welcome.service palworld-performance.service --no-pager -l || true
echo
printf 'CPU governor: '
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || printf 'n/a'
echo
printf 'vm.swappiness: '
sysctl -n vm.swappiness
printf 'PalServer priority: '
pgrep -f 'PalServer-Linux-Shipping' | head -n 1 | xargs -r ps -o ni=,pri= -p
echo
systemctl list-timers palworld-backup.timer palworld-update.timer palworld-kuma-push.timer palworld-stats.timer --no-pager
echo
ss -lunp | grep -E ':(8211|27015)\b' || true
'@

$encodedScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remoteScript))
& ssh.exe $config.SshAlias "printf '%s' '$encodedScript' | base64 -d | bash"
exit $LASTEXITCODE
