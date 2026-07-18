Set-StrictMode -Version 2.0

function Read-GaylemonEnvFile {
    param([Parameter(Mandatory = $true)] [string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }

    foreach ($rawLine in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $separator = $line.IndexOf("=")
        if ($separator -lt 1) {
            throw "Ligne .env invalide dans ${Path}: $rawLine"
        }

        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Nom de variable .env invalide dans ${Path}: $name"
        }

        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        $values[$name] = $value
    }

    return $values
}

function Get-GaylemonSetting {
    param(
        [Parameter(Mandatory = $true)] [hashtable]$FileValues,
        [Parameter(Mandatory = $true)] [string]$Name,
        [AllowEmptyString()] [string]$Default = ""
    )

    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($null -ne $processValue) {
        return $processValue
    }
    if ($FileValues.ContainsKey($Name)) {
        return [string]$FileValues[$Name]
    }
    return $Default
}

function ConvertTo-GaylemonInt {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [string]$Value,
        [int]$Minimum = 1,
        [int]$Maximum = [int]::MaxValue
    )

    $parsed = 0
    if (-not [int]::TryParse($Value, [ref]$parsed) -or $parsed -lt $Minimum -or $parsed -gt $Maximum) {
        throw "$Name doit etre un entier entre $Minimum et $Maximum. Valeur recue: '$Value'."
    }
    return $parsed
}

