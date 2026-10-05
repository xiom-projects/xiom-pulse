#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE soak driver: start a compiled server exe, run the XIOM client
# twice, soak with N PowerShell TCP clients, QUIT, and report stability.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\soak_tcp.ps1 -Seconds 60
# Exit code: 0 = all green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Seconds = 60,
    [int]$Port = 19080,
    [int]$IntervalMs = 400,
    [string]$ServerExe = "",
    [string]$ClientExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\tcp_srv2.exe" }
if (-not $ClientExe) { $ClientExe = Join-Path $repoRoot "out\tcp_cli2.exe" }

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$srvOut = Join-Path $logDir "soak-tcp.out"
$srvErr = Join-Path $logDir "soak-tcp.err"

function Send-ProbeRequest {
    param([string]$Path = "/soak")
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $req = [Text.Encoding]::ASCII.GetBytes("GET $Path HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 512
        $n = $s.Read($buf, 0, $buf.Length)
        return $n
    } finally {
        $c.Close()
    }
}

Write-Host "soak: starting $ServerExe"
# System.Diagnostics.Process (not Start-Process -PassThru): with redirected
# output the Start-Process object does not expose ExitCode reliably in PS 5.1.
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
Start-Sleep -Milliseconds 1000

# --- x2 XIOM client runs -------------------------------------------------
$c1 = 1; $c2 = 1
try {
    & $ClientExe | Write-Host
    $c1 = $LASTEXITCODE
    & $ClientExe | Write-Host
    $c2 = $LASTEXITCODE
} catch {
    Write-Host "soak: client run threw: $($_.Exception.Message)"
}

# --- soak ----------------------------------------------------------------
$baseline = Get-Process -Id $srv.Id
$mem0 = $baseline.WorkingSet64
$handles0 = $baseline.HandleCount
Write-Host ("soak: {0}s, interval {1}ms; baseline ws={2:N0} handles={3}" -f $Seconds, $IntervalMs, $mem0, $handles0)

$ok = 0; $fail = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    try {
        $n = Send-ProbeRequest
        if ($n -gt 0) { $ok++ } else { $fail++ }
    } catch {
        $fail++
    }
    Start-Sleep -Milliseconds $IntervalMs
}

$mem1 = (Get-Process -Id $srv.Id).WorkingSet64
$handles1 = (Get-Process -Id $srv.Id).HandleCount

# --- QUIT ----------------------------------------------------------------
try { $null = Send-ProbeRequest -Path "/quit?QUIT" } catch { }
if (-not $srv.WaitForExit(15000)) {
    Write-Host "soak: server did not exit after QUIT; killing"
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    $srv.WaitForExit(5000) | Out-Null
}
Start-Sleep -Milliseconds 300
$srvExit = $srv.ExitCode
$srvLog = $srv.StandardOutput.ReadToEnd() + $srv.StandardError.ReadToEnd()
if ($srvLog.Length -gt 0) { Set-Content -LiteralPath $srvOut -Value $srvLog }

Write-Host "--- server output ---"
Write-Host $srvLog.TrimEnd()
Write-Host "--- soak result ---"
Write-Host ("soak: client1_exit={0} client2_exit={1} ok={2} fail={3}" -f $c1, $c2, $ok, $fail)
Write-Host ("soak: ws {0:N0} -> {1:N0} (delta {2:N0}); handles {3} -> {4} (delta {5})" -f $mem0, $mem1, ($mem1 - $mem0), $handles0, $handles1, ($handles1 - $handles0))
Write-Host ("soak: server_exit={0}" -f $srvExit)

$servedMatch = [regex]::Match($srvLog, "served=(\d+)")
$served = if ($servedMatch.Success) { [int]$servedMatch.Groups[1].Value } else { -1 }
Write-Host ("soak: served={0} expected>={1}" -f $served, ($ok + 2))

# QUIT request is not counted as served; expect served == ok + 2 client runs.
if ($c1 -eq 0 -and $c2 -eq 0 -and $fail -eq 0 -and $srvExit -eq 0 -and $served -eq ($ok + 2)) {
    Write-Host "soak: GREEN"
    exit 0
}
Write-Host "soak: RED"
exit 1
