#!/usr/bin/env pwsh
# Setup wizard for pi-agent configurations

$ErrorActionPreference = 'Stop'
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir  = Join-Path $scriptDir 'configs'
$activeFile = Join-Path $configDir '.active'

# Ensure configs directory exists
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir | Out-Null
}

# ── helpers ────────────────────────────────────────────────────────────────────

function Get-ActiveProfileName {
    if (Test-Path $activeFile) {
        $content = Get-Content $activeFile -Raw
        if ($content) { return $content.Trim() }
    }
    return $null
}

function Get-AllProfiles {
    $files = Get-ChildItem -Path $configDir -Filter '*.conf' -ErrorAction SilentlyContinue |
             Sort-Object Name
    $profiles = @()
    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $cfg  = @{}
        Get-Content $f.FullName | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $parts = $line -split '=', 2
                if ($parts.Count -eq 2) { $cfg[$parts[0].Trim()] = $parts[1].Trim() }
            }
        }
        # Parse VOLUME_MOUNTS into an array
        $mountList = @()
        if ($cfg['VOLUME_MOUNTS']) {
            $mountList = $cfg['VOLUME_MOUNTS'] -split ';' |
                         Where-Object { $_.Trim() -ne '' } |
                         ForEach-Object { $_.Trim() }
        }
        $profiles += [PSCustomObject]@{
            Name          = $name
            ImageName     = $cfg['IMAGE_NAME']
            ImageTag      = $cfg['IMAGE_TAG']
            ContainerName = $cfg['CONTAINER_NAME']
            VolumeName    = $cfg['VOLUME_NAME']
            VolumeMounts  = $mountList
            FilePath      = $f.FullName
        }
    }
    return $profiles
}

function Get-DockerStatus {
    param([string]$Container, [string]$Volume)

    $containerStatus = 'not found'
    $exists = docker ps -a --format '{{.Names}}' 2>$null | Where-Object { $_ -eq $Container }
    if ($exists) {
        $running = docker ps --format '{{.Names}}' 2>$null | Where-Object { $_ -eq $Container }
        $containerStatus = if ($running) { 'running' } else { 'stopped' }
    }

    $volumeStatus = 'not found'
    $volExists = docker volume ls --format '{{.Name}}' 2>$null | Where-Object { $_ -eq $Volume }
    if ($volExists) { $volumeStatus = 'exists' }

    return @{ Container = $containerStatus; Volume = $volumeStatus }
}

