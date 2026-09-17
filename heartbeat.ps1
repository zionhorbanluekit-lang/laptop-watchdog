# Laptop watchdog: edits one Discord message every minute (heartbeat + status),
# posts alerts on state change. GitHub Actions (.github/workflows/watchdog.yml)
# notices when the message stops being edited.
#
#   .\heartbeat.ps1 -Install   create status message + register scheduled task
#   .\heartbeat.ps1 -Once      one iteration, print status line (self-check)
#   .\heartbeat.ps1            run forever (what the scheduled task does)
param([switch]$Install, [switch]$Once)

$ErrorActionPreference = 'Stop'
$dir       = $PSScriptRoot
$cfgPath   = Join-Path $dir 'config.json'
$statePath = Join-Path $dir 'state.json'
$cfg       = Get-Content $cfgPath -Raw | ConvertFrom-Json

# Windows PowerShell 5.1's Invoke-RestMethod mis-encodes non-ASCII (emoji) in a
# [string] -Body, corrupting the UTF-8 bytes Discord receives. Encode explicitly.
function Send-Json($uri, $method, $content) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((@{ content = $content } | ConvertTo-Json -Compress))
    Invoke-RestMethod -Uri $uri -Method $method -ContentType 'application/json; charset=utf-8' -Body $bytes
}
function Post-Discord($content)  { Send-Json "$($cfg.webhook)?wait=true" Post $content }
function Patch-Status($content)  { Send-Json "$($cfg.webhook)/messages/$($cfg.statusMessageId)" Patch $content | Out-Null }

if ($Install) {
    if (-not $cfg.statusMessageId) {
        $msg = Post-Discord "⏳ laptop watchdog starting..."
        $cfg | Add-Member -NotePropertyName statusMessageId -NotePropertyValue $msg.id -Force
        $cfg | ConvertTo-Json | Set-Content $cfgPath
        Write-Host "status message id: $($msg.id)  <- put this in GitHub secret STATUS_MSG_ID"
    }
    # No admin rights needed: drop a shortcut in the Startup folder instead of a
    # scheduled task. ponytail: no auto-restart-on-crash like Task Scheduler gives;
    # upgrade by running Register-ScheduledTask from an elevated prompt if that matters.
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup 'LaptopWatchdog.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath = 'powershell.exe'
    $lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $lnk.WorkingDirectory = $dir
    $lnk.WindowStyle = 7   # minimized
    $lnk.Save()
    Write-Host "startup shortcut created: $lnkPath"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -WorkingDirectory $dir
    Write-Host "heartbeat loop started in background"
    return
}

# ---- state ----------------------------------------------------------------
$prev = @{ bot = $null; ac = $null; low = $false }
$lastOk = $null
if (Test-Path $statePath) { $lastOk = [datetime](Get-Content $statePath -Raw | ConvertFrom-Json).lastOk }

function Tick {
    $bot = [bool](Get-Process -Name $cfg.botProcess -ErrorAction SilentlyContinue)
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $alerts = @()

    if ($prev.bot -ne $null -and $bot -ne $prev.bot) {
        $alerts += if ($bot) { "🟢 bot **$($cfg.botProcess)** is running again" } else { "🔴 bot **$($cfg.botProcess)** is NOT running" }
    }
    $power = ''
    if ($bat) {
        $ac  = $bat.BatteryStatus -ne 1          # 1 = discharging
        $pct = [int]$bat.EstimatedChargeRemaining
        $low = (-not $ac) -and $pct -le $cfg.lowBatteryPct
        if ($prev.ac -ne $null -and $ac -ne $prev.ac) {
            $alerts += if ($ac) { "🟢 power restored ($pct%)" } else { "⚠️ charger unplugged, battery $pct%" }
        }
        if ($low -and -not $prev.low) { $alerts += "🔋 LOW battery $pct% — laptop will die soon" }
        $prev.ac = $ac; $prev.low = $low
        $power = if ($ac) { " · 🔌 AC $pct%" } else { " · 🔋 battery $pct%" }
    }
    $prev.bot = $bot

    $botTxt = if ($bot) { 'bot running' } else { 'bot DOWN' }
    $icon   = if ($bot -and -not $prev.low) { '🟢' } else { '🟠' }
    $line   = "$icon $env:COMPUTERNAME $botTxt$power · $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    Patch-Status $line
    $now = [datetime]::UtcNow
    if ($script:lastOk -and ($now - $script:lastOk).TotalMinutes -gt $cfg.offlineAfterMin) {
        $alerts += "🟢 laptop back online — was offline $([int]($now - $script:lastOk).TotalMinutes) min"
    }
    $script:lastOk = $now
    @{ lastOk = $now.ToString('o') } | ConvertTo-Json | Set-Content $statePath
    foreach ($a in $alerts) { Post-Discord $a | Out-Null }
    return $line
}

if ($Once) { Tick; return }

while ($true) {
    try { Tick | Out-Null } catch { Write-Warning "$(Get-Date -Format s) $_" }
    Start-Sleep -Seconds $cfg.intervalSec
}
