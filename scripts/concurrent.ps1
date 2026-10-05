#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE concurrency driver: open N simultaneous TCP connections to the
# compiled probe server, then exchange one request per connection.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\concurrent.ps1 -Clients 64
# Exit code: 0 = all N served, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Clients = 64,
    [int]$Port = 19080,
    [string]$Path = "/health",
    [string]$ServerExe = "",
    [string]$ClientExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\tcp_srv2.exe" }
if (-not $ClientExe) { $ClientExe = Join-Path $repoRoot "out\tcp_cli2.exe" }

# Start the server with output redirected to a FILE (cmd), never a
# PowerShell pipe: a chatty server (per-request access log) fills an
# undrained 4 KiB pipe and blocks mid-test.
$env:PULSE_PORT = "$Port"
$srvLog = Join-Path (Split-Path -Parent $PSScriptRoot) "probe-logs\concurrent-server.out"
$logDir = Split-Path -Parent $srvLog
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"`"$ServerExe`" > `"$srvLog`" 2>&1`""
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$srv = New-Object System.Diagnostics.Process
$srv.StartInfo = $psi
$null = $srv.Start()
Start-Sleep -Milliseconds 800

$mem0 = (Get-Process -Id $srv.Id).WorkingSet64
$handles0 = (Get-Process -Id $srv.Id).HandleCount

# --- open N simultaneous connections (all established before any request) --
# NOTE: PowerShell variables are case-insensitive -- keep local state named
# `$conns`, never `$clients` (that collides with the [int]$Clients param).
$conns = New-Object System.Collections.ArrayList
$connectFail = 0
for ($i = 0; $i -lt $Clients; $i++) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port)
        $null = $conns.Add($c)
    } catch {
        $connectFail++
    }
}
$connected = @($conns | Where-Object { $_.Connected }).Count
Write-Host "concurrent: connected=$connected/$Clients connect_fail=$connectFail"
$mem1 = (Get-Process -Id $srv.Id).WorkingSet64
$handles1 = (Get-Process -Id $srv.Id).HandleCount

# --- exchange one request per connection (server serves sequentially) -----
$ok = 0; $fail = 0
$idx = 0
foreach ($c in $conns) {
    try {
        $s = $c.GetStream()
        $req = [Text.Encoding]::ASCII.GetBytes("GET $Path HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 512
        $n = $s.Read($buf, 0, $buf.Length)
        if ($n -gt 0) {
            $txt = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
            if ($txt -like "HTTP/1.1 200*") { $ok++ } else { $fail++ }
        } else {
            $fail++
        }
    } catch {
        $fail++
    } finally {
        $c.Close()
    }
    $idx++
}
Write-Host "concurrent: ok=$ok fail=$fail"

# --- QUIT -----------------------------------------------------------------
# One well-formed request carrying X-Pulse-Quit: 1 (pulse_server) and the
# literal QUIT marker (tcp_srv2 scans for it) -- works for both servers.
try {
    $q = New-Object System.Net.Sockets.TcpClient
    $q.Connect("127.0.0.1", $Port)
    $qs = $q.GetStream()
    $qreq = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nX-Pulse-Quit: 1`r`n`r`n")
    $qs.Write($qreq, 0, $qreq.Length)
    $q.Close()
} catch { }

if (-not $srv.WaitForExit(15000)) {
    Write-Host "concurrent: server did not exit; killing"
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    $srv.WaitForExit(5000) | Out-Null
}
$srvExit = $srv.ExitCode
$srvOut = if (Test-Path -LiteralPath $srvLog) { Get-Content -LiteralPath $srvLog -Raw } else { "" }

Write-Host "--- server output ---"
Write-Host $srvOut.TrimEnd()
$mem2 = (Get-Process -Id $srv.Id -ErrorAction SilentlyContinue)
Write-Host ("concurrent: ws {0:N0} -> {1:N0}; handles {2} -> {3}" -f $mem0, $mem1, $handles0, $handles1)
Write-Host ("concurrent: server_exit={0}" -f $srvExit)

$servedMatch = [regex]::Match($srvOut, "served=(\d+)")
$served = if ($servedMatch.Success) { [int]$servedMatch.Groups[1].Value } else { -1 }
Write-Host ("concurrent: served={0} expected={1}" -f $served, $Clients)

if ($connected -eq $Clients -and $connectFail -eq 0 -and $fail -eq 0 -and $ok -eq $Clients -and $srvExit -eq 0 -and $served -eq $Clients) {
    Write-Host "concurrent: GREEN"
    exit 0
}
Write-Host "concurrent: RED"
exit 1
