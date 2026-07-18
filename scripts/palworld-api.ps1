param(
    [ValidateSet("info", "players", "metrics", "settings", "game-data")]
    [string]$Endpoint = "info"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$remoteApiScript = "$($config.RemoteSteamRoot)/bin/palworld-api.sh"

function Invoke-NativeCapture {
    param([Parameter(Mandatory = $true)] [scriptblock]$ScriptBlock)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $ScriptBlock 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        Output = $output
        ExitCode = $exitCode
    }
}

function Get-RemotePalworldAdminPassword {
    $settingsPath = "$($config.RemotePalworldRoot)/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini"
    $settingsResult = Invoke-NativeCapture {
        ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "cat '$settingsPath'"
    }
    if ($settingsResult.ExitCode -ne 0) {
        $rawSettings = $settingsResult.Output
        $details = (($rawSettings | Out-String).Trim())
        throw "Lecture de la configuration Palworld impossible via SSH. $details"
    }

    $rawSettings = $settingsResult.Output
    $match = [regex]::Match(($rawSettings | Out-String), 'AdminPassword="([^"]*)"')
    if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups[1].Value)) {
        throw "AdminPassword est absent de la configuration Palworld distante."
    }

    return $match.Groups[1].Value
}

function Invoke-LocalTunnelApi {
    $script:LocalTunnelExitCode = 1
    $password = Get-RemotePalworldAdminPassword
    $credentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:$password"))
    $uri = "http://127.0.0.1:$($config.ApiLocalPort)/v1/api/$Endpoint"

    try {
        $response = Invoke-WebRequest `
            -Uri $uri `
            -Headers @{ Authorization = "Basic $credentials" } `
            -UseBasicParsing `
            -TimeoutSec 15
        Write-Output $response.Content
        $script:LocalTunnelExitCode = 0
        return
    }
    catch {
        $response = $_.Exception.Response
        if ($response) {
            $statusCode = [int]$response.StatusCode
            $body = ""
            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = [IO.StreamReader]::new($stream)
                    $body = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            }
            catch {
                $body = ""
            }

            [Console]::Error.WriteLine(("HTTP {0}. {1}" -f $statusCode, $body.Trim()))
            return
        }

        [Console]::Error.WriteLine($_.Exception.Message)
        return
    }
}

$remoteResult = Invoke-NativeCapture {
    ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "$remoteApiScript GET /$Endpoint"
}
$remoteOutput = $remoteResult.Output
$remoteExitCode = $remoteResult.ExitCode
if ($remoteExitCode -eq 0) {
    Write-Output $remoteOutput
    exit 0
}

$remoteError = ($remoteOutput | Out-String).Trim()
if ($remoteExitCode -eq 126 -or $remoteError -match "Permission denied") {
    $sudoResult = Invoke-NativeCapture {
        ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "sudo -n $remoteApiScript GET /$Endpoint"
    }
    $sudoOutput = $sudoResult.Output
    $sudoExitCode = $sudoResult.ExitCode
    if ($sudoExitCode -eq 0) {
        Write-Output $sudoOutput
        exit 0
    }

    $sudoError = ($sudoOutput | Out-String).Trim()
    if ($sudoError -and $sudoError -notmatch "(?i)sudo:|password|not allowed|not permitted|Permission denied") {
        [Console]::Error.WriteLine($sudoError)
        exit $sudoExitCode
    }

    Invoke-LocalTunnelApi
    exit $script:LocalTunnelExitCode
}

[Console]::Error.WriteLine($remoteError)
exit $remoteExitCode
