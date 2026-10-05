#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE Step 3 crash/reopen test: write events, hard-kill the server,
# leave a torn line, reopen, and verify the prefix is intact and the store
# heals for the next append.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\crash_test.ps1
# Exit code: 0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18084,
    [int]$Events = 20,
    [string]$ServerExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) { $ServerExe = Join-Path $repoRoot "out\pulse_app.exe" }

$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$storeFile = Join-Path $logDir "crash-store.jsonl"
if (Test-Path -LiteralPath $storeFile) { Remove-Item -LiteralPath $storeFile -Force }

$env:PULSE_PORT = "$Port"
$env:PULSE_STORE_PATH = $storeFile

function Start-Pulse {
    param([string]$Log)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"`"$ServerExe`" > `"$Log`" 2>&1`""
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
    $buf = New-Object byte[] 4096
    while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) {
        $null = $sb.Append([Text.Encoding]::ASCII.GetString($buf, 0, $n))
    }
    $c.Close()
    return $sb.ToString()
}

function Get-Count {
    $r = Send-Req -Method "GET" -Path "/api/events/count"
    $m = [regex]::Match($r, '"count":(\d+)')
    if (-not $m.Success) { throw "count not found in: $r" }
    return [int]$m.Groups[1].Value
}

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

# --- phase 1: write events -------------------------------------------------
$srv1 = Start-Pulse -Log (Join-Path $logDir "crash-server1.out")
$last = ""
for ($i = 1; $i -le $Events; $i++) {
    $last = Send-Req -Method "POST" -Path "/api/events" -Body "{`"kind`":`"evt`",`"n`":$i}"
}
Check "post events 200" ($last -like "*200 OK*")
Check "count after writes" ((Get-Count) -eq $Events)

# --- phase 2: crash + torn line -------------------------------------------
& taskkill /T /F /PID $srv1.Id 2>$null | Out-Null
$srv1.WaitForExit(5000) | Out-Null
Start-Sleep -Milliseconds 300
Add-Content -LiteralPath $storeFile -Value '{"torn":' -NoNewline
$sizeBefore = (Get-Item -LiteralPath $storeFile).Length
Write-Host "crash: killed server, store=$sizeBefore bytes, appended torn line"

# --- phase 3: reopen -------------------------------------------------------
$srv2 = Start-Pulse -Log (Join-Path $logDir "crash-server2.out")
$count2 = Get-Count
Check "prefix intact after crash+torn" ($count2 -eq $Events)
$r = Send-Req -Method "POST" -Path "/api/events" -Body '{"kind":"evt","n":999}'
Check "append after torn heals" ($r -like "*200 OK*")
$count3 = Get-Count
Check "count after heal append" ($count3 -eq ($Events + 1))
$list = Send-Req -Method "GET" -Path "/api/events"
Check "list has last event" ($list -like "*`"n`":999*")

# --- shutdown --------------------------------------------------------------
$null = Send-Req -Method "GET" -Path "/health"  # warm
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

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "crash: GREEN"; exit 0 }
Write-Host "crash: RED"
exit 1
