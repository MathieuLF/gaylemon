Set-StrictMode -Version 2.0

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
            Destination = $destination
            Owner = $owner
            Group = $group
            Mode = [string]$entry.mode
            Validation = [string]$entry.validation
            RestartUnit = if ($null -eq $entry.restartUnit) { "" } else { [string]$entry.restartUnit }
            RestartPolicy = [string]$entry.restartPolicy
        })
    }

    return [pscustomobject][ordered]@{
        Version = [int]$manifest.version
        BackupRoot = [string]$manifest.backupRoot
        Entries = @($entries)
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
                destination = $_.Destination
                owner = $_.Owner
                group = $_.Group
                mode = $_.Mode
                validation = $_.Validation
                restartUnit = if ($_.RestartUnit) { $_.RestartUnit } else { $null }
                restartPolicy = $_.RestartPolicy
            }
        })
    }

    $json = $payload | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($OutputPath, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
