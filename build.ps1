#!/usr/bin/env pwsh
# Build the pi-agent Docker image from PowerShell

[CmdletBinding()]
param(
    [string]$ImageName = 'pi-agent',
    [string]$ImageTag = 'latest',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DockerBuildArgs
)

$ErrorActionPreference = 'Stop'

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Error "Docker was not found in PATH. Install Docker Desktop and ensure 'docker' is available."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tag = "$ImageName`:$ImageTag"

Write-Host "Building Docker image: $tag"

Push-Location $scriptDir
try {
    $dockerArgs = @('build', '-t', $tag)
    if ($DockerBuildArgs) {
        $dockerArgs += $DockerBuildArgs
    }
    $dockerArgs += '.'

    & $dockerCmd.Source @dockerArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Image built successfully: $tag"
        exit 0
    }

    Write-Error "Build failed"
}
finally {
    Pop-Location
}


