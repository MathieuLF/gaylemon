param(
    [string]$DataDirectory = (Join-Path $PSScriptRoot "..\portal\data"),
    [string]$UptimeKumaBaseUrl = "",
    [string]$StatusPageSlug = "",
    [int]$MaxHeartbeatBars = 96
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $UptimeKumaBaseUrl) { $UptimeKumaBaseUrl = $config.UptimeKumaBaseUrl }
if (-not $StatusPageSlug) { $StatusPageSlug = $config.UptimeKumaStatusSlug }

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($property) {
        return $property.Value
    }

    return $null
}

function Convert-KumaStatus {
    param($Status)

    $statusCode = -1
    if ($null -ne $Status) {
        $statusCode = [int]$Status
    }

    switch ($statusCode) {
        0 { return "down" }
        1 { return "up" }
        2 { return "pending" }
        3 { return "maintenance" }
        default { return "unknown" }
    }
}

function Convert-KumaBeat {
    param($Beat)

    return [ordered]@{
        status = Convert-KumaStatus -Status $Beat.status
        statusCode = if ($null -ne $Beat.status) { [int]$Beat.status } else { $null }
        time = $Beat.time
        ping = if ($null -ne $Beat.ping) { [Math]::Round([double]$Beat.ping, 1) } else { $null }
        message = if ($Beat.msg) { [string]$Beat.msg } else { $null }
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($Path, ($json.TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
$outputPath = Join-Path $DataDirectory "public-uptime.json"
$now = Get-Date

try {
    $baseUrl = $UptimeKumaBaseUrl.TrimEnd("/")
    $statusUrl = "{0}/api/status-page/{1}" -f $baseUrl, $StatusPageSlug
    $heartbeatUrl = "{0}/api/status-page/heartbeat/{1}" -f $baseUrl, $StatusPageSlug

    $statusPage = Invoke-RestMethod -Uri $statusUrl -TimeoutSec 10
    $heartbeatPage = Invoke-RestMethod -Uri $heartbeatUrl -TimeoutSec 10

    $rawMonitors = @()
    foreach ($group in @($statusPage.publicGroupList)) {
        foreach ($monitor in @($group.monitorList)) {
            if ($null -ne $monitor) {
                $rawMonitors += $monitor
            }
        }
    }

    $monitors = @()
    foreach ($monitor in $rawMonitors) {
        $monitorId = [string]$monitor.id
        $uptimeKey = "{0}_24" -f $monitorId
        $uptime24h = Get-ObjectPropertyValue -Object $heartbeatPage.uptimeList -Name $uptimeKey
        $rawBeats = @(Get-ObjectPropertyValue -Object $heartbeatPage.heartbeatList -Name $monitorId)

        $beats = @($rawBeats | Select-Object -Last $MaxHeartbeatBars | ForEach-Object { Convert-KumaBeat -Beat $_ })
        $latest = if ($beats.Count -gt 0) { $beats[-1] } else { $null }

        $monitors += [ordered]@{
            id = [int]$monitor.id
            name = [string]$monitor.name
            type = [string]$monitor.type
            status = if ($latest) { $latest.status } else { "unknown" }
            statusCode = if ($latest) { $latest.statusCode } else { $null }
            lastHeartbeatAt = if ($latest) { $latest.time } else { $null }
            ping = if ($latest) { $latest.ping } else { $null }
            uptime24h = if ($null -ne $uptime24h) { [Math]::Round(([double]$uptime24h) * 100, 2) } else { $null }
            beats = $beats
        }
    }

    $total = $monitors.Count
    $up = @($monitors | Where-Object { $_.status -eq "up" }).Count
    $down = @($monitors | Where-Object { $_.status -eq "down" }).Count
    $maintenance = @($monitors | Where-Object { $_.status -eq "maintenance" }).Count
    $knownUptime = @($monitors | Where-Object { $null -ne $_.uptime24h } | ForEach-Object { [double]$_.uptime24h })
    $averageUptime = if ($knownUptime.Count -gt 0) {
        [Math]::Round((($knownUptime | Measure-Object -Average).Average), 2)
    }
    else {
        $null
    }

    $summaryStatus = if ($total -eq 0) {
        "unknown"
    }
    elseif ($down -gt 0) {
        "down"
    }
    elseif ($maintenance -gt 0) {
        "maintenance"
    }
    elseif ($up -eq $total) {
        "up"
    }
    else {
        "degraded"
    }

    $payload = [ordered]@{
        version = 1
        ok = $true
        source = "uptime-kuma"
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        title = $statusPage.config.title
        monitors = $monitors
        summary = [ordered]@{
            total = $total
            up = $up
            down = $down
            maintenance = $maintenance
            status = $summaryStatus
            uptime24hAverage = $averageUptime
        }
    }
}
catch {
    $payload = [ordered]@{
        version = 1
        ok = $false
        source = "uptime-kuma"
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        error = $_.Exception.Message
        monitors = @()
        summary = [ordered]@{
            total = 0
            up = 0
            down = 0
            maintenance = 0
            status = "unknown"
            uptime24hAverage = $null
        }
    }
}

Write-JsonFile -Path $outputPath -Payload $payload
Write-Host "Public uptime data exported to $outputPath"
