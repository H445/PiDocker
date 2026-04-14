#!/usr/bin/env pwsh
# Configure local LLM providers (LMStudio, Ollama) and save to pi models config in container

$ErrorActionPreference = 'Stop'
$scriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load active configuration
. "$scriptDir\_config.ps1"

$CONTAINER     = $ContainerName
$PI_MODELS_PATH = '/root/.pi/agent/models.json'

# ── helpers ────────────────────────────────────────────────────────────────────

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '  local provider configuration' -ForegroundColor Cyan
    Write-Host '  ============================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  [1] Configure LMStudio' -ForegroundColor Green
    Write-Host '  [2] Configure Ollama'   -ForegroundColor Green
    Write-Host '  [3] View current config' -ForegroundColor Yellow
    Write-Host '  [4] Clear all providers' -ForegroundColor Red
    Write-Host '  [Q] Done'               -ForegroundColor DarkGray
    Write-Host ''
}

function Assert-ContainerRunning {
    $state = docker inspect -f '{{.State.Running}}' $CONTAINER 2>$null
    if ($state -ne 'true') {
        Write-Host "  Container '$CONTAINER' is not running. Start it first." -ForegroundColor Red
        return $false
    }
    return $true
}

function Read-OrDefault {
    param([string]$Prompt, [string]$Default)
    $value = (Read-Host $Prompt).Trim()
    if ($value -eq '') { return $Default }
    return $value
}

function Get-CurrentConfig {
    $existing = docker exec $CONTAINER cat $PI_MODELS_PATH 2>$null
    if ($existing) { return $existing }
    return '{}'
}

# ── configure LMStudio ─────────────────────────────────────────────────────────

function Invoke-ConfigureLMStudio {
    if (-not (Assert-ContainerRunning)) { return }

    Clear-Host
    Write-Host ''
    Write-Host '  ⚠️  LMStudio Configuration' -ForegroundColor Yellow
    Write-Host '  =====================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  WARNING: LMStudio must be running on your system for setup to work.' -ForegroundColor DarkRed
    Write-Host '  LMStudio typically runs on http://localhost:1234/v1' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  NOTE: If LMStudio runs on your host machine (not in the container),' -ForegroundColor DarkGray
    Write-Host '  use http://host.docker.internal:1234/v1 on Docker Desktop (Windows/Mac)' -ForegroundColor DarkGray
    Write-Host '  or http://<your-host-ip>:1234/v1 on Linux.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Provide the API endpoint where LMStudio is accessible FROM THE CONTAINER.' -ForegroundColor DarkGray
    Write-Host ''

    $url = Read-OrDefault '  API URL (default http://host.docker.internal:1234/v1): ' 'http://host.docker.internal:1234/v1'
    Write-Host ''
    Write-Host '  Fetching available models from LMStudio...' -ForegroundColor DarkCyan

    # Poll LMStudio for available models
    try {
        $response = Invoke-WebRequest -Uri "$url/models" -UseBasicParsing -ErrorAction Stop
        $modelsJson = $response.Content | ConvertFrom-Json
    } catch {
        Write-Host "  ✗ Could not reach LMStudio at $url" -ForegroundColor Red
        Write-Host "  Make sure it's running and accessible." -ForegroundColor Red
        return
    }

    $availableModels = @()
    if ($modelsJson.data) {
        $availableModels = @($modelsJson.data | ForEach-Object { if ($_.id) { $_.id } } | Sort-Object)
    }

    if ($availableModels.Count -eq 0) {
        Write-Host "  ✗ No models found. Load a model in LMStudio first." -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  Available models:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $availableModels.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $availableModels[$i])
    }

    Write-Host ''
    Write-Host '  Enter numbers to add, separated by spaces or commas (e.g. 1 3).' -ForegroundColor DarkGray
    $raw = (Read-Host '  Selection (blank to cancel)').Trim()
    if (-not $raw) { return }

    $indices = $raw -split '[\s,]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $selectedModels = @()
    foreach ($idx in $indices) {
        if ($idx -ge 1 -and $idx -le $availableModels.Count) {
            $selectedModels += $availableModels[$idx - 1]
        } else {
            Write-Host "  Skipping invalid index: $idx" -ForegroundColor Yellow
        }
    }

    if ($selectedModels.Count -eq 0) {
        Write-Host '  No valid models selected.' -ForegroundColor Red
        return
    }

    # Build the provider config
    $config = Get-CurrentConfig | ConvertFrom-Json -AsHashtable
    if (-not $config.providers) { $config.providers = @{} }

    # Build models array
    $modelsArray = @()
    foreach ($model in $selectedModels) {
        $modelsArray += @{ 'id' = $model }
    }

    # Add provider with selected models
    $config.providers['lmstudio'] = @{
        'baseUrl' = $url
        'api'     = 'openai-completions'
        'apiKey'  = 'lmstudio'
        'models'  = $modelsArray
    }

    $json = $config | ConvertTo-Json -Depth 10
    $json | docker exec -i $CONTAINER bash -c "mkdir -p $(Split-Path $PI_MODELS_PATH -Parent) && cat > $PI_MODELS_PATH"

    Write-Host ''
    Write-Host ("  ✅ LMStudio configuration saved with {0} model(s)." -f $selectedModels.Count) -ForegroundColor Green
    Write-Host ''
}

# ── configure Ollama ──────────────────────────────────────────────────────────

