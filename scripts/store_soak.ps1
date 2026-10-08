#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE storage soak: continuous event writes over HTTP, periodic count
# verification, compaction, hard kill, reopen and count re-verification.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\store_soak.ps1 -Seconds 600
# Exit code: 0 = green, 1 = failed. Summary: probe-logs\store-soak.summary.txt
# ============================================================================
[CmdletBinding()]
param(
    [int]$Seconds = 600,
    [int]$IntervalMs = 200,
    [int]$Port = 18089,
    [string]$ServerExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app.exe" }

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$storeFile = Join-Path $logDir "store-soak.jsonl"
$summaryFile = Join-Path $logDir "store-soak.summary.txt"
$serverLog = Join-Path $logDir "store-soak-server.out"
if (Test-Path -LiteralPath $storeFile) { Remove-Item -LiteralPath $storeFile -Force }

$env:PULSE_PORT = "$Port"
$env:PULSE_STORE_PATH = $storeFile
$env:PULSE_LOG = "0"   # keep the server log small during the write soak

function Start-Pulse {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"`"$ServerExe`" > `"$serverLog`" 2>&1`""
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    Start-Sleep -Milliseconds 900
    return $p
}

function Send-Req {
    param([string]$Method, [string]$Path, [string]$Body = "")
    $c = New-Object System.Net.Sockets.TcpClient
    $c.ReceiveTimeout = 5000; $c.SendTimeout = 5000
    $c.Connect("127.0.0.1", $Port)
    $s = $c.GetStream()
    $req = "$Method $Path HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`nContent-Length: $($Body.Length)`r`n`r`n$Body"
    $b = [Text.Encoding]::ASCII.GetBytes($req)
    $s.Write($b, 0, $b.Length)
    $sb = New-Object System.Text.StringBuilder
    $buf = New-Object byte[] 8192
    while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) {
        $null = $sb.Append([Text.Encoding]::ASCII.GetString($buf, 0, $n))
    }
    $c.Close()
    return $sb.ToString()
}

function Get-StoreCount {
    $r = Send-Req -Method "GET" -Path "/api/events/count"
    $m = [regex]::Match($r, '"count":(\d+)')
    if (-not $m.Success) { throw "count not found: $r" }
    return [int]$m.Groups[1].Value
}

$srv = Start-Pulse
$baseline = Get-StoreCount
Write-Host "store-soak: baseline count=$baseline for ${Seconds}s"

$ok = 0; $fail = 0; $mismatch = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastCheck = $sw.Elapsed.TotalSeconds
$i = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $i = $i + 1
    $body = "{`"kind`":`"soak`",`"n`":$i}"
    try {
        $r = Send-Req -Method "POST" -Path "/api/events" -Body $body
        if ($r -like "*HTTP/1.1 200*") { $ok++ } else { $fail++ }
    } catch { $fail++ }

    if (($sw.Elapsed.TotalSeconds - $lastCheck) -ge 60) {
        $c = Get-StoreCount
        $expected = $baseline + $ok
        if ($c -ne $expected) {
            $mismatch++
            Add-Content -LiteralPath $summaryFile -Value ("{0:u} MISMATCH count={1} expected={2}" -f [DateTime]::UtcNow, $c, $expected)
        }
        Write-Host ("store-soak: elapsed={0:N0}s ok={1} fail={2} count={3}" -f $sw.Elapsed.TotalSeconds, $ok, $fail, $c)
        $lastCheck = $sw.Elapsed.TotalSeconds
    }
    Start-Sleep -Milliseconds $IntervalMs
}

# --- compaction ------------------------------------------------------------
$r = Send-Req -Method "POST" -Path "/api/events/compact" -Body ""
$compactOk = $r -like "*HTTP/1.1 200*"
$countAfterCompact = Get-StoreCount

# --- hard kill + reopen ----------------------------------------------------
& taskkill /T /F /PID $srv.Id 2>$null | Out-Null
$srv.WaitForExit(5000) | Out-Null
Start-Sleep -Milliseconds 300
$srv2 = Start-Pulse
$countAfterReopen = Get-StoreCount

$null = Send-Req -Method "GET" -Path "/health" | Out-Null
$c = New-Object System.Net.Sockets.TcpClient
$c.Connect("127.0.0.1", $Port)
$s = $c.GetStream()
$q = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nX-Pulse-Quit: 1`r`n`r`n")
$s.Write($q, 0, $q.Length)
$c.Close()
if (-not $srv2.WaitForExit(15000)) {
    & taskkill /T /F /PID $srv2.Id 2>$null | Out-Null
    $srv2.WaitForExit(5000) | Out-Null
}
$srvExit = $srv2.ExitCode

$expectedFinal = $baseline + $ok
$summary = @(
    "store-soak summary (UTC $([DateTime]::UtcNow.ToString('u')))",
    "duration: $Seconds s, interval ${IntervalMs}ms",
    "writes: ok=$ok fail=$fail",
    "baseline=$baseline count_after_compact=$countAfterCompact count_after_reopen=$countAfterReopen expected=$expectedFinal",
    "compaction_ok=$compactOk count_mismatches=$mismatch",
    "server_exit=$srvExit store_bytes=$((Get-Item -LiteralPath $storeFile -ErrorAction SilentlyContinue).Length)"
)
$summary | Set-Content -LiteralPath $summaryFile
$summary | ForEach-Object { Write-Host $_ }

if ($fail -eq 0 -and $mismatch -eq 0 -and $compactOk -and $countAfterCompact -eq $expectedFinal -and $countAfterReopen -eq $expectedFinal -and $srvExit -eq 0) {
    Write-Host "store-soak: GREEN"
    exit 0
}
Write-Host "store-soak: RED"
exit 1
