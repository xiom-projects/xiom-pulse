#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE HTTP soak: run pulse_server for N seconds, hammer /health with
# one connection per interval, sample memory/handles every minute, QUIT
# cleanly, and write a summary the next session can read.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage (persistent background):
#   .\scripts\soak_http.ps1 -Seconds 3600
# Exit code: 0 = no failures + clean shutdown, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Seconds = 1800,
    [int]$Port = 8080,
    [int]$IntervalMs = 500,
    [string]$ServerExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app.exe" }

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$progressFile = Join-Path $logDir "soak-http-progress.txt"
$summaryFile = Join-Path $logDir "soak-http.summary.txt"
$serverLog = Join-Path $logDir "soak-http-server.out"

function Send-Health {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $c.ReceiveTimeout = 5000
        $c.SendTimeout = 5000
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $req = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 512
        $n = $s.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return $false }
        $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
        return ($txt -like "HTTP/1.1 200*")
    } finally {
        $c.Close()
    }
}

function Send-Quit {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $req = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nX-Pulse-Quit: 1`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $c.Close()
    } catch { }
}

# Server output goes to a FILE (cmd redirection), never a PowerShell pipe:
# the server flushes one log line per request, and an undrained pipe would
# fill and block it mid-soak.
$env:PULSE_PORT = "$Port"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"`"$ServerExe`" > `"$serverLog`" 2>&1`""
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$srv = New-Object System.Diagnostics.Process
$srv.StartInfo = $psi
$null = $srv.Start()
Start-Sleep -Milliseconds 1200

$mem0 = (Get-Process -Id $srv.Id).WorkingSet64
$handles0 = (Get-Process -Id $srv.Id).HandleCount
Write-Host ("soak-http: baseline ws={0:N0} handles={1} for {2}s" -f $mem0, $handles0, $Seconds)

$ok = 0; $fail = 0
$lastSample = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Add-Content -LiteralPath $progressFile -Value ("{0:u} elapsed=0s ok=0 fail=0 ws={1:N0} handles={2}" -f [DateTime]::UtcNow, $mem0, $handles0)

while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $good = $false
    $t0 = [DateTime]::UtcNow
    try { $good = Send-Health } catch { $good = $false }
    $callMs = ([DateTime]::UtcNow - $t0).TotalMilliseconds
    if ($callMs -gt 10000) {
        Add-Content -LiteralPath $progressFile -Value ("{0:u} SLOW-CALL {1:N0}ms elapsed={2:N0}s" -f [DateTime]::UtcNow, $callMs, $sw.Elapsed.TotalSeconds)
    }
    if (-not $good) {
        Start-Sleep -Milliseconds 200
        try { $good = Send-Health } catch { $good = $false }
    }
    if ($good) { $ok++ } else { $fail++ }

    if (([DateTime]::UtcNow - $lastSample).TotalSeconds -ge 60) {
        $proc = Get-Process -Id $srv.Id -ErrorAction SilentlyContinue
        $line = "{0:u} elapsed={1:N0}s ok={2} fail={3} ws={4:N0} handles={5}" -f `
            [DateTime]::UtcNow, $sw.Elapsed.TotalSeconds, $ok, $fail, $proc.WorkingSet64, $proc.HandleCount
        Add-Content -LiteralPath $progressFile -Value $line
        $lastSample = [DateTime]::UtcNow
    }

    Start-Sleep -Milliseconds $IntervalMs
}

$mem1 = (Get-Process -Id $srv.Id).WorkingSet64
$handles1 = (Get-Process -Id $srv.Id).HandleCount

Send-Quit
if (-not $srv.WaitForExit(15000)) {
    Write-Host "soak-http: server did not exit after QUIT; killing"
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    $srv.WaitForExit(5000) | Out-Null
}
$srvExit = $srv.ExitCode
$srvLog = if (Test-Path -LiteralPath $serverLog) { Get-Content -LiteralPath $serverLog -Raw } else { "" }
$tail = ""
if ($srvLog.Length -gt 0) {
    $tail = ($srvLog.TrimEnd() -split "`r?`n" | Select-Object -Last 5) -join "`n"
}

$summary = @(
    "soak-http summary (UTC $([DateTime]::UtcNow.ToString('u')))",
    "server: $ServerExe",
    "duration: $Seconds s, interval ${IntervalMs}ms",
    "requests: ok=$ok fail=$fail",
    "memory:   ws $mem0 -> $mem1 (delta $($mem1 - $mem0))",
    "handles:  $handles0 -> $handles1 (delta $($handles1 - $handles0))",
    "server_exit: $srvExit",
    "--- server log tail ---",
    $tail
)
$summary | Set-Content -LiteralPath $summaryFile
$summary | ForEach-Object { Write-Host $_ }

if ($fail -eq 0 -and $srvExit -eq 0) {
    Write-Host "soak-http: GREEN"
    exit 0
}
Write-Host "soak-http: RED"
exit 1
