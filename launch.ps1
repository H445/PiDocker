#!/usr/bin/env pwsh
# Windows PowerShell wrapper for launch.sh

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsToForward
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$launchScript = Join-Path $scriptDir 'launch.sh'

if (-not (Test-Path -Path $launchScript -PathType Leaf)) {
    Write-Error "Could not find launch script at '$launchScript'."
}

$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashCmd) {
    Write-Error "Bash was not found in PATH. Install Git Bash/WSL and ensure 'bash' is available."
}

# Delegate to launch.sh to keep container lifecycle and pi startup in one place.
Push-Location $scriptDir
try {
    & $bashCmd.Source ./launch.sh @ArgsToForward
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}


