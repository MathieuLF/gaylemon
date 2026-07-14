$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

$remoteScript = @'
set -euo pipefail

manifest="__PALWORLD_ROOT__/game/steamapps/appmanifest_2394010.acf"

if [ ! -r "$manifest" ]; then
  printf 'Installed build: unknown\n'
  printf 'Steam public build: unknown\n'
  printf 'Status: unknown - manifest not readable: %s\n' "$manifest"
  exit 2
fi

installed="$(awk -F\" '/"buildid"/ {print $4; exit}' "$manifest")"
steam_output="$(cd /tmp && __STEAM_ROOT__/steamcmd/steamcmd.sh +login anonymous +app_info_update 1 +app_info_print 2394010 +quit 2>/dev/null || true)"
public="$(printf '%s\n' "$steam_output" | awk -F\" '
  /"branches"/ { in_branches=1 }
  in_branches && /"public"/ { in_public=1 }
  in_public && /"buildid"/ { print $4; exit }
')"

printf 'Installed build: %s\n' "${installed:-unknown}"
printf 'Steam public build: %s\n' "${public:-unknown}"

if [ -z "$public" ]; then
  printf 'Status: unknown - Steam did not return a public build\n'
  exit 2
elif [ "$installed" = "$public" ]; then
  printf 'Status: up to date\n'
else
  printf 'Status: update available\n'
fi
'@

$remoteScript = $remoteScript.Replace("__PALWORLD_ROOT__", $config.RemotePalworldRoot).Replace("__STEAM_ROOT__", $config.RemoteSteamRoot)

$encodedScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remoteScript))
& ssh.exe $config.SshAlias "printf '%s' '$encodedScript' | base64 -d | bash"
exit $LASTEXITCODE
