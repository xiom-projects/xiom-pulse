#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE WP4 drain/supervisor smoke.
#
# 1) single worker: control /health 200, wrong-token drain 403, right-token
#    drain 200, exit 0, public port closed;
# 2) supervisor PULSE_WORKERS=2: both public ports 200, supervisor control
#    /health 200, drain 200, all children exit, all ports closed.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\drain_smoke.ps1
# Exit code: 0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$WorkerPort = 18361,
    [int]$WorkerControl = 18362,
    [int]$SupervisorBase = 18371,
    [int]$SupervisorControlBase = 18375
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$serverExe = Join-Path $repoRoot "out\drain_app.exe"
$logDir = Join-Path $repoRoot "probe-logs\drain-smoke"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

& (Join-Path $PSScriptRoot "build.ps1") (Join-Path $repoRoot "src\server.xi") `
    -Name "drain_app" -TimeoutSec 300
if ($LASTEXITCODE -ne 0) {
    Write-Host "drain-smoke: RED (build failed, exit $LASTEXITCODE)"
    exit 1
}

$green = $true
$procs = @()

function Start-Srv {
    param([hashtable]$Env, [string]$Tag)
    $out = Join-Path $logDir "$Tag.out"
    $err = Join-Path $logDir "$Tag.err"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"`"$serverExe`" 1>`"$out`" 2>`"$err`"`""
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    foreach ($k in $Env.Keys) {
        $psi.EnvironmentVariables[$k] = "$($Env[$k])"
    }
    return [System.Diagnostics.Process]::Start($psi)
}

function Http-Code {
    param([string]$Method, [string]$Url, [string]$Token = "")
    $args = @("-s", "-o", "NUL", "-w", "%{http_code}", "--max-time", "2", "-X", $Method)
    if ($Token.Length -gt 0) { $args += @("-H", "X-Pulse-Control-Token: $Token") }
    $args += $Url
    try {
        return ((& curl.exe @args 2>$null | Out-String).Trim())
    } catch {
        return ""
    }
}

