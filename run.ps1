#!/usr/bin/env pwsh
# Interactive menu to run pi-agent management scripts
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CONTAINER  = 'pi-agent'
$EXT_EXAMPLES = '/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/examples/extensions'
$EXT_USER     = '/root/.pi/extensions'
# ── helpers ────────────────────────────────────────────────────────────────────
function Show-Menu {
    Clear-Host
    Write-Host ''
    Write-Host '  pi-agent  --  management menu' -ForegroundColor Cyan
    Write-Host '  ================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  [1]  Launch pi                 (launch.ps1)'  -ForegroundColor Green
    Write-Host '  [2]  Launch pi with extensions              '  -ForegroundColor Green
    Write-Host '  [3]  Build image               (build.ps1)'   -ForegroundColor Yellow
    Write-Host '  [4]  Backup data               (backup.ps1)'  -ForegroundColor Blue
    Write-Host '  [5]  Restore data              (restore.ps1)' -ForegroundColor Magenta
    Write-Host '  [6]  Stop container'                          -ForegroundColor DarkYellow
    Write-Host '  [7]  Remove container'                        -ForegroundColor DarkYellow
    Write-Host '  [8]  Container status'                        -ForegroundColor White
    Write-Host '  [Q]  Quit'                                    -ForegroundColor DarkGray
    Write-Host ''
}
function Invoke-Script {
    param([string]$Name, [string[]]$ScriptArgs)
    $path = Join-Path $scriptDir $Name
    Push-Location $scriptDir
    try { & $path @ScriptArgs } finally { Pop-Location }
}
function Assert-ContainerRunning {
    $state = docker inspect -f '{{.State.Running}}' $CONTAINER 2>$null
    if ($state -ne 'true') {
        Write-Host "  Container '$CONTAINER' is not running. Start it first with option [1]." -ForegroundColor Red
        return $false
    }
    return $true
}
# ── extension picker ────────────────────────────────────────────────────────────
function Select-Extensions {
    # Gather extensions from user folder then example folder inside the container
    $findUser = docker exec $CONTAINER bash -c "find '$EXT_USER' -maxdepth 2 \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' \) 2>/dev/null | sort" 2>$null
    $findExamples = docker exec $CONTAINER bash -c "find '$EXT_EXAMPLES' -maxdepth 1 \( -name '*.ts' -o -name '*.js' \) 2>/dev/null | sort" 2>$null
    $allPaths = @()
    if ($findUser)     { $allPaths += $findUser    | Where-Object { $_ -ne '' } }
    if ($findExamples) { $allPaths += $findExamples | Where-Object { $_ -ne '' } }
    if (-not $allPaths) {
        Write-Host '  No extension files found in the container.' -ForegroundColor Red
        Write-Host "  User extensions: $EXT_USER" -ForegroundColor DarkGray
        Write-Host "  Examples:        $EXT_EXAMPLES" -ForegroundColor DarkGray
        return @()
    }
    Write-Host '  Available extensions  (space = example, * = yours):' -ForegroundColor Cyan
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
# ── launch with extensions ──────────────────────────────────────────────────────
function Invoke-LaunchWithExtensions {
    if (-not (Assert-ContainerRunning)) { return }
    $chosen = Select-Extensions
    if (-not $chosen) {
        Write-Host '  No extensions selected. Returning to menu.' -ForegroundColor DarkYellow
        return
    }
    Write-Host ''
    Write-Host '  Loading extensions:' -ForegroundColor Cyan
    foreach ($p in $chosen) { Write-Host "    $p" }
    Write-Host ''
    # Build --extension flags
    $extArgs = @()
    foreach ($p in $chosen) { $extArgs += '--extension'; $extArgs += $p }
    Write-Host '  Launching pi in container...'
    docker exec -it $CONTAINER pi @extArgs
}
# ── main loop ───────────────────────────────────────────────────────────────────
while ($true) {
    Show-Menu
    $choice = (Read-Host '  Select an option').Trim().ToUpper()
    Write-Host ''
    switch ($choice) {
        '1' { Invoke-Script 'launch.ps1'; break }
        '2' { Invoke-LaunchWithExtensions; break }
        '3' { Invoke-Script 'build.ps1';  break }
        '4' { Invoke-Script 'backup.ps1'; break }
        '5' {
            $backupDir = Join-Path $scriptDir 'backups'
            $files = Get-ChildItem -Path $backupDir -Filter '*.tar.gz' -ErrorAction SilentlyContinue |
                     Sort-Object Name
            if (-not $files) {
                Write-Host '  No backups found in backups/' -ForegroundColor Red
            } else {
                Write-Host '  Available backups:' -ForegroundColor Cyan
                $i = 1
                foreach ($f in $files) {
                    $kb = [math]::Round($f.Length / 1KB, 1)
                    Write-Host "  [$i] $($f.Name)  ($kb KB)"
                    $i++
                }
                Write-Host ''
                $sel = (Read-Host '  Enter number (or path), blank to cancel').Trim()
                if ($sel -ne '') {
                    if ($sel -match '^\d+$') {
                        $idx = [int]$sel - 1
                        if ($idx -ge 0 -and $idx -lt $files.Count) {
                            Invoke-Script 'restore.ps1' @($files[$idx].FullName)
                        } else { Write-Host '  Invalid selection.' -ForegroundColor Red }
                    } else {
                        Invoke-Script 'restore.ps1' @($sel)
                    }
                }
            }
            break
        }
        '6' {
            Write-Host '  Stopping pi-agent container...'
            docker stop $CONTAINER
            break
        }
        '7' {
            $confirm = (Read-Host '  Remove container pi-agent? Data volume is preserved. (y/N)').Trim().ToUpper()
            if ($confirm -eq 'Y') { docker rm -f $CONTAINER }
            break
        }
        '8' {
            Write-Host '--- docker ps ---' -ForegroundColor DarkCyan
            docker ps -a --filter "name=$CONTAINER"
            Write-Host ''
            Write-Host '--- docker volume ---' -ForegroundColor DarkCyan
            docker volume ls --filter 'name=pi-agent-data'
            break
        }
        'Q' { Write-Host '  Bye.'; exit 0 }
        default { Write-Host '  Unknown option.' -ForegroundColor Red }
    }
    Write-Host ''
    Read-Host '  Press Enter to return to menu'
}