function Show-Header {
    Clear-Host
    Write-Host ''
    Write-Host '  pi-agent  --  setup' -ForegroundColor Cyan
    Write-Host '  ===================' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-ProfileList {
    $active   = Get-ActiveProfileName
    $profiles = Get-AllProfiles

    if (-not $profiles) {
        Write-Host '  No configurations found.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $i = 1
    foreach ($p in $profiles) {
        $isActive = $p.Name -eq $active
        $marker   = if ($isActive) { '*' } else { ' ' }
        $status   = Get-DockerStatus -Container $p.ContainerName -Volume $p.VolumeName
        $cColor   = switch ($status.Container) {
            'running'   { 'Green' }
            'stopped'   { 'DarkYellow' }
            default     { 'DarkGray' }
        }

        Write-Host ("  [{0}] {1} " -f $i, $marker) -NoNewline
        Write-Host $p.Name -ForegroundColor White -NoNewline
        Write-Host ("  {0}:{1}" -f $p.ImageName, $p.ImageTag) -ForegroundColor DarkGray -NoNewline
        Write-Host "  $($p.ContainerName) " -NoNewline
        Write-Host ("({0})" -f $status.Container) -ForegroundColor $cColor
        $i++
    }
    Write-Host ''
}

# ── volume mounts sub-menu ─────────────────────────────────────────────────────

function Invoke-EditVolumeMounts {
    param([string[]]$Current = @())

    $mounts = [System.Collections.Generic.List[string]]($Current)

    while ($true) {
        Write-Host ''
        Write-Host '  Volume Mounts' -ForegroundColor Yellow
        Write-Host '  -------------' -ForegroundColor DarkGray
        Write-Host '  Map host folders into the container (host_path:container_path).' -ForegroundColor DarkGray
        Write-Host ''

        if ($mounts.Count -eq 0) {
            Write-Host '  (none)' -ForegroundColor DarkGray
        } else {
            $i = 1
            foreach ($m in $mounts) {
                Write-Host "  $i. $m"
                $i++
            }
        }

        Write-Host ''
        Write-Host '  [A] Add mount   [R] Remove mount   [C] Clear all   [K] Keep / done' -ForegroundColor DarkGray
        Write-Host ''

        $action = (Read-Host '  Select').Trim().ToUpper()

        switch ($action) {
            'A' {
                $hostPath = (Read-Host '  Host path (e.g. C:\Projects\myapp)').Trim()
                if (-not $hostPath) { Write-Host '  Canceled.' -ForegroundColor DarkYellow; break }
                $ctnPath  = (Read-Host '  Container path (e.g. /workspace)').Trim()
                if (-not $ctnPath) { Write-Host '  Canceled.' -ForegroundColor DarkYellow; break }
                $mounts.Add("${hostPath}:${ctnPath}")
                Write-Host "  ✓ Added: ${hostPath}:${ctnPath}" -ForegroundColor Green
            }
            'R' {
                if ($mounts.Count -eq 0) { Write-Host '  Nothing to remove.' -ForegroundColor DarkYellow; break }
                $num = (Read-Host '  Enter mount number to remove').Trim()
                if ($num -match '^\d+$') {
                    $ridx = [int]$num - 1
                    if ($ridx -ge 0 -and $ridx -lt $mounts.Count) {
                        $removed = $mounts[$ridx]
                        $mounts.RemoveAt($ridx)
                        Write-Host "  ✓ Removed: $removed" -ForegroundColor Green
                    } else {
                        Write-Host '  Invalid number.' -ForegroundColor Red
                    }
                }
            }
            'C' {
                $mounts.Clear()
                Write-Host '  ✓ All mounts cleared.' -ForegroundColor Green
            }
            'K' { return ,$mounts.ToArray() }
            default { Write-Host '  Unknown option.' -ForegroundColor Red }
        }
    }
}

# ── wizard: create & build ─────────────────────────────────────────────────────

function Invoke-SetupWizard {
    # ── Step 1: Profile name ──
    Show-Header
    Write-Host '  Step 1 — Profile Name' -ForegroundColor Yellow
    Write-Host '  ---------------------' -ForegroundColor DarkGray
    Write-Host ''

    $name = (Read-Host '  Name (e.g. default, work, test)').Trim()
    if (-not $name) {
        Write-Host '  Canceled.' -ForegroundColor DarkYellow
        return
    }
    if ($name -notmatch '^[a-zA-Z0-9_-]+$') {
        Write-Host '  Invalid name. Use only letters, numbers, dashes, underscores.' -ForegroundColor Red
        return
    }

    $confPath = Join-Path $configDir "$name.conf"
    if (Test-Path $confPath) {
        Write-Host "  Profile '$name' already exists." -ForegroundColor Red
        return
    }

    # ── Step 2: Docker settings ──
    Write-Host ''
    Write-Host '  Step 2 — Docker Settings' -ForegroundColor Yellow
    Write-Host '  ------------------------' -ForegroundColor DarkGray
    Write-Host '  Press Enter to accept defaults.' -ForegroundColor DarkGray
    Write-Host ''

    $img = (Read-Host "  Image name     [pi-agent]").Trim()
    if (-not $img) { $img = 'pi-agent' }

    $tag = (Read-Host "  Image tag      [latest]").Trim()
    if (-not $tag) { $tag = 'latest' }

    $ctn = (Read-Host "  Container name [$img]").Trim()
    if (-not $ctn) { $ctn = $img }

    $vol = (Read-Host "  Volume name    [$img-data]").Trim()
    if (-not $vol) { $vol = "$img-data" }

    # ── Step 3: Volume mounts ──
    Write-Host ''
    Write-Host '  Step 3 — Volume Mounts' -ForegroundColor Yellow
    Write-Host '  ----------------------' -ForegroundColor DarkGray
    Write-Host '  Optionally map host folders into the container.' -ForegroundColor DarkGray
    $mounts = Invoke-EditVolumeMounts -Current @()

    # ── Step 4: Review ──
    Write-Host ''
    Write-Host '  Step 4 — Review' -ForegroundColor Yellow
    Write-Host '  ---------------' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  Profile:   $name"
    Write-Host "  Image:     ${img}:${tag}"
    Write-Host "  Container: $ctn"
    Write-Host "  Volume:    $vol"
    if ($mounts.Count -gt 0) {
        Write-Host "  Mounts:"
        foreach ($m in $mounts) { Write-Host "    - $m" }
    } else {
        Write-Host "  Mounts:    (none)"
    }
    Write-Host ''

    $confirm = (Read-Host '  Look good? (Y/n)').Trim().ToUpper()
    if ($confirm -eq 'N') {
        Write-Host '  Canceled.' -ForegroundColor DarkYellow
        return
    }

    # Save config
    $mountsLine = if ($mounts.Count -gt 0) { "`nVOLUME_MOUNTS=$($mounts -join ';')" } else { '' }
    $content = @"
IMAGE_NAME=$img
IMAGE_TAG=$tag
CONTAINER_NAME=$ctn
VOLUME_NAME=$vol$mountsLine
"@
    Set-Content -Path $confPath -Value $content -NoNewline
    Set-Content -Path $activeFile -Value $name -NoNewline
    Write-Host ''
    Write-Host "  ✓ Profile '$name' saved and set as active." -ForegroundColor Green

    # ── Step 5: Build ──
    Write-Host ''
    Write-Host '  Step 5 — Build' -ForegroundColor Yellow
    Write-Host '  --------------' -ForegroundColor DarkGray
    Write-Host ''

    $doBuild = (Read-Host '  Build the Docker image now? (Y/n)').Trim().ToUpper()
    if ($doBuild -eq 'N') {
        Write-Host ''
        Write-Host "  Skipped. Run setup again and choose [B] to build later." -ForegroundColor DarkYellow
        return
    }

    Write-Host ''
    Invoke-BuildImage

    Write-Host ''
    Write-Host '  ✓ Setup complete! Run .\run.ps1 to launch pi.' -ForegroundColor Green
}

# ── build ──────────────────────────────────────────────────────────────────────


function Invoke-BuildImage {
    $active = Get-ActiveProfileName
    if (-not $active) {
        Write-Host '  No active profile. Create one first.' -ForegroundColor Red
        return
    }

    $buildScript = Join-Path $scriptDir 'scripts\build.ps1'
    if (-not (Test-Path $buildScript)) {
        Write-Host "  Build script not found: $buildScript" -ForegroundColor Red
        return
    }

    Write-Host "  Building image for profile: $active" -ForegroundColor Cyan
    Write-Host ''

    Push-Location $scriptDir
    try {
        & $buildScript
    }
    finally { Pop-Location }
}

# ── edit ───────────────────────────────────────────────────────────────────────

function Invoke-EditProfile {
    $profiles = Get-AllProfiles
    if (-not $profiles) {
        Write-Host '  No configurations to edit.' -ForegroundColor DarkYellow
        return
    }

    Show-ProfileList

    $sel = (Read-Host '  Enter number to edit (blank to cancel)').Trim()
    if (-not $sel) { return }

    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $profiles.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        return
    }

    $p = $profiles[$idx]

    Write-Host ''
    Write-Host "  Editing: $($p.Name)" -ForegroundColor Cyan
    Write-Host '  Press Enter to keep current value.' -ForegroundColor DarkGray
    Write-Host ''

    $img = (Read-Host "  Image name     [$($p.ImageName)]").Trim()
    if (-not $img) { $img = $p.ImageName }

    $tag = (Read-Host "  Image tag      [$($p.ImageTag)]").Trim()
    if (-not $tag) { $tag = $p.ImageTag }

    $ctn = (Read-Host "  Container name [$($p.ContainerName)]").Trim()
    if (-not $ctn) { $ctn = $p.ContainerName }

    $vol = (Read-Host "  Volume name    [$($p.VolumeName)]").Trim()
    if (-not $vol) { $vol = $p.VolumeName }

    Write-Host ''
    Write-Host '  Volume Mounts' -ForegroundColor Yellow
    Write-Host '  Current:' -ForegroundColor DarkGray
    if ($p.VolumeMounts.Count -gt 0) {
        $p.VolumeMounts | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
    } else {
        Write-Host '    (none)' -ForegroundColor DarkGray
    }
    $mounts = Invoke-EditVolumeMounts -Current $p.VolumeMounts

    $mountsLine = if ($mounts.Count -gt 0) { "`nVOLUME_MOUNTS=$($mounts -join ';')" } else { '' }
    $content = @"
IMAGE_NAME=$img
IMAGE_TAG=$tag
CONTAINER_NAME=$ctn
VOLUME_NAME=$vol$mountsLine
"@
    Set-Content -Path $p.FilePath -Value $content -NoNewline
    Write-Host ''
    Write-Host "  ✓ Profile '$($p.Name)' updated." -ForegroundColor Green

    $rebuild = (Read-Host '  Rebuild the Docker image? (y/N)').Trim().ToUpper()
    if ($rebuild -eq 'Y') {
        Set-Content -Path $activeFile -Value $p.Name -NoNewline
        Write-Host ''
        Invoke-BuildImage
    }
    Write-Host ''
}

# ── delete ─────────────────────────────────────────────────────────────────────

function Invoke-DeleteProfile {
    $profiles = Get-AllProfiles
    if (-not $profiles) {
        Write-Host '  No configurations to delete.' -ForegroundColor DarkYellow
        return
    }

    Show-ProfileList

    $sel = (Read-Host '  Enter number to delete (blank to cancel)').Trim()
    if (-not $sel) { return }

    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $profiles.Count) {
        Write-Host '  Invalid selection.' -ForegroundColor Red
        return
    }

    $p = $profiles[$idx]
    $confirm = (Read-Host "  Delete '$($p.Name)'? This does NOT remove Docker resources. (y/N)").Trim().ToUpper()
    if ($confirm -ne 'Y') {
        Write-Host '  Canceled.' -ForegroundColor DarkYellow
        return
    }

    Remove-Item -Path $p.FilePath -Force
    Write-Host "  ✓ Profile '$($p.Name)' deleted." -ForegroundColor Green

    $active = Get-ActiveProfileName
    if ($active -eq $p.Name) {
        $remaining = Get-AllProfiles
        if ($remaining) {
            Set-Content -Path $activeFile -Value $remaining[0].Name -NoNewline
            Write-Host "  ✓ Active profile switched to '$($remaining[0].Name)'." -ForegroundColor Green
        } else {
            Remove-Item -Path $activeFile -Force -ErrorAction SilentlyContinue
            Write-Host '  No profiles remaining.' -ForegroundColor DarkYellow
        }
    }
    Write-Host ''
}

