# ============================================================================
# XIOM PULSE RSS-growth probe (Windows): starts the server, serves /health
# at a fixed interval, samples the working set and reports growth per
# request with a 10s progress curve. Diagnostic twin of scripts/rss_probe.sh
# (Windows is the FLAT platform in the C-PULSE-14 comparison).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\rss_probe.ps1
#   .\scripts\rss_probe.ps1 -Seconds 300 -IntervalMs 500 -Port 18096
# Summary: probe-logs\rss-probe.summary.txt.
# Exit: 0 = ran cleanly (growth is informational), 1 = server start/stop failed.
# ============================================================================

param(
    [int]$Seconds = 120,
    [int]$IntervalMs = 500,
    [int]$Port = 18096,
    [string]$ServerExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app.exe" }
if (-not (Test-Path -LiteralPath $ServerExe)) {
    Write-Host "ERROR: server not built: $ServerExe"
    exit 1
}

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$summary = Join-Path $logDir "rss-probe.summary.txt"
$store = Join-Path $logDir "rss-probe.jsonl"
$serverLog = Join-Path $logDir "rss-probe-server.out"
Remove-Item -LiteralPath $store -ErrorAction SilentlyContinue

$env:PULSE_PORT = "$Port"
$env:PULSE_LOG = "0"
$env:PULSE_STORE_PATH = $store
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ServerExe
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$srv = New-Object System.Diagnostics.Process
$srv.StartInfo = $psi
$null = $srv.Start()
Start-Sleep -Milliseconds 900

function Get-Ws {
    param($Proc)
    try { return (Get-Process -Id $Proc.Id).WorkingSet64 } catch { return 0 }
}

$ws0 = Get-Ws $srv
$base = "http://127.0.0.1:$Port"
$head = "rss-probe: baseline ws=$ws0 interval_ms=$IntervalMs for ${Seconds}s"
Write-Host $head
Set-Content -LiteralPath $summary -Value @($head)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$reqs = 0
$failed = 0
$lastSample = 0.0
$sampleN = 0
$ssdWs = $ws0
$ssdReqs = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $code = (curl.exe -s -o NUL -w "%{http_code}" "$base/health")
    if ($code -eq "200") { $reqs++ } else { $failed++ }
    if (($sw.Elapsed.TotalSeconds - $lastSample) -ge 10) {
        $ws = Get-Ws $srv
        $line = "$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')) elapsed=$([int]$sw.Elapsed.TotalSeconds)s requests=$reqs fail=$failed ws=$ws"
        Write-Host $line
        Add-Content -LiteralPath $summary -Value $line
        $lastSample = $sw.Elapsed.TotalSeconds
        $sampleN++
        if ($sampleN -eq 2) {
            $ssdWs = $ws
            $ssdReqs = $reqs
        }
    }
    Start-Sleep -Milliseconds $IntervalMs
}

$wsEnd = Get-Ws $srv
$growth = $wsEnd - $ws0
if ($reqs -gt 0) { $perReq = [math]::Round($growth / $reqs, 2) } else { $perReq = 0 }
$ssdGrowth = $wsEnd - $ssdWs
$ssdReqsN = $reqs - $ssdReqs
if ($ssdReqsN -gt 0) { $ssdPer = [math]::Round($ssdGrowth / $ssdReqsN, 2) } else { $ssdPer = 0 }
$tail = @(
    "rss-probe summary ($([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')))",
    "server: $ServerExe",
    "duration: ${Seconds}s, interval ${IntervalMs}ms",
    "requests: ok=$reqs fail=$failed",
    "ws: $ws0 -> $wsEnd (growth $growth bytes, $perReq bytes/request incl. warmup)",
    "steady (2nd sample onward): $ssdReqsN requests, growth $ssdGrowth bytes, $ssdPer bytes/request"
)
$tail | ForEach-Object { Write-Host $_ }
Add-Content -LiteralPath $summary -Value $tail

curl.exe -s -o NUL -H "X-Pulse-Quit: 1" "$base/health" | Out-Null
if (-not $srv.WaitForExit(15000)) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
$srvExit = 1
try { $srvExit = $srv.ExitCode } catch { $srvExit = 1 }
$srvLog = $srv.StandardOutput.ReadToEnd() + $srv.StandardError.ReadToEnd()
Set-Content -LiteralPath $serverLog -Value $srvLog
Add-Content -LiteralPath $summary -Value "server_exit: $srvExit"
if ($srvExit -eq 0) {
    Write-Host "rss-probe: done"
    exit 0
}
Write-Host "rss-probe: RED (server_exit=$srvExit)"
exit 1
