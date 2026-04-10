#!/usr/bin/env pwsh
# Create a timestamped backup of pi-agent container data

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Error "Docker was not found in PATH. Install Docker Desktop and ensure 'docker' is available."
}

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupDir  = Join-Path $scriptDir 'backups'
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = "pi-agent-backup-$timestamp.tar.gz"

# Ensure backup directory exists
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

# Check volume exists
$volume = & docker volume ls --filter 'name=pi-agent-data' --format '{{.Name}}' 2>$null
if ($volume -notmatch 'pi-agent-data') {
    Write-Error 'No pi-agent-data volume found. Nothing to backup.'
}

Write-Host "Creating backup: backups/$backupFile"

# Docker requires forward-slash paths for volume mounts; convert Windows path.
$backupDirUnix = $backupDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'

& docker run --rm `
    -v 'pi-agent-data:/data' `
    -v "${backupDirUnix}:/backup" `
    alpine tar czf "/backup/$backupFile" -C /data .

if ($LASTEXITCODE -eq 0) {
    $info = Get-Item (Join-Path $backupDir $backupFile)
    $sizeKb = [math]::Round($info.Length / 1KB, 1)
    Write-Host "Backup created: backups/$backupFile ($sizeKb KB)"
} else {
    Write-Error 'Backup failed.'
}

