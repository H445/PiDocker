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
}

# Helper: check if the running container's mounts match the profile config
function Test-ContainerMountsMatch {
    # Use .Name for named volumes, .Source for bind mounts — avoids comparing
    # raw host paths like /var/lib/docker/volumes/... against the volume name
    $actualMounts = & $dockerCmd.Source inspect `
        --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}:{{.Destination}} {{end}}' `
        $ContainerName 2>$null

    # Named volume
    if ($actualMounts -notlike "*${VolumeName}:/root*") { return $false }

    # Extra mounts from profile
    foreach ($mount in $VolumeMounts) {
        if ($actualMounts -notlike "*${mount}*") { return $false }
    }
    return $true
}

# ── main ──────────────────────────────────────────────────────────────────────
if ($existing -contains $ContainerName) {
    # Container exists — verify mounts match before reusing it
    if (-not (Test-ContainerMountsMatch)) {
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
