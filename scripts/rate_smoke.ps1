#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE rate-limit smoke: start the server with PULSE_RATE_LIMIT=2,
# burst 8 rapid requests, expect some 429 + Retry-After, then a refill pass.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\rate_smoke.ps1
# Exit code: 0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18086,
    [string]$ServerExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app_v6.exe" }

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$srvLog = Join-Path $logDir "rate-smoke-server.out"

$env:PULSE_PORT = "$Port"
$env:PULSE_RATE_LIMIT = "2"
$env:PULSE_RATE_BURST = "2"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"`"$ServerExe`" > `"$srvLog`" 2>&1`""
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$srv = New-Object System.Diagnostics.Process
$srv.StartInfo = $psi
$null = $srv.Start()
Start-Sleep -Milliseconds 900

function Send-Req {
    param([string]$Method = "GET", [string]$Path = "/health")
    $c = New-Object System.Net.Sockets.TcpClient
    $c.ReceiveTimeout = 5000; $c.SendTimeout = 5000
    $c.Connect("127.0.0.1", $Port)
    $s = $c.GetStream()
    $req = "$Method $Path HTTP/1.1`r`nHost: 127.0.0.1:$Port`r`nConnection: close`r`n`r`n"
    $b = [Text.Encoding]::ASCII.GetBytes($req)
    $s.Write($b, 0, $b.Length)
    $sb = New-Object System.Text.StringBuilder
    $buf = New-Object byte[] 4096
    while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) {
        $null = $sb.Append([Text.Encoding]::ASCII.GetString($buf, 0, $n))
    }
    $c.Close()
    return $sb.ToString()
}

$ok = 0; $limited = 0; $other = 0
$r429 = ""
for ($i = 0; $i -lt 8; $i++) {
    $r = Send-Req
    if ($r -like "*HTTP/1.1 200*") { $ok++ }
    elseif ($r -like "*HTTP/1.1 429*") { $limited++; if ($r429 -eq "") { $r429 = $r } }
    else { $other++ }
}

Start-Sleep -Milliseconds 1300
$after = Send-Req
$afterOk = $after -like "*HTTP/1.1 200*"

$null = Send-Req -Path "/health"  # QUIT goes through headers below
$c = New-Object System.Net.Sockets.TcpClient
$c.Connect("127.0.0.1", $Port)
$s = $c.GetStream()
$q = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nX-Pulse-Quit: 1`r`n`r`n")
$s.Write($q, 0, $q.Length)
$c.Close()
if (-not $srv.WaitForExit(15000)) {
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    $srv.WaitForExit(5000) | Out-Null
}
$srvExit = $srv.ExitCode
$srvOut = Get-Content -LiteralPath $srvLog -Raw

Write-Host ("rate-smoke: burst 200={0} 429={1} other={2}; after-refill_200={3}; server_exit={4}" -f $ok, $limited, $other, $afterOk, $srvExit)
$retryHeader = $r429 -like "*Retry-After:*"

if ($ok -ge 2 -and $limited -ge 1 -and $other -eq 0 -and $afterOk -and $srvExit -eq 0 -and $retryHeader) {
    Write-Host "rate-smoke: GREEN"
    exit 0
}
Write-Host "rate-smoke: RED (retry_header=$retryHeader)"
Write-Host "---- 429 sample ----"
Write-Host $r429
Write-Host "--------------------"
exit 1
