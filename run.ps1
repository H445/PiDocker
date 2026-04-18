#!/usr/bin/env pwsh
# Interactive menu to manage the pi-agent container

$ErrorActionPreference = 'Stop'
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load active configuration
. "$scriptDir\scripts\_config.ps1"

$CONTAINER    = $ContainerName
$EXT_EXAMPLES = '/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/examples/extensions'
$EXT_USER     = '/root/.pi/extensions'

# ── helpers ────────────────────────────────────────────────────────────────────

function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '  pi-agent  --  management menu' -ForegroundColor Cyan
    Write-Host '  ================================' -ForegroundColor DarkCyan
    Write-Host "  profile: $ActiveProfile ($ContainerName)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [1] Launch pi'                                     -ForegroundColor Green
    Write-Host '  [2] Launch pi with extensions'                     -ForegroundColor Green
    Write-Host '  [3] Open container shell'                          -ForegroundColor Green
    Write-Host '  [4] Provider configuration'                        -ForegroundColor Cyan
    Write-Host '  [5] Backup management'                             -ForegroundColor Magenta
    Write-Host '  [6] Container management'                          -ForegroundColor DarkYellow
    Write-Host '  [7] Setup / switch profile'                        -ForegroundColor Cyan
    Write-Host '  [8] Update pi'                                     -ForegroundColor Yellow
    Write-Host '  [Q] Quit'                                          -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-Script {
    param([string]$Name, [string[]]$ScriptArgs)
    $path = Join-Path $scriptDir $Name
    Push-Location $scriptDir
    try {
        if ($ScriptArgs) { & $path @ScriptArgs }
        else             { & $path }
    }
    finally { Pop-Location }
}

function Assert-ContainerRunning {
    $state = docker inspect -f '{{.State.Running}}' $CONTAINER 2>$null
    if ($state -ne 'true') {
        Write-Host "  Container '$CONTAINER' is not running. Start it first with option [1]." -ForegroundColor Red
        return $false
    }
    return $true
}

# ── open container shell ───────────────────────────────────────────────────────

