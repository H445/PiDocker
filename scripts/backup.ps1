#!/usr/bin/env pwsh
# Create a timestamped backup of pi-agent container data

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Load active configuration
. "$PSScriptRoot\_config.ps1"

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Error "Docker was not found in PATH. Install Docker Desktop and ensure 'docker' is available."
}

$backupDir  = Join-Path (Split-Path $PSScriptRoot -Parent) 'backups'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = "$ContainerName-backup-$timestamp.tar.gz"

# Ensure backup directory exists
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

# Check volume exists
$volume = & docker volume ls --format '{{.Name}}' 2>$null | Where-Object { $_ -eq $VolumeName }
if (-not $volume) {
    Write-Error "No $VolumeName volume found. Nothing to backup."
}

Write-Host "Creating backup: backups/$backupFile"

# Docker requires forward-slash paths for volume mounts; convert Windows path.
$backupDirUnix = $backupDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'

& docker run --rm `
    -v "${VolumeName}:/data" `
    -v "${backupDirUnix}:/backup" `
    alpine tar czf "/backup/$backupFile" -C /data .

if ($LASTEXITCODE -eq 0) {
    $info = Get-Item (Join-Path $backupDir $backupFile)
    $sizeKb = [math]::Round($info.Length / 1KB, 1)
    Write-Host "Backup created: backups/$backupFile ($sizeKb KB)"
} else {
    Write-Error 'Backup failed.'
}

