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
$syftImage = 'anchore/syft:v1.51.0@sha256:678bfa565b60f747aac0f8e964fe5588a24445b8d0a480e91f6efd70020dfbb0'
$trivyImage = 'aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969'
$cosignImage = 'ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8'
$releasePredicateType = 'urn:gaylemon:attestation:release-manifest:v1'
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
$builtAt = (& git -C $root show -s --format=%cI HEAD).Trim()
$validationReceiptPath = Join-Path $root 'release\local-validation.json'
if (-not (Test-Path -LiteralPath $validationReceiptPath -PathType Leaf)) {
    throw 'Un reçu Full suite.local-validation.v2 est requis avant la release.'
}
$validationReceipt = Get-Content -Raw -LiteralPath $validationReceiptPath | ConvertFrom-Json
if ($validationReceipt.schema -ne 'suite.local-validation.v2' -or
    $validationReceipt.contractRevision -ne '2.3.0' -or $validationReceipt.application -ne 'gaylemon' -or
    $validationReceipt.mode -ne 'full' -or $validationReceipt.result -ne 'passed' -or
    -not $validationReceipt.git.cleanAtStart -or -not $validationReceipt.git.cleanAtEnd -or
    $validationReceipt.git.commit -ne $commit -or $validationReceipt.version -ne $Version) {
    throw 'Le reçu Full ne prouve pas ce commit propre et cette version.'
}
$validationReceiptHash = (Get-FileHash -LiteralPath $validationReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$releaseNotes = Get-Content -Raw -LiteralPath (Join-Path $root 'portal\release-notes.json') | ConvertFrom-Json
if (-not @($releaseNotes.releases | Where-Object { $_.version -eq $Version })) { throw 'Les notes de version ne couvrent pas la version demandée.' }
if (-not (Select-String -LiteralPath (Join-Path $root 'CHANGELOG.md') -SimpleMatch 'multi-saisons' -Quiet)) { throw 'Le journal des changements ne couvre pas le cycle multi-saisons.' }
$tag = "$Image`:$Version"
docker build --build-arg "GAYLEMON_VERSION=$Version" --build-arg "GAYLEMON_COMMIT=$commit" --build-arg "GAYLEMON_BUILT_AT=$builtAt" --tag $tag $root
if ($LASTEXITCODE -ne 0) { throw 'Construction OCI impossible.' }
$output = Join-Path $root 'release'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$outputMount = $output.Replace('\', '/')
$artifactName = "gaylemon-$Version-linux-amd64.oci.tar"
$artifact = Join-Path $output $artifactName
Invoke-Checked { docker image save --output $artifact $tag } 'Matérialisation OCI locale impossible.'
$artifactHash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
$artifactDigest = "sha256:$artifactHash"
Invoke-Checked {
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${outputMount}:/out" $syftImage $tag `
        -o "spdx-json=/out/gaylemon-$Version.spdx.json" -o "cyclonedx-json=/out/gaylemon-$Version.cdx.json"
} 'SBOM impossible.'
Invoke-Checked {
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${outputMount}:/out" $trivyImage image `
        --exit-code 1 --severity HIGH,CRITICAL --format json --output "/out/gaylemon-$Version-trivy.json" $tag
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
    $artifactBundle = "$artifact.cosign-bundle.json"
    $artifactBundleName = Split-Path -Leaf $artifactBundle
    Invoke-Checked {
        docker run --rm -e COSIGN_PASSWORD -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out" $cosignImage `
            sign-blob --yes --use-signing-config=false --key "/keys/$keyName" --bundle "/out/$artifactBundleName" "/out/$artifactName"
    } 'Signature OCI locale impossible.'
    Invoke-Checked {
        docker run --rm -v "${publicKeyDirectory}:/trust:ro" -v "${outputMount}:/out" $cosignImage `
            verify-blob --key "/trust/$publicKeyName" --bundle "/out/$artifactBundleName" "/out/$artifactName"
    } 'Vérification de la signature OCI locale impossible.'
    $localAttestation = Join-Path $output "gaylemon-$Version-local-attestation.json"
    [IO.File]::WriteAllText($localAttestation, (([ordered]@{
        schema='gaylemon.local-attestation.v1'; application='gaylemon'; version=$Version; commit=$commit
        artifactDigest=$artifactDigest; routes=$validationReceipt.routes; validationReceiptSha256=$validationReceiptHash
    } | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $localAttestationBundle = "$localAttestation.cosign-bundle.json"
    $localAttestationName = Split-Path -Leaf $localAttestation
    $localAttestationBundleName = Split-Path -Leaf $localAttestationBundle
    Invoke-Checked {
        docker run --rm -e COSIGN_PASSWORD -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out" $cosignImage `
            sign-blob --yes --use-signing-config=false --key "/keys/$keyName" --bundle "/out/$localAttestationBundleName" "/out/$localAttestationName"
    } "Signature de l'attestation locale impossible."
    Invoke-Checked {
        docker run --rm -v "${publicKeyDirectory}:/trust:ro" -v "${outputMount}:/out" $cosignImage `
            verify-blob --key "/trust/$publicKeyName" --bundle "/out/$localAttestationBundleName" "/out/$localAttestationName"
    } "Vérification de l'attestation locale impossible."
    $localSpdxAttestationBundle = Join-Path $output "gaylemon-$Version-spdx-attestation.cosign-bundle.json"
    $localCycloneAttestationBundle = Join-Path $output "gaylemon-$Version-cyclonedx-attestation.cosign-bundle.json"
    $localSpdxAttestationBundleName = Split-Path -Leaf $localSpdxAttestationBundle
    $localCycloneAttestationBundleName = Split-Path -Leaf $localCycloneAttestationBundle
    Invoke-Checked {
        docker run --rm -e COSIGN_PASSWORD -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out" $cosignImage `
            attest-blob --yes --use-signing-config=false --key "/keys/$keyName" --predicate "/out/gaylemon-$Version.spdx.json" --type spdxjson --bundle "/out/$localSpdxAttestationBundleName" "/out/$artifactName"
    } 'Attestation SPDX locale impossible.'
    Invoke-Checked {
        docker run --rm -v "${publicKeyDirectory}:/trust:ro" -v "${outputMount}:/out" $cosignImage `
            verify-blob-attestation --key "/trust/$publicKeyName" --bundle "/out/$localSpdxAttestationBundleName" --type spdxjson "/out/$artifactName"
    } 'Vérification de l’attestation SPDX locale impossible.'
    Invoke-Checked {
        docker run --rm -e COSIGN_PASSWORD -v "${keyDirectory}:/keys:ro" -v "${outputMount}:/out" $cosignImage `
            attest-blob --yes --use-signing-config=false --key "/keys/$keyName" --predicate "/out/gaylemon-$Version.cdx.json" --type cyclonedx --bundle "/out/$localCycloneAttestationBundleName" "/out/$artifactName"
    } 'Attestation CycloneDX locale impossible.'
    Invoke-Checked {
        docker run --rm -v "${publicKeyDirectory}:/trust:ro" -v "${outputMount}:/out" $cosignImage `
            verify-blob-attestation --key "/trust/$publicKeyName" --bundle "/out/$localCycloneAttestationBundleName" --type cyclonedx "/out/$artifactName"
    } 'Vérification de l’attestation CycloneDX locale impossible.'
    if ($Publish) {
        docker push $tag
        if ($LASTEXITCODE -ne 0) { throw 'Publication GHCR impossible.' }
        $digest = (docker buildx imagetools inspect $tag --format '{{.Manifest.Digest}}').Trim()
        if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Digest GHCR introuvable.' }
        $reference = "$Image@$digest"
        $releaseManifestPath = Join-Path $output "gaylemon-$Version-release.json"
        $releaseManifest = [ordered]@{
            schema = 'suite.release.v1'
            contract = 'suite-foundation-v2'
            contractRevision = '2.3.0'
            application = 'gaylemon'
            version = $Version
            commit = $commit
            immutableSource = $true
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
$spdxPath = Join-Path $output "gaylemon-$Version.spdx.json"
$cyclonePath = Join-Path $output "gaylemon-$Version.cdx.json"
$trivyPath = Join-Path $output "gaylemon-$Version-trivy.json"
$scanEvidencePath = Join-Path $output "gaylemon-$Version-scan-evidence.json"
$signatureEvidencePath = Join-Path $output "gaylemon-$Version-signature-evidence.json"
$attestationEvidencePath = Join-Path $output "gaylemon-$Version-attestation-evidence.json"
$spdxAttestationEvidencePath = Join-Path $output "gaylemon-$Version-attestation-spdx-evidence.json"
$cycloneAttestationEvidencePath = Join-Path $output "gaylemon-$Version-attestation-cyclonedx-evidence.json"
[IO.File]::WriteAllText($scanEvidencePath, (([ordered]@{
    schema='suite.security-evidence.v1'; control='scan'; application='gaylemon'; version=$Version; commit=$commit
    artifactDigest=$artifactDigest; result='passed'; verifier=[ordered]@{name='Trivy';command='trivy image --exit-code 1 --severity HIGH,CRITICAL --format json';exitCode=0}
} | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($signatureEvidencePath, (([ordered]@{
    schema='suite.security-evidence.v1'; control='signature'; application='gaylemon'; version=$Version; commit=$commit
    artifactDigest=$artifactDigest; result='passed'; verifier=[ordered]@{name='Cosign';command='cosign verify-blob --key security/cosign.pub --bundle artifact.cosign-bundle.json';exitCode=0}
} | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($attestationEvidencePath, (([ordered]@{
    schema='suite.attestation-evidence.v1'; predicateType=$releasePredicateType; application='gaylemon'; version=$Version; commit=$commit
    artifactDigest=$artifactDigest; result='passed'; verifier=[ordered]@{name='Cosign';command='cosign verify-blob --key security/cosign.pub --bundle local-attestation.cosign-bundle.json local-attestation.json';exitCode=0}
} | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($spdxAttestationEvidencePath, (([ordered]@{
    schema='suite.attestation-evidence.v1'; predicateType='https://spdx.dev/Document'; application='gaylemon'; version=$Version; commit=$commit
    artifactDigest=$artifactDigest; result='passed'; verifier=[ordered]@{name='Cosign';command="cosign verify-blob-attestation --type spdxjson --bundle gaylemon-$Version-spdx-attestation.cosign-bundle.json";exitCode=0}
} | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($cycloneAttestationEvidencePath, (([ordered]@{
    schema='suite.attestation-evidence.v1'; predicateType='cyclonedx'; application='gaylemon'; version=$Version; commit=$commit
    artifactDigest=$artifactDigest; result='passed'; verifier=[ordered]@{name='Cosign';command="cosign verify-blob-attestation --type cyclonedx --bundle gaylemon-$Version-cyclonedx-attestation.cosign-bundle.json";exitCode=0}
} | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
function New-Evidence([string]$Path) {
    [ordered]@{ path = "release/$([IO.Path]::GetFileName($Path))"; sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$receipt = [ordered]@{
    schema='suite.release.v1'; contract='suite-foundation-v2'; contractRevision='2.3.0'; application='gaylemon'; version=$Version; commit=$commit
    source=[ordered]@{kind='digest';value="local:$artifactName@$artifactDigest"}
    artifact=(New-Evidence $artifact); artifactDigest=$artifactDigest
    routes=[ordered]@{count=[int]$validationReceipt.routes.count;sha256=[string]$validationReceipt.routes.sha256}
    validation=[ordered]@{mode='full';receipt=(New-Evidence $validationReceiptPath);result='passed'}
    sbom=[ordered]@{spdx=(New-Evidence $spdxPath);cycloneDx=(New-Evidence $cyclonePath)}
    scan=[ordered]@{status='passed';evidence=(New-Evidence $scanEvidencePath)}
    signature=[ordered]@{status='passed';evidence=(New-Evidence $signatureEvidencePath)}
    attestations=@(
        (New-Evidence $attestationEvidencePath)
        (New-Evidence $spdxAttestationEvidencePath)
        (New-Evidence $cycloneAttestationEvidencePath)
    )
    operations=[ordered]@{
        update='private-operations-authority';backup='private-operations-authority';restore='private-operations-authority'
        health='private-operations-authority';rollback='private-operations-authority'
    }
    result='passed'
}
$releaseReceiptPath = Join-Path $output 'release.json'
[IO.File]::WriteAllText($releaseReceiptPath, (($receipt | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
& python -B (Join-Path $PSScriptRoot 'validate-release-evidence.py') --repository $root --receipt $releaseReceiptPath
if ($LASTEXITCODE -ne 0) { throw 'Le reçu release ne conserve pas les attestations liées exactes.' }
Write-Host "Release préparée: $tag"