function Wait-Code {
    param([string]$Url, [int]$Tries = 75)
    for ($i = 0; $i -lt $Tries; $i++) {
        $code = Http-Code -Method "GET" -Url $Url
        if ($code -eq "200") { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Stop-Tree {
    param($Proc)
    if ($null -ne $Proc -and -not $Proc.HasExited) {
        & taskkill /T /F /PID $Proc.Id 2>$null | Out-Null
        $Proc.WaitForExit(5000) | Out-Null
    }
}

$token = "drain-smoke-token"
try {
    # --- single worker -----------------------------------------------------
    $wEnv = @{
        PULSE_BIND = "127.0.0.1"; PULSE_PORT = "$WorkerPort"
        PULSE_WORKERS = "1"; PULSE_WORKER_CHILD = "0"
        PULSE_CONTROL_PORT = "$WorkerControl"; PULSE_CONTROL_TOKEN = $token
        PULSE_LOG = "0"
        PULSE_STORE_PATH = (Join-Path $logDir "worker-events.jsonl")
        PULSE_AUDIT_PATH = (Join-Path $logDir "worker-audit.log")
    }
    Write-Host "drain-smoke: starting worker on 127.0.0.1:$WorkerPort (control $WorkerControl)"
    $w = Start-Srv -Env $wEnv -Tag "worker"
    $procs += $w
    if (Wait-Code "http://127.0.0.1:$WorkerControl/health") {
        Write-Host "[PASS] control GET /health 200"
    } else {
        Write-Host "[FAIL] control GET /health not 200"
        $green = $false
    }
    $noTok = Http-Code -Method "POST" -Url "http://127.0.0.1:$WorkerControl/drain"
    if ($noTok -eq "403") {
        Write-Host "[PASS] drain without token 403"
    } else {
        Write-Host "[FAIL] drain without token = $noTok (want 403)"
        $green = $false
    }
    $badTok = Http-Code -Method "POST" -Url "http://127.0.0.1:$WorkerControl/drain" -Token "wrong"
    if ($badTok -eq "403") {
        Write-Host "[PASS] drain with wrong token 403"
    } else {
        Write-Host "[FAIL] drain with wrong token = $badTok (want 403)"
        $green = $false
    }
    $okTok = Http-Code -Method "POST" -Url "http://127.0.0.1:$WorkerControl/drain" -Token $token
    if ($okTok -eq "200") {
        Write-Host "[PASS] drain with token 200"
    } else {
        Write-Host "[FAIL] drain with token = $okTok (want 200)"
        $green = $false
    }
    if ($w.WaitForExit(5000) -and $w.ExitCode -eq 0) {
        Write-Host "[PASS] worker exited 0 after drain"
    } else {
        Write-Host "[FAIL] worker did not exit 0 after drain"
        $green = $false
    }
    $after = Http-Code -Method "GET" -Url "http://127.0.0.1:$WorkerPort/health"
    if ($after -ne "200") {
        Write-Host "[PASS] public port closed after drain"
    } else {
        Write-Host "[FAIL] public port still 200 after drain"
        $green = $false
    }

    # --- supervisor (2 workers) -------------------------------------------
    $sEnv = @{
        PULSE_BIND = "127.0.0.1"; PULSE_PORT = "$SupervisorBase"
        PULSE_WORKERS = "2"; PULSE_WORKER_CHILD = "0"
        PULSE_CONTROL_PORT = "$SupervisorControlBase"; PULSE_CONTROL_TOKEN = $token
        PULSE_LOG = "0"
        PULSE_STORE_PATH = (Join-Path $logDir "sup-events.jsonl")
        PULSE_AUDIT_PATH = (Join-Path $logDir "sup-audit.log")
    }
    Write-Host "drain-smoke: starting supervisor (2 workers) on $SupervisorBase/$($SupervisorBase + 1)"
    $s = Start-Srv -Env $sEnv -Tag "supervisor"
    $procs += $s
    $h0 = Wait-Code "http://127.0.0.1:$SupervisorBase/health"
    $h1 = Wait-Code "http://127.0.0.1:$($SupervisorBase + 1)/health"
    if ($h0 -and $h1) {
        Write-Host "[PASS] both workers GET /health 200"
    } else {
        Write-Host "[FAIL] worker health: w0=$h0 w1=$h1"
        $green = $false
    }
    $supCtl = $SupervisorControlBase - 1
    if (Wait-Code "http://127.0.0.1:$supCtl/health") {
        Write-Host "[PASS] supervisor control GET /health 200"
    } else {
        Write-Host "[FAIL] supervisor control GET /health not 200"
        $green = $false
    }
    $sd = Http-Code -Method "POST" -Url "http://127.0.0.1:$supCtl/drain" -Token $token
    if ($sd -eq "200") {
        Write-Host "[PASS] supervisor drain 200"
    } else {
        Write-Host "[FAIL] supervisor drain = $sd (want 200)"
        $green = $false
    }
    if ($s.WaitForExit(15000) -and $s.ExitCode -eq 0) {
        Write-Host "[PASS] supervisor exited 0 after drain"
    } else {
        Write-Host "[FAIL] supervisor did not exit 0 after drain"
        $green = $false
    }
    Start-Sleep -Milliseconds 500
    $p0 = Http-Code -Method "GET" -Url "http://127.0.0.1:$SupervisorBase/health"
    $p1 = Http-Code -Method "GET" -Url "http://127.0.0.1:$($SupervisorBase + 1)/health"
    if ($p0 -ne "200" -and $p1 -ne "200") {
        Write-Host "[PASS] all public ports closed after supervisor drain"
    } else {
        Write-Host "[FAIL] public ports after supervisor drain: $p0/$p1"
        $green = $false
    }
} finally {
    foreach ($p in $procs) { Stop-Tree -Proc $p }
    # The supervisor's children are reaped by /drain; a strict sweep also
    # catches a failed run so a red smoke cannot leave listeners behind.
    Get-Process drain_app -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

if (-not $green) {
    Write-Host "---- worker log ----"
    $wf = Join-Path $logDir "worker.out"
    if (Test-Path -LiteralPath $wf) { Get-Content -LiteralPath $wf -ErrorAction SilentlyContinue | Write-Host }
    Write-Host "---- supervisor log ----"
    $sf = Join-Path $logDir "supervisor.out"
    if (Test-Path -LiteralPath $sf) { Get-Content -LiteralPath $sf -ErrorAction SilentlyContinue | Write-Host }
    Write-Host "drain-smoke: RED"
    exit 1
}

Write-Host "drain-smoke: GREEN"
exit 0
