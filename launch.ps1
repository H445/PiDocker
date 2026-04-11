#!/usr/bin/env pwsh
# Launch the pi-agent Docker container persistently (PowerShell-native)

[CmdletBinding()]
param(
    [string]$ContainerName = 'pi-agent',
    [string]$ImageName = 'pi-agent:latest'
)

$ErrorActionPreference = 'Stop'

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
    Write-Host "Container '$ContainerName' already exists. Starting it..."
    & $dockerCmd.Source start $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to start container '$ContainerName'."
    }
}
else {
    Write-Host "Creating new persistent container: $ContainerName"
    & $dockerCmd.Source run -d --name $ContainerName -v 'pi-agent-data:/root' -v '/var/run/docker.sock:/var/run/docker.sock' $ImageName 'tail' '-f' '/dev/null' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create container '$ContainerName' from image '$ImageName'. Build the image first (menu option [4])."
    }
}

Write-Host 'Launching pi in container...'
& $dockerCmd.Source exec -it $ContainerName pi
exit $LASTEXITCODE
