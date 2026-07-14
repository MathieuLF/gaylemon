param(
    [ValidateSet("info", "players", "metrics", "settings", "game-data")]
    [string]$Endpoint = "info"
)

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

& ssh.exe $config.SshAlias "$($config.RemoteSteamRoot)/bin/palworld-api.sh GET /$Endpoint"
exit $LASTEXITCODE