function Get-GaylemonConfig {
    param([string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path)

    $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectRoot)
    $fileValues = Read-GaylemonEnvFile -Path (Join-Path $resolvedRoot ".env")

    $remoteSteamRoot = (Get-GaylemonSetting $fileValues "GAYLEMON_REMOTE_STEAM_ROOT" "/srv/storage/steam").TrimEnd("/")
    $remoteProjectRoot = (Get-GaylemonSetting $fileValues "GAYLEMON_REMOTE_PROJECT_ROOT" "/home/palworld/Gaylemon").TrimEnd("/")
    $remoteProjectUserDefault = if ($remoteProjectRoot -match '^/home/([^/]+)/') { $Matches[1] } else { "palworld" }
    $remoteProjectUser = Get-GaylemonSetting $fileValues "GAYLEMON_REMOTE_PROJECT_USER" $remoteProjectUserDefault
    $micrositePort = ConvertTo-GaylemonInt "GAYLEMON_MICROSITE_PORT" (Get-GaylemonSetting $fileValues "GAYLEMON_MICROSITE_PORT" "8787") 1 65535
    $apiLocalPort = ConvertTo-GaylemonInt "GAYLEMON_API_LOCAL_PORT" (Get-GaylemonSetting $fileValues "GAYLEMON_API_LOCAL_PORT" "8212") 1 65535
    $apiRemotePort = ConvertTo-GaylemonInt "GAYLEMON_API_REMOTE_PORT" (Get-GaylemonSetting $fileValues "GAYLEMON_API_REMOTE_PORT" "8212") 1 65535
    $apiTunnelMode = (Get-GaylemonSetting $fileValues "GAYLEMON_API_TUNNEL_MODE" "docker").ToLowerInvariant()
    if ($apiTunnelMode -notin @("docker", "windows-ssh")) {
        throw "GAYLEMON_API_TUNNEL_MODE doit valoir 'docker' ou 'windows-ssh'. Valeur recue: '$apiTunnelMode'."
    }
    $defaultSshDirectory = Join-Path $HOME ".ssh"
    $sshDirectory = Get-GaylemonSetting $fileValues "GAYLEMON_SSH_DIR" $defaultSshDirectory
    if ([string]::IsNullOrWhiteSpace($sshDirectory)) {
        $sshDirectory = $defaultSshDirectory
    }
    $sshDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($sshDirectory)
    $gamePort = ConvertTo-GaylemonInt "GAYLEMON_GAME_PORT" (Get-GaylemonSetting $fileValues "GAYLEMON_GAME_PORT" "8211") 1 65535
    $metricInterval = ConvertTo-GaylemonInt "GAYLEMON_METRIC_INTERVAL_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_METRIC_INTERVAL_SECONDS" "20") 5 3600
    $eventSyncInterval = ConvertTo-GaylemonInt "GAYLEMON_EVENT_SYNC_INTERVAL_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_EVENT_SYNC_INTERVAL_SECONDS" "20") 5 3600
    $eventSyncTimeout = ConvertTo-GaylemonInt "GAYLEMON_EVENT_SYNC_TIMEOUT_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_EVENT_SYNC_TIMEOUT_SECONDS" "60") 15 3600
    $saveSnapshotSyncInterval = ConvertTo-GaylemonInt "GAYLEMON_SAVE_SNAPSHOT_SYNC_INTERVAL_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_SAVE_SNAPSHOT_SYNC_INTERVAL_SECONDS" "60") 15 3600
    $saveSnapshotSyncTimeout = ConvertTo-GaylemonInt "GAYLEMON_SAVE_SNAPSHOT_SYNC_TIMEOUT_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_SAVE_SNAPSHOT_SYNC_TIMEOUT_SECONDS" "180") 60 3600
    $metricUpdateTimeout = ConvertTo-GaylemonInt "GAYLEMON_METRIC_UPDATE_TIMEOUT_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_METRIC_UPDATE_TIMEOUT_SECONDS" "120") 30 3600
    $uptimeKumaMonitorId = ConvertTo-GaylemonInt "GAYLEMON_UPTIME_KUMA_MONITOR_ID" (Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_MONITOR_ID" "1") 1 ([int]::MaxValue)
    $uptimeHistoryDays = ConvertTo-GaylemonInt "GAYLEMON_UPTIME_HISTORY_DAYS" (Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_HISTORY_DAYS" "90") 1 3650
    $recoveryStaleSeconds = ConvertTo-GaylemonInt "GAYLEMON_RECOVERY_STALE_SECONDS" (Get-GaylemonSetting $fileValues "GAYLEMON_RECOVERY_STALE_SECONDS" "90") 30 86400

    return [pscustomobject][ordered]@{
        ProjectRoot = $resolvedRoot
        EnvPath = Join-Path $resolvedRoot ".env"
        SshAlias = Get-GaylemonSetting $fileValues "GAYLEMON_SSH_ALIAS" "palworld"
        SshDirectory = $sshDirectory
        ServerLanIp = Get-GaylemonSetting $fileValues "GAYLEMON_SERVER_LAN_IP" ""
        RemoteProjectRoot = $remoteProjectRoot
        RemoteProjectUser = $remoteProjectUser
        RemoteSteamRoot = $remoteSteamRoot
        RemotePalworldRoot = "$remoteSteamRoot/servers/palworld"
        MicrositePort = $micrositePort
        MicrositeOriginUrl = "http://127.0.0.1:$micrositePort/"
        MicrositePublicUrl = Get-GaylemonSetting $fileValues "GAYLEMON_MICROSITE_PUBLIC_URL" "http://127.0.0.1:$micrositePort/"
        MetricIntervalSeconds = $metricInterval
        EventSyncIntervalSeconds = $eventSyncInterval
        EventSyncTimeoutSeconds = $eventSyncTimeout
        SaveSnapshotSyncIntervalSeconds = $saveSnapshotSyncInterval
        SaveSnapshotSyncTimeoutSeconds = $saveSnapshotSyncTimeout
        DockerMicrositeContainer = Get-GaylemonSetting $fileValues "GAYLEMON_DOCKER_MICROSITE_CONTAINER" "gaylemon-microsite"
        ApiLocalPort = $apiLocalPort
        ApiRemotePort = $apiRemotePort
        ApiTunnelMode = $apiTunnelMode
        MetricUpdateTimeoutSeconds = $metricUpdateTimeout
        UptimeKumaBaseUrl = (Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_BASE_URL" "").TrimEnd("/")
        UptimeKumaStatusSlug = Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_STATUS_SLUG" "palworld"
        UptimeKumaPublicUrl = Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_PUBLIC_URL" ""
        UptimeKumaApiKey = Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_API_KEY" ""
        UptimeKumaContainer = Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_CONTAINER" "uptime-kuma"
        UptimeKumaDbPath = Get-GaylemonSetting $fileValues "GAYLEMON_UPTIME_KUMA_DB_PATH" "/app/data/kuma.db"
        UptimeKumaMonitorId = $uptimeKumaMonitorId
        UptimeHistoryDays = $uptimeHistoryDays
        RecoveryStaleSeconds = $recoveryStaleSeconds
        CloudflaredContainerPattern = Get-GaylemonSetting $fileValues "GAYLEMON_CLOUDFLARED_CONTAINER_PATTERN" "cloudflared"
        GameHost = Get-GaylemonSetting $fileValues "GAYLEMON_GAME_HOST" "palworld.example.com"
        GamePort = $gamePort
        DiscordUrl = Get-GaylemonSetting $fileValues "GAYLEMON_DISCORD_URL" ""
        GithubUrl = Get-GaylemonSetting $fileValues "GAYLEMON_GITHUB_URL" ""
        Ga4Id = Get-GaylemonSetting $fileValues "GAYLEMON_GA4_ID" ""
        SaveToolsUpstream = Get-GaylemonSetting $fileValues "GAYLEMON_SAVE_TOOLS_UPSTREAM" "deafdudecomputers/PalworldSaveTools"
        SaveToolsFork = Get-GaylemonSetting $fileValues "GAYLEMON_SAVE_TOOLS_FORK" "UTILISATEUR/PalworldSaveTools"
        StartupTaskName = Get-GaylemonSetting $fileValues "GAYLEMON_STARTUP_TASK_NAME" "Gaylemon Ops Local Services"
        SaveToolsTaskName = Get-GaylemonSetting $fileValues "GAYLEMON_SAVE_TOOLS_TASK_NAME" "Gaylemon PalworldSaveTools Maintenance"
    }
}
