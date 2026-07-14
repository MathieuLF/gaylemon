param(
    [ValidateSet("service", "game", "update", "backup", "welcome", "kuma")]
    [string]$Mode = "service",

    [int]$Lines = 120,

    [switch]$Follow
)

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

$safeLines = [Math]::Max(1, [Math]::Min(5000, $Lines))
$followValue = if ($Follow) { "1" } else { "0" }

$remoteScript = @"
set -uo pipefail

mode="$Mode"
lines="$safeLines"
follow="$followValue"

show_journal() {
  local unit="`$1"
  if [ "`$follow" = "1" ]; then
    journalctl -u "`$unit" -n "`$lines" -f -o short-iso
  else
    journalctl -u "`$unit" -n "`$lines" --no-pager -o short-iso
  fi
}

case "`$mode" in
  service)
    show_journal palworld.service
    ;;
  game)
    logs_dir="__PALWORLD_ROOT__/game/Pal/Saved/Logs"
    log_file=""
    if [ -d "`$logs_dir" ]; then
      log_file="`$(find "`$logs_dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.txt' \) -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print; exit }')"
    fi

    if [ -n "`$log_file" ] && [ -r "`$log_file" ]; then
      printf 'Game log file: %s\n' "`$log_file"
      if [ "`$follow" = "1" ]; then
        tail -n "`$lines" -f "`$log_file"
      else
        tail -n "`$lines" "`$log_file"
      fi
    else
      printf 'Aucun fichier Palworld dans %s; repli vers journalctl palworld.service.\n' "`$logs_dir"
      show_journal palworld.service
    fi
    ;;
  update)
    show_journal palworld-update.service
    ;;
  backup)
    show_journal palworld-backup.service
    ;;
  welcome)
    show_journal palworld-welcome.service
    ;;
  kuma)
    show_journal palworld-kuma-push.service
    ;;
esac
"@

$remoteScript = $remoteScript.Replace("__PALWORLD_ROOT__", $config.RemotePalworldRoot)

$encodedScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remoteScript))
& ssh.exe $config.SshAlias "printf '%s' '$encodedScript' | base64 -d | bash"
exit $LASTEXITCODE
