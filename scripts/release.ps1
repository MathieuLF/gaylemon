[CmdletBinding()]
param(
    [string]$Version = ((Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION')).Trim()),
    [string]$Image = 'ghcr.io/mathieulf/gaylemon',
    [string]$CosignKey = "$env:USERPROFILE\.gaylemon\cosign.key",
    [string]$CosignPublicKey = "$env:USERPROFILE\.gaylemon\cosign.pub",
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$syftImage = 'anchore/syft:v1.50.0@sha256:1288ea4c8b38767b4e620c1e312c8cb26b6e887a99b4f07ab6cd19fc6f225026'
$trivyImage = 'aquasec/trivy:0.73.0@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c'
$cosignImage = 'ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8'
$releasePredicateType = 'https://gaylemon.nethercore.dev/attestations/release-manifest/v1'
$securityDirectory = Join-Path $root 'security'
$committedCosignPublicKey = Join-Path $securityDirectory 'cosign.pub'
if (@(& git -C $root status --porcelain).Count -ne 0) { throw 'La publication exige un arbre Git propre.' }
foreach ($command in 'docker','go') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Outil de release absent: $command" }
}
function Invoke-Checked([scriptblock]$Action, [string]$Message) {
    & $Action
    if ($LASTEXITCODE -ne 0) { throw $Message }
}
function New-GHCRDockerConfig {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI est requis pour publier dans GHCR.' }
    $login = (& gh api user --jq .login).Trim()
    $token = (& gh auth token).Trim()
    if (-not $login -or -not $token) { throw 'Authentification GitHub/GHCR absente.' }
    $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${login}:$token"))
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('gaylemon-cosign-docker-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $config = [ordered]@{ auths = [ordered]@{ 'ghcr.io' = [ordered]@{ auth = $auth } } }
    [IO.File]::WriteAllText((Join-Path $directory 'config.json'), ($config | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    $token = $null
    return $directory
}
foreach ($keyPath in $CosignKey,$CosignPublicKey) {
    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) { throw "Clé CoSign absente: $keyPath" }
}
if (-not (Test-Path -LiteralPath $committedCosignPublicKey -PathType Leaf)) {
    throw 'La clé publique versionnée security/cosign.pub est absente.'
}
$localPublicKeyHash = (Get-FileHash -LiteralPath $CosignPublicKey -Algorithm SHA256).Hash
$committedPublicKeyHash = (Get-FileHash -LiteralPath $committedCosignPublicKey -Algorithm SHA256).Hash
if ($localPublicKeyHash -ne $committedPublicKeyHash) {
    throw 'La clé publique locale ne correspond pas à security/cosign.pub.'
}
function Read-CosignPassword([string]$KeyPath) {
    if (Test-Path Env:COSIGN_PASSWORD) { return [string]$env:COSIGN_PASSWORD }
    $protectedPath = Join-Path (Split-Path -Parent $KeyPath) 'cosign-password.dpapi'
    if (-not (Test-Path -LiteralPath $protectedPath)) { throw "COSIGN_PASSWORD est absent et aucun mot de passe DPAPI local n'accompagne la clé." }
    $secure = (Get-Content -Raw -LiteralPath $protectedPath).Trim() | ConvertTo-SecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
$commit = (& git -C $root rev-parse HEAD).Trim()
$releaseNotes = Get-Content -Raw -LiteralPath (Join-Path $root 'portal\release-notes.json') | ConvertFrom-Json
if (-not @($releaseNotes.releases | Where-Object { $_.version -eq $Version })) { throw 'Les notes de version ne couvrent pas la version demandée.' }
if (-not (Select-String -LiteralPath (Join-Path $root 'CHANGELOG.md') -SimpleMatch 'multi-saisons' -Quiet)) { throw 'Le journal des changements ne couvre pas le cycle multi-saisons.' }
$tag = "$Image`:$Version"
docker build --build-arg "GAYLEMON_VERSION=$Version" --build-arg "GAYLEMON_COMMIT=$commit" --build-arg GAYLEMON_CHANNEL=production --tag $tag $root
if ($LASTEXITCODE -ne 0) { throw 'Construction OCI impossible.' }
$output = Join-Path $root 'release'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$outputMount = $output.Replace('\', '/')
Invoke-Checked {
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${outputMount}:/out" $syftImage $tag `
        -o "spdx-json=/out/gaylemon-$Version.spdx.json" -o "cyclonedx-json=/out/gaylemon-$Version.cdx.json"
} 'SBOM impossible.'
Invoke-Checked {
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock $trivyImage image --exit-code 1 --severity HIGH,CRITICAL $tag
} 'Scan Trivy bloquant.'
$agent = Join-Path $output "gaylemon-agent-$Version-linux-amd64"
$env:CGO_ENABLED = '0'; $env:GOOS = 'linux'; $env:GOARCH = 'amd64'
try { go build -mod=readonly -trimpath -ldflags "-s -w -X main.version=$Version" -o $agent ./cmd/gaylemon }
finally { Remove-Item Env:CGO_ENABLED,Env:GOOS,Env:GOARCH -ErrorAction SilentlyContinue }
$agentSha = (Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$agent.sha256", "$agentSha  $([IO.Path]::GetFileName($agent))`n", [Text.UTF8Encoding]::new($false))
$previousCosignPassword = $env:COSIGN_PASSWORD
try {
    $env:COSIGN_PASSWORD = Read-CosignPassword $CosignKey
    $agentBundle = "$agent.cosign-bundle.json"
    $keyDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $CosignKey))
    $keyName = Split-Path -Leaf $CosignKey
    $publicKeyDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $CosignPublicKey))
    $publicKeyName = Split-Path -Leaf $CosignPublicKey
    $agentName = Split-Path -Leaf $agent
    $agentBundleName = Split-Path -Leaf $agentBundle
    Invoke-Checked {
        docker run --rm -e COSIGN_PASSWORD -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out" $cosignImage `
            sign-blob --yes --use-signing-config=false --key "/keys/$keyName" --bundle "/out/$agentBundleName" "/out/$agentName"
    } 'Signature du bundle agent impossible.'
    Invoke-Checked {
        docker run --rm -v "${publicKeyDirectory}:/trust:ro" -v "${outputMount}:/out" $cosignImage `
            verify-blob --key "/trust/$publicKeyName" --bundle "/out/$agentBundleName" "/out/$agentName"
    } 'Vérification du bundle agent impossible.'
    $localImageID = (docker image inspect $tag --format '{{.Id}}').Trim()
    $descriptor = Join-Path $output "gaylemon-$Version-local-image.json"
    [IO.File]::WriteAllText($descriptor, (([ordered]@{ image=$tag; imageId=$localImageID; commit=$commit } | ConvertTo-Json) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $descriptorBundle = "$descriptor.cosign-bundle.json"
    $descriptorName = Split-Path -Leaf $descriptor
    $descriptorBundleName = Split-Path -Leaf $descriptorBundle
    Invoke-Checked {
        docker run --rm -e COSIGN_PASSWORD -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out" $cosignImage `
            sign-blob --yes --use-signing-config=false --key "/keys/$keyName" --bundle "/out/$descriptorBundleName" "/out/$descriptorName"
    } "Preuve Cosign locale de l'image impossible."
    Invoke-Checked {
        docker run --rm -v "${publicKeyDirectory}:/trust:ro" -v "${outputMount}:/out" $cosignImage `
            verify-blob --key "/trust/$publicKeyName" --bundle "/out/$descriptorBundleName" "/out/$descriptorName"
    } "Vérification de la preuve locale de l'image impossible."
    if ($Publish) {
        docker push $tag
        if ($LASTEXITCODE -ne 0) { throw 'Publication GHCR impossible.' }
        $digest = (docker buildx imagetools inspect $tag --format '{{.Manifest.Digest}}').Trim()
        if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Digest GHCR introuvable.' }
        $reference = "$Image@$digest"
        $releaseManifestPath = Join-Path $output "gaylemon-$Version-release.json"
        $releaseManifest = [ordered]@{
            schema = 'gaylemon.release.v2'
            version = $Version
            commit = $commit
            image = $reference
            agentSha256 = $agentSha
            signed = $true
            attested = $true
        }
        [IO.File]::WriteAllText($releaseManifestPath, (($releaseManifest | ConvertTo-Json) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        $dockerConfigDirectory = New-GHCRDockerConfig
        try {
            Invoke-Checked { docker run --rm -e COSIGN_PASSWORD -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${keyDirectory}:/keys:ro" $cosignImage sign --yes --key "/keys/$keyName" $reference } 'Signature du digest GHCR impossible.'
            Invoke-Checked { docker run --rm -e COSIGN_PASSWORD -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out:ro" $cosignImage attest --yes --key "/keys/$keyName" --type $releasePredicateType --predicate "/out/$([IO.Path]::GetFileName($releaseManifestPath))" $reference } 'Attestation du manifeste de release impossible.'
            Invoke-Checked { docker run --rm -e COSIGN_PASSWORD -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out:ro" $cosignImage attest --yes --key "/keys/$keyName" --type spdxjson --predicate "/out/gaylemon-$Version.spdx.json" $reference } 'Attestation SPDX impossible.'
            Invoke-Checked { docker run --rm -e COSIGN_PASSWORD -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out:ro" $cosignImage attest --yes --key "/keys/$keyName" --type cyclonedx --predicate "/out/gaylemon-$Version.cdx.json" $reference } 'Attestation CycloneDX impossible.'
            Invoke-Checked { docker run --rm -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${securityDirectory}:/trust:ro" $cosignImage verify --key /trust/cosign.pub $reference *> $null } 'Vérification de la signature GHCR impossible.'
            Invoke-Checked { docker run --rm -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${securityDirectory}:/trust:ro" $cosignImage verify-attestation --key /trust/cosign.pub --type $releasePredicateType $reference *> $null } 'Vérification du manifeste de release attesté impossible.'
            Invoke-Checked { docker run --rm -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${securityDirectory}:/trust:ro" $cosignImage verify-attestation --key /trust/cosign.pub --type spdxjson $reference *> $null } 'Vérification de la preuve SPDX impossible.'
            Invoke-Checked { docker run --rm -e DOCKER_CONFIG=/docker-config -v "${dockerConfigDirectory}:/docker-config:ro" -v "${securityDirectory}:/trust:ro" $cosignImage verify-attestation --key /trust/cosign.pub --type cyclonedx $reference *> $null } 'Vérification de la preuve CycloneDX impossible.'
        }
        finally {
            if ($dockerConfigDirectory -and (Test-Path -LiteralPath $dockerConfigDirectory)) { Remove-Item -LiteralPath $dockerConfigDirectory -Recurse -Force }
        }
    }
}
finally {
    if ($null -eq $previousCosignPassword) { Remove-Item Env:COSIGN_PASSWORD -ErrorAction SilentlyContinue }
    else { $env:COSIGN_PASSWORD = $previousCosignPassword }
}
[ordered]@{ schema='gaylemon.release.v2'; version=$Version; commit=$commit; image=$tag; imageId=$localImageID; agentSha256=$agentSha; localSigningVerified=$true; published=[bool]$Publish } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'release-local.json') -Encoding utf8NoBOM
Write-Host "Release préparée: $tag"
