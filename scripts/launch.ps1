#!/usr/bin/env pwsh
# Launch the pi-agent Docker container persistently (PowerShell-native)

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Load active configuration
. "$PSScriptRoot\_config.ps1"

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Error "Docker was not found in PATH. Install Docker Desktop and ensure 'docker' is available."
}

# ── Mount-config fingerprint ──────────────────────────────────────────────────
# Build a canonical string that represents the current mount configuration.
# We save this to a file when creating/recreating the container and compare it
# on the next launch.  This avoids all the issues with docker inspect returning
# rewritten paths on Docker Desktop (Windows/Mac).
$_configDir = if (Test-Path (Join-Path $PSScriptRoot 'configs')) {
    Join-Path $PSScriptRoot 'configs'
} else {
    Join-Path (Split-Path $PSScriptRoot -Parent) 'configs'
}
$_mountFingerprintFile = Join-Path $_configDir ".mounts_${ContainerName}"

function Get-MountFingerprint {
    # Deterministic string: volume name + sorted extra mounts
    $parts = @("volume=${VolumeName}:/root")
    foreach ($m in ($VolumeMounts | Sort-Object)) {
        $parts += "bind=$m"
    }
    return ($parts -join "`n")
}

$currentFingerprint = Get-MountFingerprint

function Save-MountFingerprint {
    $currentFingerprint | Set-Content -Path $_mountFingerprintFile -NoNewline -Encoding UTF8
}

function Test-MountFingerprintMatch {
    if (-not (Test-Path $_mountFingerprintFile)) { return $false }
    $saved = Get-Content $_mountFingerprintFile -Raw -Encoding UTF8
    return ($saved -eq $currentFingerprint)
}

# ── Docker helpers ────────────────────────────────────────────────────────────

# Check if container already exists
$existing = & $dockerCmd.Source ps -a --filter "name=^${ContainerName}$" --format '{{.Names}}'
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to query Docker containers. Is Docker Desktop running?'
}

# Build extra -v args from VOLUME_MOUNTS defined in the profile
$extraVolArgs = @()
foreach ($mount in $VolumeMounts) {
    $extraVolArgs += '-v'
    $extraVolArgs += $mount
}

# Helper: run docker run with all volume args
function Invoke-DockerRun {
    & $dockerCmd.Source run -d --name $ContainerName `
        -v "${VolumeName}:/root" `
        -v '/var/run/docker.sock:/var/run/docker.sock' `
        @extraVolArgs `
        "${ImageName}:${ImageTag}" 'tail' '-f' '/dev/null' | Out-Null
    # Save fingerprint so next launch knows the config hasn't changed
    Save-MountFingerprint
}

# ── main ──────────────────────────────────────────────────────────────────────
if ($existing -contains $ContainerName) {
    # Container exists — compare saved mount fingerprint to current config
    if (-not (Test-MountFingerprintMatch)) {
        Write-Host "Container '$ContainerName' mount config has changed. Recreating..." -ForegroundColor Yellow
        & $dockerCmd.Source rm -f $ContainerName | Out-Null
        Invoke-DockerRun
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to recreate container '$ContainerName'. Run setup to build the image first."
        }
    } else {
        # Mounts are correct — just make sure it's running
        & $dockerCmd.Source start $ContainerName 2>$null | Out-Null

        $state = & $dockerCmd.Source inspect -f '{{.State.Running}}' $ContainerName 2>$null
        if ($state -ne 'true') {
            Write-Host "Container '$ContainerName' won't stay running. Recreating..." -ForegroundColor Yellow
            & $dockerCmd.Source rm -f $ContainerName | Out-Null
            Invoke-DockerRun
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to recreate container '$ContainerName'. Run setup to build the image first."
            }
        } else {
            Write-Host "Container '$ContainerName' is running."
        }
    }
}
else {
    Write-Host "Creating new persistent container: $ContainerName"
    Invoke-DockerRun
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create container '$ContainerName' from image '${ImageName}:${ImageTag}'. Run .\setup.ps1 to build the image first."
    }
}

Write-Host 'Launching pi in container...'
& $dockerCmd.Source exec -it $ContainerName pi
exit $LASTEXITCODE
