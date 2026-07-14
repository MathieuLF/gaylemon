param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Message
)

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

$text = ($Message -join " ").Trim()
if (-not $text) {
    Write-Error "Le message ne peut pas etre vide."
    exit 1
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
$encoded = [Convert]::ToBase64String($bytes)

& ssh.exe $config.SshAlias "$($config.RemoteSteamRoot)/bin/palworld-announce.sh --base64 $encoded"
exit $LASTEXITCODE
