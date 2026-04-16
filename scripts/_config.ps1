#!/usr/bin/env pwsh
# Shared config loader — dot-source this from any script:
#   . "$PSScriptRoot\_config.ps1"   (from scripts/)
#   . "$scriptDir\scripts\_config.ps1"  (from root)
# Provides: $ImageName, $ImageTag, $ContainerName, $VolumeName, $ActiveProfile

# $PSScriptRoot in a dot-sourced file equals the CALLING script's PSScriptRoot.
# Callers may be in root/ (run.ps1) or scripts/ (build.ps1 etc.).
# Try both locations to find configs/.
$_try1      = Join-Path $PSScriptRoot 'configs'
$_try2      = Join-Path (Split-Path $PSScriptRoot -Parent) 'configs'
$_configDir = if (Test-Path $_try1) { $_try1 } else { $_try2 }
$_activeFile = Join-Path $_configDir '.active'

if (-not (Test-Path $_activeFile)) {
    Write-Host 'No active configuration found. Run .\setup.ps1 first.' -ForegroundColor Red
    exit 1
}

$_activeContent = Get-Content $_activeFile -Raw
if (-not $_activeContent) {
    Write-Host 'Active configuration file is empty. Run .\setup.ps1 first.' -ForegroundColor Red
    exit 1
}
$ActiveProfile = $_activeContent.Trim()
$_confFile     = Join-Path $_configDir "$ActiveProfile.conf"

if (-not (Test-Path $_confFile)) {
    Write-Host "Active profile '$ActiveProfile' not found at $_confFile. Run .\setup.ps1 to fix." -ForegroundColor Red
    exit 1
}

# Parse key=value pairs
Get-Content $_confFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            Set-Variable -Name $parts[0].Trim() -Value $parts[1].Trim() -Scope Script
        }
    }
}

# Map to friendly variable names used by all scripts
$ImageName     = $IMAGE_NAME
$ImageTag      = $IMAGE_TAG
$ContainerName = $CONTAINER_NAME
$VolumeName    = $VOLUME_NAME

# Parse VOLUME_MOUNTS (semicolon-separated list of host_path:container_path)
# Example in .conf:  VOLUME_MOUNTS=C:\Projects\app:/workspace;C:\data:/data
$VolumeMounts = @()
if ($VOLUME_MOUNTS) {
    $VolumeMounts = $VOLUME_MOUNTS -split ';' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }
}

