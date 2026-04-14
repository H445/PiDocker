#!/usr/bin/env pwsh
# Build the pi-agent Docker image and start the container

$ErrorActionPreference = 'Stop'

# Load active configuration
. "$PSScriptRoot\_config.ps1"

$tag = "$ImageName`:$ImageTag"

Write-Host "Building Docker image: $tag"

docker build -t $tag .

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Image built successfully: $tag"
} else {
    Write-Host "✗ Build failed" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "Starting container: $ContainerName"

# Check if container already exists
$existingContainer = docker ps -a --format '{{.Names}}' 2>$null | Where-Object { $_ -eq $ContainerName }

if ($existingContainer) {
    # Remove old container so we can recreate with the new image
    Write-Host "Removing old container..."
    docker rm -f $ContainerName | Out-Null
}

Write-Host "Creating new container and volume..."
# Check if volume exists, if not create it
$volumeExists = docker volume ls --format '{{.Name}}' 2>$null | Where-Object { $_ -eq $VolumeName }
if (-not $volumeExists) {
    docker volume create $VolumeName
}
# Create and start container with a keep-alive command
docker run -d `
    --name $ContainerName `
    -v "${VolumeName}:/root" `
    -v '/var/run/docker.sock:/var/run/docker.sock' `
    $tag `
    tail -f /dev/null

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Container started successfully"
    Write-Host ''
    Write-Host "Next steps:"
    Write-Host "  1. Configure local providers (optional): .\run.ps1 → [4]"
    Write-Host "  2. Launch pi: .\run.ps1 → [1]"
} else {
    Write-Host "✗ Failed to start container" -ForegroundColor Red
    exit 1
}
