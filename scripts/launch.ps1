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

if ($existing -contains $ContainerName) {
    # Try to start the existing container
    & $dockerCmd.Source start $ContainerName 2>$null | Out-Null

    # Verify it's actually running
    $state = & $dockerCmd.Source inspect -f '{{.State.Running}}' $ContainerName 2>$null
    if ($state -ne 'true') {
        Write-Host "Container '$ContainerName' won't stay running. Recreating..."
        & $dockerCmd.Source rm -f $ContainerName | Out-Null
        & $dockerCmd.Source run -d --name $ContainerName -v "${VolumeName}:/root" -v '/var/run/docker.sock:/var/run/docker.sock' "${ImageName}:${ImageTag}" 'tail' '-f' '/dev/null' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to recreate container '$ContainerName'. Run setup to build the image first."
        }
    } else {
        Write-Host "Container '$ContainerName' is running."
    }
}
else {
    Write-Host "Creating new persistent container: $ContainerName"
    & $dockerCmd.Source run -d --name $ContainerName -v "${VolumeName}:/root" -v '/var/run/docker.sock:/var/run/docker.sock' "${ImageName}:${ImageTag}" 'tail' '-f' '/dev/null' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create container '$ContainerName' from image '${ImageName}:${ImageTag}'. Run .\setup.ps1 to build the image first."
    }
}

Write-Host 'Launching pi in container...'
& $dockerCmd.Source exec -it $ContainerName pi
exit $LASTEXITCODE