function Invoke-OpenContainerShell {
    if (-not (Assert-ContainerRunning)) { return }

    $shell = docker exec $CONTAINER sh -lc "if command -v bash >/dev/null 2>&1; then echo bash; elif command -v sh >/dev/null 2>&1; then echo sh; fi" 2>$null
    $shell = ($shell | Select-Object -First 1).Trim()
    if (-not $shell) {
        Write-Host "  No interactive shell found in container '$CONTAINER' (tried bash, sh)." -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host "  Opening $shell shell in container (type 'exit' to return to menu)..." -ForegroundColor DarkCyan
    Write-Host ''
    docker exec -it $CONTAINER $shell
}

# ── backup management ──────────────────────────────────────────────────────────

function Get-BackupFiles {
    $backupDir = Join-Path $scriptDir 'backups'
    if (-not (Test-Path $backupDir)) { return @() }
    return Get-ChildItem -Path $backupDir -Filter '*.tar.gz' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending
}

function Show-BackupList {
    param([System.IO.FileInfo[]]$Files)

    if (-not $Files) {
        Write-Host '  No backups found in backups/' -ForegroundColor Red
        return
    }

    Write-Host '  Available backups:' -ForegroundColor Cyan
    $i = 1
    foreach ($f in $Files) {
        $kb    = [math]::Round($f.Length / 1KB, 1)
        $stamp = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        Write-Host ("  [{0}] {1}  ({2} KB, {3})" -f $i, $f.Name, $kb, $stamp)
        $i++
    }
}

function Invoke-RestoreBackup {
    $files = Get-BackupFiles
    Show-BackupList -Files $files
    if (-not $files) { return }

    Write-Host ''
    $sel = (Read-Host '  Enter number (or path), blank to cancel').Trim()
    if ($sel -eq '') { return }

    if ($sel -match '^\d+$') {
        $idx = [int]$sel - 1
        if ($idx -ge 0 -and $idx -lt $files.Count) {
            Invoke-Script 'scripts\restore.ps1' @($files[$idx].FullName)
        } else {
            Write-Host '  Invalid selection.' -ForegroundColor Red
        }
    } else {
        Invoke-Script 'scripts\restore.ps1' @($sel)
    }
}

function Invoke-DeleteBackup {
    $files = Get-BackupFiles
    Show-BackupList -Files $files
    if (-not $files) { return }

    Write-Host ''
    $sel = (Read-Host '  Enter number (or path) to delete, blank to cancel').Trim()
    if ($sel -eq '') { return }

    $target = $null
    if ($sel -match '^\d+$') {
        $idx = [int]$sel - 1
        if ($idx -ge 0 -and $idx -lt $files.Count) {
            $target = $files[$idx].FullName
        } else {
            Write-Host '  Invalid selection.' -ForegroundColor Red
            return
        }
    } else {
        $target = $sel
    }

    if (-not (Test-Path $target)) {
        Write-Host "  Backup not found: $target" -ForegroundColor Red
        return
    }

    $name = Split-Path $target -Leaf
    $confirm = (Read-Host "  Delete '$name'? (y/N)").Trim().ToUpper()
    if ($confirm -ne 'Y') {
        Write-Host '  Delete canceled.' -ForegroundColor DarkYellow
        return
    }

    Remove-Item -Path $target -Force
    Write-Host '  Backup deleted.' -ForegroundColor Green
}

function Show-BackupMenu {
    Write-Host ''
    Write-Host '  Backup Management' -ForegroundColor Cyan
    Write-Host '  =================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  [1] Create backup'
    Write-Host '  [2] List backups'
    Write-Host '  [3] Restore backup'
    Write-Host '  [4] Delete backup'
    Write-Host ''
    Write-Host '  Press Enter to go back.' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-BackupMenu {
    while ($true) {
        Show-BackupMenu
        $choice = (Read-Host '  Select an option').Trim().ToUpper()
        if ($choice -eq '') { return }
        Write-Host ''
        switch ($choice) {
            '1' { Invoke-Script 'scripts\backup.ps1' }
            '2' { Show-BackupList -Files (Get-BackupFiles) }
            '3' { Invoke-RestoreBackup }
            '4' { Invoke-DeleteBackup }
            default { Write-Host '  Unknown option.' -ForegroundColor Red }
        }
        Write-Host ''
        Read-Host '  Press Enter to continue'
    }
}

# ── container management ───────────────────────────────────────────────────────

function Show-ContainerMenu {
    Write-Host ''
    Write-Host '  Container Management' -ForegroundColor Cyan
    Write-Host '  ====================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  [1] Stop container'
    Write-Host '  [2] Remove container (keep volume)'
    Write-Host '  [3] Container status'
    Write-Host ''
    Write-Host '  Press Enter to go back.' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-ContainerMenu {
    while ($true) {
        Show-ContainerMenu
        $choice = (Read-Host '  Select an option').Trim().ToUpper()
        if ($choice -eq '') { return }
        Write-Host ''
        switch ($choice) {
            '1' {
                Write-Host '  Stopping pi-agent container...'
                docker stop $CONTAINER
            }
            '2' {
                $confirm = (Read-Host '  Remove container? Data volume is preserved. (y/N)').Trim().ToUpper()
                if ($confirm -eq 'Y') { docker rm -f $CONTAINER }
            }
            '3' {
                Write-Host '--- docker ps ---' -ForegroundColor DarkCyan
                docker ps -a --filter "name=$CONTAINER"
                Write-Host ''
                Write-Host '--- docker volume ---' -ForegroundColor DarkCyan
                docker volume ls --filter "name=$VolumeName"
            }
            default { Write-Host '  Unknown option.' -ForegroundColor Red }
        }
        Write-Host ''
        Read-Host '  Press Enter to continue'
    }
}

# ── extension picker ───────────────────────────────────────────────────────────

function Select-Extensions {
    param([bool]$IncludeExamples = $true)

    $findUser = docker exec $CONTAINER bash -c "find '$EXT_USER' -maxdepth 2 \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' \) 2>/dev/null | sort" 2>$null
    $allPaths = @()
    if ($findUser) { $allPaths += $findUser | Where-Object { $_ -ne '' } }

    if ($IncludeExamples) {
        $findExamples = docker exec $CONTAINER bash -c "find '$EXT_EXAMPLES' -maxdepth 1 \( -name '*.ts' -o -name '*.js' \) 2>/dev/null | sort" 2>$null
        if ($findExamples) { $allPaths += $findExamples | Where-Object { $_ -ne '' } }
    }

    if (-not $allPaths) {
        Write-Host '  No extension files found in the container.' -ForegroundColor Red
        Write-Host "  User extensions: $EXT_USER" -ForegroundColor DarkGray
        if ($IncludeExamples) {
            Write-Host "  Examples:        $EXT_EXAMPLES" -ForegroundColor DarkGray
        } else {
            Write-Host '  (Demo/example extensions were excluded.)' -ForegroundColor DarkGray
        }
        return @()
    }

    if ($IncludeExamples) {
        Write-Host '  Available extensions (space = example, * = yours):' -ForegroundColor Cyan
    } else {
        Write-Host '  Available extensions (* = yours):' -ForegroundColor Cyan
    }
    Write-Host ''

    $i = 1
    foreach ($p in $allPaths) {
        $label = if ($p -like "$EXT_USER*") { '* ' } else { '  ' }
        $name  = Split-Path $p -Leaf
        $dir   = Split-Path $p -Parent
        $rel   = $dir -replace [regex]::Escape($EXT_EXAMPLES), '[examples]' `
                      -replace [regex]::Escape($EXT_USER),     '[yours]'
        Write-Host ("  [{0,2}] {1}{2}  {3}" -f $i, $label, $name, $rel) -ForegroundColor White
        $i++
    }

    Write-Host ''
    Write-Host '  Enter numbers to load, separated by spaces or commas (e.g. 1 3 5).' -ForegroundColor DarkGray
    Write-Host '  Press Enter with no input to cancel.' -ForegroundColor DarkGray
    Write-Host ''
    $raw = (Read-Host '  Selection').Trim()
    if (-not $raw) { return @() }

    $indices = $raw -split '[\s,]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $chosen  = @()
    foreach ($idx in $indices) {
        if ($idx -ge 1 -and $idx -le $allPaths.Count) {
            $chosen += $allPaths[$idx - 1]
        } else {
            Write-Host "  Skipping invalid index: $idx" -ForegroundColor DarkYellow
        }
    }
    return $chosen
}

# ── launch with extensions ─────────────────────────────────────────────────────

function Invoke-LaunchWithExtensions {
    if (-not (Assert-ContainerRunning)) { return }

    $raw = (Read-Host '  Include demo/example extensions? (Y/n)').Trim().ToUpper()
    $includeExamples = $raw -ne 'N'

    $chosen = Select-Extensions -IncludeExamples:$includeExamples
    if (-not $chosen) {
        Write-Host '  No extensions selected. Returning to menu.' -ForegroundColor DarkYellow
        return
    }

    Write-Host ''
    Write-Host '  Loading extensions:' -ForegroundColor Cyan
    foreach ($p in $chosen) { Write-Host "    $p" }
    Write-Host ''

    $extArgs = @()
    foreach ($p in $chosen) { $extArgs += '--extension'; $extArgs += $p }

    Write-Host '  Launching pi in container...'
    docker exec -it $CONTAINER pi @extArgs
}

# ── update pi ──────────────────────────────────────────────────────────────────

function Invoke-UpdatePi {
    if (-not (Assert-ContainerRunning)) { return }

    Write-Host '  Updating pi coding agent inside the container...' -ForegroundColor Cyan
    Write-Host ''
    docker exec -it $CONTAINER bash -c 'cd /app && git pull && npm install && npm --workspace packages/tui run build && npm --workspace packages/ai run build && npm --workspace packages/agent run build && npm --workspace packages/coding-agent run build'
    if ($LASTEXITCODE -eq 0) {
        Write-Host ''
        Write-Host '  pi has been updated successfully.' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-Host '  Update failed. Check the output above for errors.' -ForegroundColor Red
    }
}

# ── main loop ──────────────────────────────────────────────────────────────────

while ($true) {
    Show-Menu
    $choice = (Read-Host '  Select an option').Trim().ToUpper()
    Write-Host ''

    switch ($choice) {
        '1' { Invoke-Script 'scripts\launch.ps1'; break }
        '2' { Invoke-LaunchWithExtensions; break }
        '3' { Invoke-OpenContainerShell; break }
        '4' { Invoke-Script 'scripts\localprovider.ps1'; break }
        '5' { Invoke-BackupMenu; break }
        '6' { Invoke-ContainerMenu; break }
        '7' { Invoke-Script 'setup.ps1'; break }
        '8' { Invoke-UpdatePi; break }
        'Q' { Write-Host '  Bye.'; exit 0 }
        default { Write-Host '  Unknown option.' -ForegroundColor Red; break }
    }

    # Pause after output-producing actions so results aren't erased by Clear-Host.
    # Submenus (5, 6) handle their own flow — no extra pause needed.
    if ($choice -notin '5','6','7','8','Q') {
        Write-Host ''
        Read-Host '  Press Enter to return to menu'
    }
}