# ── main ───────────────────────────────────────────────────────────────────────

$profiles = Get-AllProfiles

# First run — go straight into wizard
if (-not $profiles) {
    Show-Header
    Write-Host '  No configurations found. Starting setup wizard...' -ForegroundColor DarkGray
    Write-Host ''
    Invoke-SetupWizard
    Read-Host '  Press Enter to continue'
    $profiles = Get-AllProfiles
    if (-not $profiles) { exit 0 }
}

# Management loop
while ($true) {
    Show-Header

    $active = Get-ActiveProfileName
    Show-ProfileList

    if ($active) {
        Write-Host "  Active: $active" -ForegroundColor Green
    }
    Write-Host ''
    Write-Host '  Enter a number to switch active profile, or:' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [N] New configuration'                -ForegroundColor Green
    Write-Host '  [E] Edit a configuration'             -ForegroundColor Yellow
    Write-Host '  [B] Build / rebuild active image'     -ForegroundColor Yellow
    Write-Host '  [D] Delete a configuration'           -ForegroundColor Red
    Write-Host '  [Q] Done'                             -ForegroundColor DarkGray
    Write-Host ''

    $choice = (Read-Host '  Select').Trim().ToUpper()
    Write-Host ''

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        $all = Get-AllProfiles
        if ($idx -ge 0 -and $idx -lt $all.Count) {
            Set-Content -Path $activeFile -Value $all[$idx].Name -NoNewline
            Write-Host "  ✓ Active profile set to '$($all[$idx].Name)'." -ForegroundColor Green
            Write-Host ''
            Read-Host '  Press Enter to continue'
        } else {
            Write-Host '  Invalid selection.' -ForegroundColor Red
            Read-Host '  Press Enter to continue'
        }
        continue
    }

    switch ($choice) {
        'N' { Invoke-SetupWizard; Read-Host '  Press Enter to continue' }
        'E' { Invoke-EditProfile; Read-Host '  Press Enter to continue' }
        'B' { Invoke-BuildImage;  Read-Host '  Press Enter to continue' }
        'D' { Invoke-DeleteProfile; Read-Host '  Press Enter to continue' }
        'Q' { Write-Host '  Done.'; exit 0 }
        default { Write-Host '  Unknown option.' -ForegroundColor Red; Read-Host '  Press Enter to continue' }
    }
}

