param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("v5", "v6")]
    [string]$ActiveContract,

    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label est absent. La promotion est annulée."
    }

    try {
        $payload = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "$Label ne contient pas un JSON valide. La promotion est annulée."
    }

    if ($null -eq $payload -or $payload -is [array]) {
        throw "$Label ne contient pas un objet JSON valide. La promotion est annulée."
    }
    return $payload
}

function Assert-V6Document {
    param(
        [Parameter(Mandatory)] $Payload,
        [Parameter(Mandatory)] [string]$Label
    )

    $schemaProperty = $Payload.PSObject.Properties["schemaVersion"]
    $okProperty = $Payload.PSObject.Properties["ok"]
    if ($null -eq $schemaProperty -or [int]$schemaProperty.Value -ne 6 -or
        $null -eq $okProperty -or $okProperty.Value -ne $true) {
        throw "$Label ne respecte pas le contrat v6. La promotion est annulée."
    }
}

function Get-RequiredNonNegativeLong {
    param(
        [Parameter(Mandatory)] $Payload,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Label
    )

    $property = $Payload.PSObject.Properties[$Name]
    $value = 0L
    if ($null -eq $property -or
        -not [long]::TryParse([string]$property.Value, [ref]$value) -or
        $value -lt 0) {
        throw "$Label n'expose pas un compte '$Name' valide. La promotion est annulée."
    }
    return $value
}

function Get-CanonicalSha256 {
    param(
        [Parameter(Mandatory)] [string]$Value,
        [Parameter(Mandatory)] [string]$Label
    )

    if ($Value -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw "$Label n'expose pas une empreinte SHA-256 valide. La promotion est annulée."
    }
    return "sha256:" + $Matches[1].ToLowerInvariant()
}

function Assert-FileSha256 {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Expected,
        [Parameter(Mandatory)] [string]$Label
    )

    $expectedHash = Get-CanonicalSha256 -Value $Expected -Label $Label
    $actualHash = "sha256:" + (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "L'empreinte de $Label ne correspond pas au fichier publié. La promotion est annulée."
    }
}

function Resolve-PortalArtifactPath {
    param(
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [string]$RequiredPrefix,
        [Parameter(Mandatory)] [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('\') -or
        -not $RelativePath.StartsWith($RequiredPrefix, [StringComparison]::Ordinal)) {
        throw "Le chemin de $Label sort du répertoire public autorisé. La promotion est annulée."
    }

    $segments = @($RelativePath.Split('/'))
    if ($segments.Count -lt 2 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "Le chemin de $Label n'est pas canonique. La promotion est annulée."
    }

    $candidate = [IO.Path]::GetFullPath((Join-Path $script:PortalRoot ($RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))))
    $portalPrefix = $script:PortalRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($portalPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Le chemin de $Label sort du portail. La promotion est annulée."
    }
    return $candidate
}

function Assert-GenerationId {
    param(
        [Parameter(Mandatory)] [string]$Value,
        [Parameter(Mandatory)] [string]$Label
    )

    if ($Value -notmatch '^[A-Za-z0-9._-]+$') {
        throw "$Label n'expose pas une génération valide. La promotion est annulée."
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
}
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "La racine du projet est absente: $ProjectRoot"
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$script:PortalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot "portal"))
if (-not (Test-Path -LiteralPath $script:PortalRoot -PathType Container)) {
    throw "Le répertoire portal est absent."
}

$channelPath = Join-Path $script:PortalRoot "public-events-channel.json"

