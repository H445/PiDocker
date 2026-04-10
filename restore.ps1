#!/usr/bin/env pwsh
# Restore pi-agent data from a backup archive
[CmdletBinding()]
param([Parameter(Position=0)][string]$BackupFile)
$ErrorActionPreference = 'Stop'
$CONTAINER = 'pi-agent'; $IMAGE = 'pi-agent:latest'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Error 'docker not found.' }
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupDir = Join-Path $scriptDir 'backups'
if (-not $BackupFile) {
    Write-Host 'Available backups:'
    $files = Get-ChildItem -Path $backupDir -Filter '*.tar.gz' -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $files) { Write-Host '  No backups found in backups/'; exit 1 }
    $i=1; foreach ($f in $files) { $kb=[math]::Round($f.Length/1KB,1); Write-Host "  [$i] $($f.Name) ($kb KB)"; $i++ }
    Write-Host ''; Write-Host 'Usage: .\restore.ps1 backups\<file>.tar.gz'; exit 0
}
$resolved = if ([IO.Path]::IsPathRooted($BackupFile)) { $BackupFile } else { Join-Path $scriptDir $BackupFile }
if (-not (Test-Path $resolved)) { Write-Error "File not found: $resolved" }
Write-Host "Restoring from: $resolved"
$r = docker ps  --filter "name=^${CONTAINER}$" --format '{{.Names}}'
if ($r) { Write-Host 'Stopping...'; docker stop $CONTAINER | Out-Null }
$e = docker ps -a --filter "name=^${CONTAINER}$" --format '{{.Names}}'
if ($e) { Write-Host 'Removing container...'; docker rm $CONTAINER | Out-Null }
$v = docker volume ls --filter 'name=pi-agent-data' --format '{{.Name}}'
if ($v) { Write-Host 'Removing volume...'; docker volume rm pi-agent-data | Out-Null }
Write-Host 'Creating volume...'; docker volume create pi-agent-data | Out-Null
Write-Host 'Extracting backup...'
$mdir = (Split-Path $resolved -Parent) -replace '\\','/' -replace '^([A-Za-z]):','/$1'
$mfile = Split-Path $resolved -Leaf
docker run --rm -v 'pi-agent-data:/data' -v "${mdir}:/backup" alpine tar xzf "/backup/$mfile" -C /data
if ($LASTEXITCODE -ne 0) { Write-Error 'Extraction failed.' }
Write-Host 'Recreating container...'
docker run -d --name $CONTAINER -v 'pi-agent-data:/root' -v '/var/run/docker.sock:/var/run/docker.sock' $IMAGE tail -f /dev/null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host 'Restored. Run .\launch.ps1 to start.' } else { Write-Error 'Restore failed.' }
