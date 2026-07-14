param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\stats.json")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

$outputItem = Get-Item -LiteralPath $OutputPath -ErrorAction SilentlyContinue
$outputDirectory = if ($outputItem -and $outputItem.PSIsContainer) {
    $outputItem.FullName
}
else {
    Split-Path -Parent $OutputPath
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$remotePath = "$($config.RemotePalworldRoot)/stats/stats.json"
$raw = & ssh.exe $config.SshAlias "test -s '$remotePath' && base64 -w0 '$remotePath'" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Remote stats file is not available yet: $remotePath"
}

$base64 = ($raw | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($base64)) {
    throw "Remote stats file is empty: $remotePath"
}

$text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
$null = $text | ConvertFrom-Json
$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
[System.IO.File]::WriteAllText($resolvedOutputPath, ($text.TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
Write-Host "Stats synced to $OutputPath"
