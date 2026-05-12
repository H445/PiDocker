#!/usr/bin/env pwsh
# Build the pi-agent Docker image and start the container

$ErrorActionPreference = 'Stop'

# Load active configuration
. "$PSScriptRoot\_config.ps1"

$tag = "$ImageName`:$ImageTag"
$piPackageName = '@mariozechner/pi-coding-agent'

Write-Host "Building Docker image: $tag"
Write-Host "Installing latest published pi package during build: $piPackageName@latest"

docker build --pull --no-cache `
    --build-arg 'PI_PACKAGE_NAME=@mariozechner/pi-coding-agent' `
    --build-arg 'PI_PACKAGE_VERSION=latest' `
    -t $tag .

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Image built successfully: $tag"
    $imageVersion = docker run --rm $tag pi --version 2>&1 |
        ForEach-Object { "$_" } |
        Select-Object -First 1
    if ($imageVersion) {
        Write-Host "  Image pi version: $($imageVersion.Trim())" -ForegroundColor DarkGray
    }
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
    @PortMappingArgs `
    $tag `
    tail -f /dev/null

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Container started successfully"
    $containerVersion = docker exec $ContainerName pi --version 2>&1 |
        ForEach-Object { "$_" } |
        Select-Object -First 1
    if ($containerVersion) {
        Write-Host "  Container pi version: $($containerVersion.Trim())" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host "Next steps:"
    Write-Host "  1. Configure local providers (optional): .\run.ps1 → [4]"
    Write-Host "  2. Launch pi: .\run.ps1 → [1]"
} else {
    Write-Host "✗ Failed to start container" -ForegroundColor Red
    exit 1
}
