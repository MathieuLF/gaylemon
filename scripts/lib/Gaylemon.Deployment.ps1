Set-StrictMode -Version 2.0

function Build-GaylemonLinuxAgent {
    param([Parameter(Mandatory = $true)] [string]$ProjectRoot)

    $go = Get-Command go -ErrorAction Stop
    $agentBuildRoot = Join-Path $ProjectRoot "server\build"
    $agentBinary = Join-Path $agentBuildRoot "gaylemon"
    New-Item -ItemType Directory -Path $agentBuildRoot -Force | Out-Null
    $previousGoOS = $env:GOOS
    $previousGoArch = $env:GOARCH
    $previousCgo = $env:CGO_ENABLED
    $previousGoFlags = $env:GOFLAGS
    Push-Location $ProjectRoot
    try {
        $env:GOOS = "linux"
        $env:GOARCH = "amd64"
        $env:CGO_ENABLED = "0"
        $env:GOFLAGS = "-mod=mod"
        & $go.Source build -trimpath -ldflags "-s -w" -o $agentBinary .\cmd\gaylemon
        if ($LASTEXITCODE -ne 0) { throw "Compilation Linux de l'agent impossible." }
    }
    finally {
        Pop-Location
        $env:GOOS = $previousGoOS
        $env:GOARCH = $previousGoArch
        $env:CGO_ENABLED = $previousCgo
        $env:GOFLAGS = $previousGoFlags
    }
    return $agentBinary
}

function Get-GaylemonDeploymentManifest {
    param(
        [Parameter(Mandatory = $true)] [string]$ProjectRoot,
        [Parameter(Mandatory = $true)] [psobject]$Config
    )

    $manifestPath = Join-Path $ProjectRoot "server\deployment-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Manifeste de deploiement absent: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.version -ne 1) {
        throw "Version de manifeste non prise en charge: $($manifest.version)"
    }

    $entries = [Collections.Generic.List[object]]::new()
    $sources = @{}
    $destinations = @{}
    foreach ($entry in @($manifest.entries)) {
        $source = ([string]$entry.source).Replace("\", "/")
        $destination = ([string]$entry.destination).
            Replace("{{REMOTE_PROJECT_ROOT}}", [string]$Config.RemoteProjectRoot).
            Replace("{{REMOTE_STEAM_ROOT}}", [string]$Config.RemoteSteamRoot)
        $owner = ([string]$entry.owner).Replace("{{REMOTE_PROJECT_USER}}", [string]$Config.RemoteProjectUser)
        $group = ([string]$entry.group).Replace("{{REMOTE_PROJECT_USER}}", [string]$Config.RemoteProjectUser)

        if (-not $source.StartsWith("server/", [StringComparison]::Ordinal)) {
            throw "Source hors du repertoire server: $source"
        }
        if (-not $destination.StartsWith("/", [StringComparison]::Ordinal)) {
            throw "Destination distante non absolue: $destination"
        }
        if ($sources.ContainsKey($source)) {
            throw "Source dupliquee dans le manifeste: $source"
        }
        if ($destinations.ContainsKey($destination)) {
            throw "Destination dupliquee dans le manifeste: $destination"
        }

        $localPath = Join-Path $ProjectRoot ($source.Replace("/", "\"))
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "Source du manifeste absente: $source"
        }

        $sources[$source] = $true
        $destinations[$destination] = $true
        $entries.Add([pscustomobject][ordered]@{
            Source = $source
            LocalPath = (Resolve-Path -LiteralPath $localPath).Path
            Sha256 = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash.ToLowerInvariant()
            Destination = $destination
            Owner = $owner
            Group = $group
            Mode = [string]$entry.mode
            Validation = [string]$entry.validation
            RestartUnit = if ($null -eq $entry.restartUnit) { "" } else { [string]$entry.restartUnit }
            RestartPolicy = [string]$entry.restartPolicy
        })
    }

    $removals = [Collections.Generic.List[object]]::new()
    $removalPaths = @{}
    foreach ($removal in @($manifest.removals)) {
        $path = ([string]$removal.path).
            Replace("{{REMOTE_PROJECT_ROOT}}", [string]$Config.RemoteProjectRoot).
            Replace("{{REMOTE_STEAM_ROOT}}", [string]$Config.RemoteSteamRoot)
        if (-not $path.StartsWith("/", [StringComparison]::Ordinal)) {
            throw "Suppression distante non absolue: $path"
        }
        if ($destinations.ContainsKey($path)) {
            throw "Suppression en conflit avec une destination livree: $path"
        }
        if ($removalPaths.ContainsKey($path)) {
            throw "Suppression dupliquee dans le manifeste: $path"
        }
        $removalPaths[$path] = $true
        $removals.Add([pscustomobject][ordered]@{
            Path = $path
            Kind = [string]$removal.kind
            Unit = if ($null -eq $removal.unit) { "" } else { [string]$removal.unit }
            Reason = [string]$removal.reason
        })
    }

    return [pscustomobject][ordered]@{
        Version = [int]$manifest.version
        BackupRoot = [string]$manifest.backupRoot
        Entries = @($entries)
        Removals = @($removals)
        SourcePath = $manifestPath
    }
}

function New-GaylemonResolvedDeploymentManifest {
    param(
        [Parameter(Mandatory = $true)] [psobject]$Manifest,
        [Parameter(Mandatory = $true)] [string]$OutputPath
    )

    $payload = [ordered]@{
        version = $Manifest.Version
        backupRoot = $Manifest.BackupRoot
        entries = @($Manifest.Entries | ForEach-Object {
            [ordered]@{
                source = $_.Source
                sha256 = $_.Sha256
                destination = $_.Destination
                owner = $_.Owner
                group = $_.Group
                mode = $_.Mode
                validation = $_.Validation
                restartUnit = if ($_.RestartUnit) { $_.RestartUnit } else { $null }
                restartPolicy = $_.RestartPolicy
            }
        })
        removals = @($Manifest.Removals | ForEach-Object {
            [ordered]@{
                path = $_.Path
                kind = $_.Kind
                unit = if ($_.Unit) { $_.Unit } else { $null }
                reason = $_.Reason
            }
        })
    }

    $json = $payload | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($OutputPath, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