if ($ActiveContract -eq "v6") {
    $pointerPath = Join-Path $script:PortalRoot "data\public-events-head-v6.json"
    $pointer = Read-JsonFile -Path $pointerPath -Label "Le pointeur v6"
    Assert-V6Document -Payload $pointer -Label "Le pointeur v6"

    $generationId = [string]$pointer.baseGenerationId
    Assert-GenerationId -Value $generationId -Label "Le pointeur v6"
    if ([string]::IsNullOrWhiteSpace([string]$pointer.revision)) {
        throw "Le pointeur v6 n'expose pas de révision. La promotion est annulée."
    }

    $expectedManifest = "data/public-events-v6/$generationId/manifest.json"
    if ([string]$pointer.manifest.path -ne $expectedManifest) {
        throw "Le manifeste v6 ne correspond pas à la génération active."
    }
    $manifestPath = Resolve-PortalArtifactPath -RelativePath ([string]$pointer.manifest.path) -RequiredPrefix "data/public-events-v6/" -Label "le manifeste v6"
    $manifest = Read-JsonFile -Path $manifestPath -Label "Le manifeste immuable v6"
    Assert-FileSha256 -Path $manifestPath -Expected ([string]$pointer.manifest.sha256) -Label "le manifeste immuable v6"
    Assert-V6Document -Payload $manifest -Label "Le manifeste immuable v6"
    if ([string]$manifest.generationId -ne $generationId) {
        throw "Le manifeste immuable v6 n'appartient pas à la génération active."
    }

    $expectedHead = "data/public-events-v6/$generationId/head.json"
    if ([string]$pointer.head.path -ne $expectedHead -or
        [string]$manifest.head.path -ne $expectedHead -or
        [string]$pointer.head.sha256 -ne [string]$manifest.head.sha256 -or
        [string]$pointer.head.revision -ne [string]$pointer.revision -or
        [string]$manifest.head.revision -ne [string]$pointer.revision) {
        throw "La tête v6 n'est pas cohérente entre le pointeur et le manifeste."
    }

    $headPath = Resolve-PortalArtifactPath -RelativePath $expectedHead -RequiredPrefix "data/public-events-v6/" -Label "la tête v6"
    $head = Read-JsonFile -Path $headPath -Label "La tête immuable v6"
    Assert-FileSha256 -Path $headPath -Expected ([string]$pointer.head.sha256) -Label "la tête immuable v6"
    Assert-V6Document -Payload $head -Label "La tête immuable v6"
    if ([string]$head.baseGenerationId -ne $generationId -or [string]$head.revision -ne [string]$pointer.revision) {
        throw "La tête immuable v6 n'appartient pas à la génération active."
    }

    if ($null -eq $manifest.PSObject.Properties["counts"] -or
        $null -eq $manifest.PSObject.Properties["days"] -or
        $null -eq $head.PSObject.Properties["counts"] -or
        $null -eq $head.PSObject.Properties["events"] -or
        $null -eq $pointer.PSObject.Properties["counts"]) {
        throw "Les comptes obligatoires du contrat v6 sont absents. La promotion est annulée."
    }

    $manifestEchoes = Get-RequiredNonNegativeLong -Payload $manifest.counts -Name "echoes" -Label "Le manifeste v6"
    $manifestRepresented = Get-RequiredNonNegativeLong -Payload $manifest.counts -Name "representedEvents" -Label "Le manifeste v6"
    $manifestDays = Get-RequiredNonNegativeLong -Payload $manifest.counts -Name "days" -Label "Le manifeste v6"
    $pointerEchoes = Get-RequiredNonNegativeLong -Payload $pointer.counts -Name "totalEchoes" -Label "Le pointeur v6"
    $headTotalEchoes = Get-RequiredNonNegativeLong -Payload $head.counts -Name "totalEchoes" -Label "La tête v6"
    $headWindowEchoes = Get-RequiredNonNegativeLong -Payload $head.counts -Name "echoes" -Label "La tête v6"
    $headEvents = @($head.events)
    if ($pointerEchoes -ne $manifestEchoes -or
        $headTotalEchoes -ne $manifestEchoes -or
        $headWindowEchoes -ne $headEvents.Count -or
        $headWindowEchoes -gt $headTotalEchoes) {
        throw "Les comptes de la tête, du pointeur et du manifeste v6 divergent. La promotion est annulée."
    }

    $days = @($manifest.days)
    if ($manifestDays -ne $days.Count) {
        throw "Le nombre de journées du manifeste v6 est incohérent. La promotion est annulée."
    }

    $seenDates = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $totalEchoes = 0L
    $totalRepresented = 0L

    foreach ($day in $days) {
        $date = [string]$day.date
        $fragmentGenerationId = [string]$day.fragmentGenerationId
        $dailyGenerationId = [string]$day.dailyGenerationId
        if ($date -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not $seenDates.Add($date)) {
            throw "Le manifeste v6 contient une journée invalide ou dupliquée. La promotion est annulée."
        }
        Assert-GenerationId -Value $fragmentGenerationId -Label "Le fragment du $date"
        Assert-GenerationId -Value $dailyGenerationId -Label "Le résumé du $date"

        $expectedFragmentPath = "data/public-events-v6/$fragmentGenerationId/$date.json"
        $expectedDailyPath = "data/public-daily/$dailyGenerationId/$date.json"
        if ([string]$day.path -ne $expectedFragmentPath -or [string]$day.dailyPath -ne $expectedDailyPath -or
            -not $seenPaths.Add($expectedFragmentPath) -or -not $seenPaths.Add($expectedDailyPath)) {
            throw "Les chemins des artefacts du $date ne sont pas canoniques. La promotion est annulée."
        }

        $fragmentPath = Resolve-PortalArtifactPath -RelativePath $expectedFragmentPath -RequiredPrefix "data/public-events-v6/" -Label "le fragment du $date"
        $dailyPath = Resolve-PortalArtifactPath -RelativePath $expectedDailyPath -RequiredPrefix "data/public-daily/" -Label "le résumé du $date"
        $fragment = Read-JsonFile -Path $fragmentPath -Label "Le fragment du $date"
        $daily = Read-JsonFile -Path $dailyPath -Label "Le résumé du $date"
        Assert-FileSha256 -Path $fragmentPath -Expected ([string]$day.sha256) -Label "le fragment du $date"
        Assert-FileSha256 -Path $dailyPath -Expected ([string]$day.dailySha256) -Label "le résumé du $date"
        Assert-V6Document -Payload $fragment -Label "Le fragment du $date"
        Assert-V6Document -Payload $daily -Label "Le résumé du $date"

        if ([string]$fragment.generationId -ne $fragmentGenerationId -or [string]$fragment.date -ne $date -or
            [string]$daily.generationId -ne $dailyGenerationId -or [string]$daily.date -ne $date) {
            throw "Les artefacts du $date ne correspondent pas aux générations déclarées. La promotion est annulée."
        }
        if ($null -eq $fragment.PSObject.Properties["counts"] -or
            $null -eq $fragment.PSObject.Properties["events"] -or
            $null -eq $daily.PSObject.Properties["counts"]) {
            throw "Les comptes des artefacts du $date sont absents. La promotion est annulée."
        }

        $declaredEchoes = Get-RequiredNonNegativeLong -Payload $day -Name "events" -Label "La journée $date"
        $declaredRepresented = Get-RequiredNonNegativeLong -Payload $day -Name "representedEvents" -Label "La journée $date"
        $fragmentEchoes = Get-RequiredNonNegativeLong -Payload $fragment.counts -Name "echoes" -Label "Le fragment du $date"
        $fragmentRepresented = Get-RequiredNonNegativeLong -Payload $fragment.counts -Name "representedEvents" -Label "Le fragment du $date"
        $dailyEchoes = Get-RequiredNonNegativeLong -Payload $daily.counts -Name "echoes" -Label "Le résumé du $date"
        $dailyRepresented = Get-RequiredNonNegativeLong -Payload $daily.counts -Name "representedEvents" -Label "Le résumé du $date"
        $fragmentEvents = @($fragment.events)
        if ($declaredEchoes -ne $fragmentEchoes -or $declaredEchoes -ne $dailyEchoes -or $declaredEchoes -ne $fragmentEvents.Count -or
            $declaredRepresented -ne $fragmentRepresented -or $declaredRepresented -ne $dailyRepresented) {
            throw "Les comptes du fragment et du résumé du $date divergent. La promotion est annulée."
        }

        foreach ($event in $fragmentEvents) {
            $eventKey = [string]$event.key
            if ([string]::IsNullOrWhiteSpace($eventKey) -or -not $seenKeys.Add($eventKey)) {
                throw "Un écho sans clé ou dupliqué est présent dans les fragments v6. La promotion est annulée."
            }
        }
        $totalEchoes += $declaredEchoes
        $totalRepresented += $declaredRepresented
    }

    if ($totalEchoes -ne $manifestEchoes -or $totalRepresented -ne $manifestRepresented) {
        throw "Les sommes journalières ne correspondent pas aux comptes du manifeste v6. La promotion est annulée."
    }

    foreach ($event in $headEvents) {
        $eventKey = [string]$event.key
        if ([string]::IsNullOrWhiteSpace($eventKey) -or -not $seenKeys.Contains($eventKey)) {
            throw "La tête v6 référence un écho absent des fragments publiés. La promotion est annulée."
        }
    }
}

$payload = [ordered]@{
    schemaVersion = 1
    activeContract = $ActiveContract
    candidateContract = "v6"
}
$json = $payload | ConvertTo-Json -Depth 4
$tempPath = "$channelPath.$PID.tmp"
$backupPath = "$channelPath.$PID.bak"
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)

try {
    [IO.File]::WriteAllText($tempPath, "$json`n", $utf8WithoutBom)
    if (Test-Path -LiteralPath $channelPath -PathType Leaf) {
        [IO.File]::Replace($tempPath, $channelPath, $backupPath, $true)
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    }
    else {
        [IO.File]::Move($tempPath, $channelPath)
    }
}
finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Canal des échos publics activé sur $ActiveContract."
