param(
    [switch]$SansDocker,
    [switch]$SansTestsPython,
    [switch]$SansBash
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$failures = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()

function Write-Result {
    param(
        [bool]$Ok,
        [string]$Label,
        [string]$Details = ""
    )

    if ($Ok) {
        Write-Host "[OK] $Label" -ForegroundColor Green
    }
    else {
        Write-Host "[ECHEC] $Label" -ForegroundColor Red
        $script:failures.Add($(if ($Details) { "$Label : $Details" } else { $Label }))
    }
}

function Add-Warning {
    param([string]$Message)
    $script:warnings.Add($Message)
    Write-Host "[AVERTISSEMENT] $Message" -ForegroundColor Yellow
}

Write-Host "Validation locale du depot Gaylemon" -ForegroundColor Cyan
Write-Host "Aucun service distant ou conteneur actif ne sera modifie." -ForegroundColor DarkGray
Write-Host ""

$requiredFiles = @(
    ".env.example",
    ".gitignore",
    ".github\ISSUE_TEMPLATE\bug.yml",
    ".github\ISSUE_TEMPLATE\feature.yml",
    ".github\pull_request_template.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "config\exemples\bot.env.example",
    "docs\BOT-DISCORD.md",
    "docs\README.md",
    "LICENSE",
    "README.md",
    "SECURITY.md",
    "THIRD_PARTY_NOTICES.md",
    "compose.yaml",
    "dependencies\palworld-save-tools.lock.json",
    "server\deployment-manifest.json",
    "server\deploy\gaylemon_deploy.py",
    "scripts\lib\Gaylemon.Deployment.ps1",
    "scripts\lib\Gaylemon.Config.ps1",
    "server\palworld.env.example",
    "server\palworld-kuma.env.example"
)
foreach ($relativePath in $requiredFiles) {
    Write-Result (Test-Path -LiteralPath (Join-Path $ProjectRoot $relativePath)) "Fichier requis: $relativePath"
}

$licenseText = Get-Content -LiteralPath (Join-Path $ProjectRoot "LICENSE") -Raw -Encoding UTF8
Write-Result (
    $licenseText -match '^MIT License' -and
    $licenseText -match 'Copyright \(c\) 2026' -and
    $licenseText -match 'THE SOFTWARE IS PROVIDED "AS IS"'
) "Licence MIT complète"

$socialCardSource = Get-Content -LiteralPath (Join-Path $ProjectRoot "portal\assets\social\gaylemon-social-card.svg") -Raw -Encoding UTF8
Write-Result (
    $socialCardSource -notmatch '(?i)(assets/game|\.\./game|T_WorldMap|_icon_normal)'
) "Carte sociale autonome" "La carte sociale référence une ressource Palworld exclue de Git."

$nginxConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot "docker\microsite\default.conf") -Raw -Encoding UTF8
Write-Result (
    $nginxConfig.Contains('location ~ ^/data/public-[A-Za-z0-9_.-]+\.json$') -and
    $nginxConfig.Contains('location ~ ^/data/players/[A-Za-z0-9-]+\.json$') -and
    $nginxConfig.Contains('location /data/ {') -and
    $nginxConfig -notmatch 'location\s+~\s+\^/data/\.\*\\\.json\$'
) "Allowlist HTTP des donnees publiques"
Write-Result (
    $nginxConfig.Contains('location ^~ /assets/game/') -and
    $nginxConfig.Contains('max-age=31536000, immutable') -and
    $nginxConfig.Contains('location ~* \.(?:css|js)$')
) "Cache long des assets statiques"
Write-Result (
    $nginxConfig.Contains('add_header X-Frame-Options "DENY" always;') -and
    $nginxConfig.Contains('add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()" always;') -and
    $nginxConfig.Contains("add_header Content-Security-Policy `"base-uri 'self'; object-src 'none'; form-action 'self'; frame-ancestors 'none'`" always;")
) "Headers de securite du microsite"
Write-Result (
    $nginxConfig.Contains('location = /assets/game/.source-commit') -and
    $nginxConfig.Contains('return 404;')
) "Marqueur source cache non servi"

$composeConfig = Get-Content -LiteralPath (Join-Path $ProjectRoot "compose.yaml") -Raw -Encoding UTF8
$apiTunnelScript = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\palworld-api-tunnel.ps1") -Raw -Encoding UTF8
$apiTunnelEntrypoint = Get-Content -LiteralPath (Join-Path $ProjectRoot "docker\palworld-api-tunnel\entrypoint.sh") -Raw -Encoding UTF8
$botEnvExample = Get-Content -LiteralPath (Join-Path $ProjectRoot "config\exemples\bot.env.example") -Raw -Encoding UTF8
Write-Result (
    $composeConfig.Contains('127.0.0.1:${GAYLEMON_API_LOCAL_PORT:-8212}:${GAYLEMON_API_LOCAL_PORT:-8212}') -and
    $composeConfig.Contains('source: ${GAYLEMON_SSH_DIR:-${USERPROFILE}/.ssh}') -and
    $composeConfig.Contains('read_only: true') -and
    $composeConfig.Contains('restart: unless-stopped')
) "Tunnel API Docker local et persistant"
Write-Result (
    $apiTunnelScript.Contains('Assert-TunnelPort') -and
    $apiTunnelScript.Contains('Assert-SshAlias') -and
    $apiTunnelScript.Contains('[ValidateSet("", "docker", "windows-ssh")]') -and
    $apiTunnelScript.Contains('Start-WindowsSshTunnel') -and
    $apiTunnelScript.Contains('GAYLEMON_SSH_DIR') -and
    $apiTunnelEntrypoint.Contains('ForwardAgent=no') -and
    $apiTunnelEntrypoint.Contains('ForwardX11=no') -and
    $apiTunnelEntrypoint.Contains('PermitLocalCommand=no') -and
    $apiTunnelEntrypoint.Contains('validate_port') -and
    $apiTunnelEntrypoint.Contains('*[!A-Za-z0-9._@:-]*')
) "Tunnel API Docker durci"
Write-Result (
    $botEnvExample -match '(?m)^BOT_PALWORLD_REST_API_URL=http://127\.0\.0\.1:8212/v1/api$' -and
    $botEnvExample -match '(?m)^BOT_PALWORLD_REST_API_USERNAME=admin$' -and
    $botEnvExample -match '(?m)^BOT_PALWORLD_REST_API_PASSWORD=REMPLACER_PAR_LE_MOT_DE_PASSE_ADMIN$'
) "Configuration exemple du bot Discord"

$eventsSyncSource = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\sync-palworld-events.ps1") -Raw -Encoding UTF8
$metricsUpdaterSource = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\update-microsite-metrics.ps1") -Raw -Encoding UTF8
Write-Result (
    $eventsSyncSource.Contains("public-events-index.json") -and
    $eventsSyncSource.Contains("public-events-page-{0:D4}.json") -and
    (Test-Path -LiteralPath (Join-Path $ProjectRoot "portal\data\public-events-index.example.json")) -and
    (Test-Path -LiteralPath (Join-Path $ProjectRoot "portal\data\public-events-page-0001.example.json"))
) "Pagination statique des echos publics"
Write-Result (
    $metricsUpdaterSource -match '\[int\]\$EventsIntervalMinutes\s*=\s*1\b'
) "Synchronisation minute des echos publics"

$publicIdentityLeakErrors = [Collections.Generic.List[string]]::new()
$publicExportTemp = Join-Path ([IO.Path]::GetTempPath()) ("gaylemon-public-export-validation-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path $publicExportTemp | Out-Null
    $sentinelAccountName = "SHOULD_NOT_BE_PUBLIC_ACCOUNT_NAME"
    $sentinelNamedAccountName = "SHOULD_NOT_BE_PUBLIC_NAMED_ACCOUNT"
    $expectedPublicName = "Nom Public"
    $sampleMetrics = [ordered]@{
        ok = $true
        updatedAt = "2026-01-01T00:00:00Z"
        info = [ordered]@{
            serverName = "Validation"
            description = "Validation"
            version = "test"
        }
        metrics = [ordered]@{
            currentPlayerCount = 1
        }
        players = @(
            [ordered]@{
                name = ""
                accountName = $sentinelAccountName
            },
            [ordered]@{
                name = $expectedPublicName
                accountName = $sentinelNamedAccountName
            }
        )
    }
    $sampleStats = [ordered]@{
        ok = $true
        updatedAt = "2026-01-01T00:00:00Z"
        collection = [ordered]@{}
        server = [ordered]@{}
        actors = [ordered]@{}
        guilds = @()
        players = @(
            [ordered]@{
                name = ""
                accountName = $sentinelAccountName
            },
            [ordered]@{
                name = $expectedPublicName
                accountName = $sentinelNamedAccountName
            }
        )
    }

    [IO.File]::WriteAllText(
        (Join-Path $publicExportTemp "metrics.json"),
        (($sampleMetrics | ConvertTo-Json -Depth 8).TrimEnd() + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $publicExportTemp "stats.json"),
        (($sampleStats | ConvertTo-Json -Depth 8).TrimEnd() + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false)
    )

    & (Join-Path $ProjectRoot "scripts\export-public-microsite-data.ps1") -DataDirectory $publicExportTemp | Out-Null
    foreach ($publicFileName in @("public-metrics.json", "public-stats.json")) {
        $publicPath = Join-Path $publicExportTemp $publicFileName
        $publicText = Get-Content -LiteralPath $publicPath -Raw -Encoding UTF8
        if ($publicText.Contains($sentinelAccountName) -or $publicText.Contains($sentinelNamedAccountName)) {
            $publicIdentityLeakErrors.Add($publicFileName)
        }
        $publicPayload = $publicText | ConvertFrom-Json
        $publicNames = @($publicPayload.players | ForEach-Object { [string]$_.name })
        if ($expectedPublicName -notin $publicNames) {
            $publicIdentityLeakErrors.Add("$publicFileName nom public absent")
        }
    }
}
catch {
    $publicIdentityLeakErrors.Add($_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $publicExportTemp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Result ($publicIdentityLeakErrors.Count -eq 0) "Exports publics sans accountName" ($publicIdentityLeakErrors -join ", ")

$availabilityExporterSource = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\export-uptime-kuma-history.ps1") -Raw -Encoding UTF8
$availabilityExample = Get-Content -LiteralPath (Join-Path $ProjectRoot "portal\data\public-availability.example.json") -Raw -Encoding UTF8
Write-Result (
    $availabilityExporterSource -notmatch '(?m)^\s*path\s*=\s*\$Path\b' -and
    $availabilityExample -notmatch '"path"\s*:'
) "Disponibilite publique sans chemins locaux"

$configSource = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\lib\Gaylemon.Config.ps1") -Raw -Encoding UTF8
$documentedLocalKeys = @(
    Get-Content -LiteralPath (Join-Path $ProjectRoot ".env.example") -Encoding UTF8 |
        Where-Object { $_ -match '^(GAYLEMON_[A-Z0-9_]+)=' } |
        ForEach-Object { $Matches[1] }
)
$consumedLocalKeys = @(
    [regex]::Matches($configSource, '"(GAYLEMON_[A-Z0-9_]+)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)
$missingLocalKeys = @($consumedLocalKeys | Where-Object { $_ -notin $documentedLocalKeys })
Write-Result ($missingLocalKeys.Count -eq 0) "Variables locales documentées" ($missingLocalKeys -join ", ")

$serverExampleText = Get-Content -LiteralPath (Join-Path $ProjectRoot "server\palworld.env.example") -Raw -Encoding UTF8
$requiredServerKeys = @(
    "ADMIN_PASSWORD",
    "SERVER_PASSWORD",
    "PALWORLD_ARGS",
    "PALWORLD_BACKUP_RETENTION_DAYS",
    "PALWORLD_BACKUP_SAVE_WAIT_SECONDS",
    "PALWORLD_REST_BASE_URL",
    "PALWORLD_UPDATE_COUNTDOWN_STEPS",
    "PALWORLD_UPDATE_DEFER_IF_PLAYERS",
    "PALWORLD_UPDATE_RETRY_DELAY_SECONDS"
)
$missingServerKeys = @($requiredServerKeys | Where-Object { $serverExampleText -notmatch "(?m)^$([regex]::Escape($_))=" })
Write-Result ($missingServerKeys.Count -eq 0) "Variables Ubuntu documentées" ($missingServerKeys -join ", ")

$parseErrors = [Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $ProjectRoot -Filter "*.ps1" -File -Recurse) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($error in @($errors)) {
        $parseErrors.Add("$($file.FullName):$($error.Extent.StartLineNumber) $($error.Message)")
    }
}
Write-Result ($parseErrors.Count -eq 0) "Syntaxe PowerShell" ($parseErrors -join "; ")

$jsonErrors = [Collections.Generic.List[string]]::new()
$jsonFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "portal\data") -Filter "*.example.json" -File
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "dependencies") -Filter "*.json" -File
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "server\tests\fixtures") -Filter "*.json" -File
    Get-Item -LiteralPath (Join-Path $ProjectRoot "server\deployment-manifest.json")
)
foreach ($file in $jsonFiles) {
    try {
        [void](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        $jsonErrors.Add("$($file.Name): $($_.Exception.Message)")
    }
}
Write-Result ($jsonErrors.Count -eq 0) "JSON versionnes" ($jsonErrors -join "; ")

try {
    . (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
    . (Join-Path $PSScriptRoot "lib\Gaylemon.Deployment.ps1")
    $deploymentConfig = Get-GaylemonConfig -ProjectRoot $ProjectRoot
    $deploymentManifest = Get-GaylemonDeploymentManifest -ProjectRoot $ProjectRoot -Config $deploymentConfig
    $mappedSources = @($deploymentManifest.Entries | ForEach-Object Source)
    $deployableSources = @(
        "bin", "sbin", "systemd", "sysctl", "sudoers" | ForEach-Object {
            $directory = Join-Path $ProjectRoot "server\$_"
            Get-ChildItem -LiteralPath $directory -File | ForEach-Object {
                $_.FullName.Substring($ProjectRoot.Length + 1).Replace("\", "/")
            }
        }
    )
    $unmappedSources = @($deployableSources | Where-Object { $_ -notin $mappedSources })
    $orphanMappings = @($mappedSources | Where-Object { $_ -notin $deployableSources })
    Write-Result (
        $unmappedSources.Count -eq 0 -and $orphanMappings.Count -eq 0
    ) "Couverture du manifeste Ubuntu" (
        "non declares: $($unmappedSources -join ', '); mappings orphelins: $($orphanMappings -join ', ')"
    )

    $apiWrapperSources = @(
        "server/bin/palworld-announce.sh",
        "server/bin/palworld-api.sh",
        "server/bin/palworld-backup.sh",
        "server/bin/palworld-kuma-push.sh"
    )
    $apiWrapperPermissionErrors = @(
        $deploymentManifest.Entries |
            Where-Object { $_.Source -in $apiWrapperSources -and ($_.Group -ne "steam" -or $_.Mode -ne "0750") } |
            ForEach-Object { "$($_.Source):$($_.Group):$($_.Mode)" }
    )
    Write-Result (
        $apiWrapperPermissionErrors.Count -eq 0
    ) "Wrappers API Palworld limites au groupe steam" ($apiWrapperPermissionErrors -join ", ")
}
catch {
    Write-Result $false "Manifeste de deploiement Ubuntu" $_.Exception.Message
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & $node.Source --check (Join-Path $ProjectRoot "portal\assets\app.js") 2>&1 | Out-Null
    Write-Result ($LASTEXITCODE -eq 0) "Syntaxe JavaScript"
}
else {
    Add-Warning "Node.js absent; la syntaxe JavaScript n'a pas ete verifiee."
}

if (-not $SansTestsPython) {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        $python = Get-Command python3 -ErrorAction SilentlyContinue
    }
    if ($python) {
        $pythonSyntaxErrors = [Collections.Generic.List[string]]::new()
        $pythonSources = @(
            Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "server\bin") -Filter "*.py" -File
            Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "server\deploy") -Filter "*.py" -File
        )
        foreach ($pythonSource in $pythonSources) {
            & $python.Source -m py_compile $pythonSource.FullName 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $pythonSyntaxErrors.Add($pythonSource.Name) }
        }
        Write-Result ($pythonSyntaxErrors.Count -eq 0) "Syntaxe Python" ($pythonSyntaxErrors -join ", ")

        & $python.Source -m unittest discover -s (Join-Path $ProjectRoot "server\tests") -p "test_*.py" 2>&1 | Out-Host
        Write-Result ($LASTEXITCODE -eq 0) "Tests Python"
    }
    else {
        Add-Warning "Python absent; les tests du collecteur n'ont pas ete executes."
    }
}

if (-not $SansBash) {
    $bashPath = $null
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        $gitBash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        if (Test-Path -LiteralPath $gitBash) {
            $bashPath = $gitBash
        }
    }
    else {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($bash) { $bashPath = $bash.Source }
    }

    if ($bashPath) {
        $bashErrors = [Collections.Generic.List[string]]::new()
        $bashFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "server\bin") -Filter "*.sh" -File
            Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "server\sbin") -File
            Get-Item -LiteralPath (Join-Path $ProjectRoot "docker\palworld-api-tunnel\entrypoint.sh")
        )
        foreach ($file in $bashFiles) {
            & $bashPath -n $file.FullName 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $bashErrors.Add($file.Name) }
        }
        Write-Result ($bashErrors.Count -eq 0) "Syntaxe Bash" ($bashErrors -join ", ")
    }
    else {
        Add-Warning "Bash absent; les scripts Ubuntu n'ont pas ete analyses."
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $ignoredPaths = @(
        ".env",
        "config/local/INSTANCE.md",
        "portal/data/public-metrics.json",
        "portal/data/players/exemple.json",
        "portal/assets/game/exemple.webp",
        "runtime/validation/exemple.json",
        "server/bin/__pycache__/exemple.pyc"
    )
    $notIgnored = [Collections.Generic.List[string]]::new()
    foreach ($path in $ignoredPaths) {
        & $git.Source -C $ProjectRoot check-ignore --quiet -- $path
        if ($LASTEXITCODE -ne 0) { $notIgnored.Add($path) }
    }
    Write-Result ($notIgnored.Count -eq 0) "Isolation des fichiers locaux Git" ($notIgnored -join ", ")

    $publishable = @(
        & $git.Source -C $ProjectRoot ls-files --cached --others --exclude-standard |
            Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot $_) }
    )
    $workflowDirectory = Join-Path $ProjectRoot ".github\workflows"
    $workflowFiles = @(
        if (Test-Path -LiteralPath $workflowDirectory) {
            Get-ChildItem -LiteralPath $workflowDirectory -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".yml", ".yaml") }
        }
    )
    Write-Result ($workflowFiles.Count -eq 0) "Validation GitHub automatique désactivée" (($workflowFiles | ForEach-Object Name) -join ", ")
    $versionedCmdFiles = @($publishable | Where-Object { $_ -like "*.cmd" })
    Write-Result ($versionedCmdFiles.Count -eq 0) "Aucun lanceur CMD versionné" ($versionedCmdFiles -join ", ")
    $forbidden = @($publishable | Where-Object {
        $_ -match '(^|/)(runtime|config/local|portal/data/players|portal/assets/game|portal/joueur)/' -or
        $_ -match '(^|/)\.env($|\.)' -and $_ -notmatch '\.example$' -or
        $_ -match '(__pycache__|\.py[co]$)'
    })
    Write-Result ($forbidden.Count -eq 0) "Liste des fichiers publiables" ($forbidden -join ", ")

    $textExtensions = @(".css", ".env", ".example", ".html", ".js", ".json", ".md", ".ps1", ".py", ".sh", ".svg", ".txt", ".yaml", ".yml")
    $utf8Errors = [Collections.Generic.List[string]]::new()
    $mojibakeErrors = [Collections.Generic.List[string]]::new()
    $whitespaceErrors = [Collections.Generic.List[string]]::new()
    $finalNewlineErrors = [Collections.Generic.List[string]]::new()
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    $boxDrawingCharacters = @([char]0x251C, [char]0x2524, [char]0x252C, [char]0xFFFD)
    $brokenPunctuationPrefix = ([char]0x00D4).ToString() + ([char]0x00C7)
    foreach ($relativePath in $publishable) {
        $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        if ($extension -notin $textExtensions -and [IO.Path]::GetFileName($relativePath) -notin @("LICENSE", ".gitignore", ".gitattributes")) {
            continue
        }
        $fullPath = Join-Path $ProjectRoot $relativePath
        try {
            $content = $strictUtf8.GetString([IO.File]::ReadAllBytes($fullPath))
            $containsBrokenText = $null -ne ($boxDrawingCharacters | Where-Object { $content.Contains([string]$_) } | Select-Object -First 1)
            if ($containsBrokenText -or $content.Contains($brokenPunctuationPrefix)) {
                $mojibakeErrors.Add($relativePath)
            }
            if ($content -match '(?m)[ \t]+$') {
                $whitespaceErrors.Add($relativePath)
            }
            if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
                $finalNewlineErrors.Add($relativePath)
            }
        }
        catch {
            $utf8Errors.Add($relativePath)
        }
    }
    Write-Result ($utf8Errors.Count -eq 0) "Encodage UTF-8 des fichiers publiables" ($utf8Errors -join ", ")
    Write-Result ($mojibakeErrors.Count -eq 0) "Absence de texte corrompu" ($mojibakeErrors -join ", ")
    Write-Result ($whitespaceErrors.Count -eq 0) "Absence d'espaces en fin de ligne" ($whitespaceErrors -join ", ")
    Write-Result ($finalNewlineErrors.Count -eq 0) "Fin de ligne finale" ($finalNewlineErrors -join ", ")

    $markdownLinkErrors = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in @($publishable | Where-Object { $_ -like "*.md" })) {
        $fullPath = Join-Path $ProjectRoot $relativePath
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($content, '!?' + '\[[^\]]*\]\((?<target>[^)]+)\)')) {
            $target = $match.Groups["target"].Value.Trim().Trim('<', '>')
            if ($target -match '^(https?://|mailto:|#)') { continue }
            $target = ($target -split '#', 2)[0]
            if (-not $target) { continue }
            $target = [Uri]::UnescapeDataString($target)
            $candidate = if ($target.StartsWith("/")) {
                Join-Path $ProjectRoot $target.TrimStart("/")
            }
            else {
                Join-Path (Split-Path -Parent $fullPath) $target
            }
            if (-not (Test-Path -LiteralPath $candidate)) {
                $markdownLinkErrors.Add("$relativePath -> $target")
            }
        }
    }
    Write-Result ($markdownLinkErrors.Count -eq 0) "Liens Markdown locaux" ($markdownLinkErrors -join "; ")

    $secretPatterns = @(
        '-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----',
        '\bAKIA[0-9A-Z]{16}\b',
        '\bgh[pousr]_[A-Za-z0-9]{30,}\b',
        '\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b',
        'https://(?:discord(?:app)?\.com)/api/webhooks/[0-9]+/',
        '(?m)^CF_API_TOKEN=[ \t]*\S+',
        '(?m)^KUMA_PUSH_URL=(?!.*(?:REPLACE_ME|EXEMPLE)).*?/api/push/[A-Za-z0-9_-]{12,}',
        '(?m)^(?:SERVER_PASSWORD|ADMIN_PASSWORD|BOT_PALWORLD_REST_API_PASSWORD)=(?![ \t]*(?:["'']?\$\{|["'']?[ \t]*$|REMPLACER|<))[^\r\n]+'
    )
    $secretErrors = [Collections.Generic.List[string]]::new()
    $publicIpErrors = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in $publishable) {
        $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        if ($extension -notin $textExtensions -and [IO.Path]::GetFileName($relativePath) -notin @("LICENSE", ".gitignore", ".gitattributes")) {
            continue
        }
        $content = Get-Content -LiteralPath (Join-Path $ProjectRoot $relativePath) -Raw -Encoding UTF8
        if ($secretPatterns | Where-Object { [regex]::IsMatch($content, $_) }) {
            $secretErrors.Add($relativePath)
        }
        if ($extension -in @(".css", ".html", ".js", ".svg")) { continue }
        foreach ($ipMatch in [regex]::Matches($content, '(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])')) {
            $parts = @($ipMatch.Value.Split('.') | ForEach-Object { [int]$_ })
            if ($parts | Where-Object { $_ -gt 255 }) { continue }
            $isNonPublic = $parts[0] -in @(0, 10, 127, 255) -or
                ($parts[0] -eq 169 -and $parts[1] -eq 254) -or
                ($parts[0] -eq 172 -and $parts[1] -ge 16 -and $parts[1] -le 31) -or
                ($parts[0] -eq 192 -and $parts[1] -eq 168)
            if (-not $isNonPublic) {
                $publicIpErrors.Add("$relativePath -> $($ipMatch.Value)")
            }
        }
    }
    Write-Result ($secretErrors.Count -eq 0) "Absence de secrets reconnaissables" (($secretErrors | Sort-Object -Unique) -join ", ")
    Write-Result ($publicIpErrors.Count -eq 0) "Absence d'adresse IP publique" (($publicIpErrors | Sort-Object -Unique) -join ", ")
}
else {
    Add-Warning "Git absent; les exclusions du depot n'ont pas ete verifiees."
}

if (-not $SansDocker) {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        & $docker.Source compose --project-directory $ProjectRoot config --quiet 2>&1 | Out-Null
        Write-Result ($LASTEXITCODE -eq 0) "Configuration Docker Compose"
    }
    else {
        Add-Warning "Docker absent; le fichier Compose n'a pas ete valide."
    }
}

Write-Host ""
if ($warnings.Count -gt 0) {
    Write-Host "$($warnings.Count) avertissement(s)." -ForegroundColor Yellow
}
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) validation(s) en echec:" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "- $failure" -ForegroundColor Red }
    exit 1
}

Write-Host "Depot valide. Aucun service actif n'a ete modifie." -ForegroundColor Green
