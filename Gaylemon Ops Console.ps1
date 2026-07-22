param(
    [ValidateSet(
        "Menu",
        "CheckAccess",
        "Status",
        "Metrics",
        "Stats",
        "RefreshStats",
        "Players",
        "Version",
        "Logs",
        "Announce",
        "Backup",
        "ListBackups",
        "Update",
        "Restart",
        "RestartWelcome",
        "ApiTunnelStatus",
        "StartApiTunnel",
        "StopApiTunnel",
        "StartLocalServices",
        "StopLocalServices",
        "StartupStatus",
        "InstallWindowsStartup",
        "UninstallWindowsStartup",
        "OpenMicrosite",
        "RefreshMetrics",
        "ValidateRepository",
        "DiagnoseIntegrations",
        "PreviewUbuntuDeploy",
        "StageUbuntuDeploy",
        "InstallUbuntuDeploy",
        "AuditUbuntuSource",
        "MaintenanceOverview"
    )]
    [string]$Action = "Menu",

    [ValidateSet("service", "game", "update", "backup", "welcome")]
    [string]$LogMode = "service",

    [int]$Lines = 120,

    [switch]$Follow,

    [switch]$NoEmoji,

    [string]$Message
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Older PowerShell hosts may not allow changing the console encoding.
}

$consoleScript = Join-Path $PSScriptRoot "scripts\palworld-console.ps1"

$arguments = @{
    Action = $Action
    LogMode = $LogMode
    Lines = $Lines
}

if ($Follow) {
    $arguments.Follow = $true
}

if ($NoEmoji) {
    $arguments.NoEmoji = $true
}

if (-not [string]::IsNullOrWhiteSpace($Message)) {
    $arguments.Message = $Message
}

& $consoleScript @arguments