function Invoke-ConfigureOllama {
    if (-not (Assert-ContainerRunning)) { return }

    Clear-Host
    Write-Host ''
    Write-Host '  ⚠️  Ollama Configuration' -ForegroundColor Yellow
    Write-Host '  =====================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  WARNING: Ollama must be running on your system for setup to work.' -ForegroundColor DarkRed
    Write-Host '  Ollama typically runs on http://localhost:11434/v1' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  NOTE: If Ollama runs on your host machine (not in the container),' -ForegroundColor DarkGray
    Write-Host '  use http://host.docker.internal:11434/v1 on Docker Desktop (Windows/Mac)' -ForegroundColor DarkGray
    Write-Host '  or http://<your-host-ip>:11434/v1 on Linux.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Provide the API endpoint where Ollama is accessible FROM THE CONTAINER.' -ForegroundColor DarkGray
    Write-Host ''

    $url = Read-OrDefault '  API URL (default http://host.docker.internal:11434/v1): ' 'http://host.docker.internal:11434/v1'
    Write-Host ''
    Write-Host '  Fetching available models from Ollama...' -ForegroundColor DarkCyan

    # Poll Ollama for available models
    try {
        $response = Invoke-WebRequest -Uri "$url/models" -UseBasicParsing -ErrorAction Stop
        $modelsJson = $response.Content | ConvertFrom-Json
    } catch {
        Write-Host "  ✗ Could not reach Ollama at $url" -ForegroundColor Red
        Write-Host "  Make sure it's running and accessible." -ForegroundColor Red
        return
    }

    $availableModels = @()
    if ($modelsJson.data) {
        $availableModels = @($modelsJson.data | ForEach-Object { if ($_.id) { $_.id } } | Sort-Object)
    }

    if ($availableModels.Count -eq 0) {
        Write-Host "  ✗ No models found. Pull a model in Ollama first (e.g. ollama pull llama2)." -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  Available models:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $availableModels.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $availableModels[$i])
    }

    Write-Host ''
    Write-Host '  Enter numbers to add, separated by spaces or commas (e.g. 1 3).' -ForegroundColor DarkGray
    $raw = (Read-Host '  Selection (blank to cancel)').Trim()
    if (-not $raw) { return }

    $indices = $raw -split '[\s,]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $selectedModels = @()
    foreach ($idx in $indices) {
        if ($idx -ge 1 -and $idx -le $availableModels.Count) {
            $selectedModels += $availableModels[$idx - 1]
        } else {
            Write-Host "  Skipping invalid index: $idx" -ForegroundColor Yellow
        }
    }

    if ($selectedModels.Count -eq 0) {
        Write-Host '  No valid models selected.' -ForegroundColor Red
        return
    }

    # Build the provider config
    $config = Get-CurrentConfig | ConvertFrom-Json -AsHashtable
    if (-not $config.providers) { $config.providers = @{} }

    # Build models array
    $modelsArray = @()
    foreach ($model in $selectedModels) {
        $modelsArray += @{ 'id' = $model }
    }

    # Add provider with selected models
    $config.providers['ollama'] = @{
        'baseUrl' = $url
        'api'     = 'openai-completions'
        'apiKey'  = 'ollama'
        'models'  = $modelsArray
    }

    $json = $config | ConvertTo-Json -Depth 10
    $json | docker exec -i $CONTAINER bash -c "mkdir -p $(Split-Path $PI_MODELS_PATH -Parent) && cat > $PI_MODELS_PATH"

    Write-Host ''
    Write-Host ("  ✅ Ollama configuration saved with {0} model(s)." -f $selectedModels.Count) -ForegroundColor Green
    Write-Host ''
}

# ── view current config ────────────────────────────────────────────────────────

function Invoke-ViewConfig {
    if (-not (Assert-ContainerRunning)) { return }

    Clear-Host
    Write-Host ''
    Write-Host '  Current Provider Configuration' -ForegroundColor Cyan
    Write-Host '  ============================' -ForegroundColor DarkCyan
    Write-Host ''

    $config = docker exec $CONTAINER cat $PI_MODELS_PATH 2>$null

    if (-not $config) {
        Write-Host '  No custom providers configured yet.' -ForegroundColor DarkYellow
        Write-Host ("  (File: {0})" -f $PI_MODELS_PATH) -ForegroundColor DarkGray
    } else {
        try {
            $json = $config | ConvertFrom-Json
            $config | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $config
        }
    }
    Write-Host ''
}

# ── clear all providers ────────────────────────────────────────────────────────

function Invoke-ClearProviders {
    if (-not (Assert-ContainerRunning)) { return }

    $confirm = (Read-Host '  Clear all provider configurations? (y/N)').Trim().ToUpper()
    if ($confirm -ne 'Y') {
        Write-Host '  Canceled.' -ForegroundColor DarkYellow
        return
    }

    docker exec $CONTAINER bash -c "mkdir -p $(Split-Path $PI_MODELS_PATH -Parent) && echo '{}' > $PI_MODELS_PATH"
    Write-Host '  ✅ All provider configurations cleared.' -ForegroundColor Green
    Write-Host ''
}

# ── main loop ──────────────────────────────────────────────────────────────────

while ($true) {
    Show-Menu
    $choice = (Read-Host '  Select an option').Trim().ToUpper()
    Write-Host ''

    switch ($choice) {
        '1' { Invoke-ConfigureLMStudio }
        '2' { Invoke-ConfigureOllama }
        '3' { Invoke-ViewConfig }
        '4' { Invoke-ClearProviders }
        'Q' { Write-Host '  Done.'; exit 0 }
        default { Write-Host '  Unknown option.' -ForegroundColor Red }
    }

    if ($choice -ne 'Q') {
        Read-Host '  Press Enter to continue'
    }
}
