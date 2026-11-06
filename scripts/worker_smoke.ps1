#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE N-ports worker smoke: build a uniquely named binary, run two
# workers on distinct ports (the portable baseline), probe GET /health on
# both, then kill both and report GREEN/RED.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\worker_smoke.ps1
# Exit code: 0 = green, 1 = failed.
#
# This deliberately does NOT set PULSE_REUSEPORT: N distinct ports is the
# Windows/portable baseline. The reuseport path is exercised by the app
# startup log, not by this smoke.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port1 = 18201,
    [int]$Port2 = 18202
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$serverExe = Join-Path $repoRoot "out\worker_app.exe"

# --- build with a unique name ----------------------------------------------
& (Join-Path $PSScriptRoot "build.ps1") (Join-Path $repoRoot "src\server.xi") `
    -Name "worker_app" -TimeoutSec 300
if ($LASTEXITCODE -ne 0) {
    Write-Host "worker-smoke: RED (build failed, exit $LASTEXITCODE)"
    exit 1
}

$logDir = Join-Path $repoRoot "probe-logs\worker-smoke"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$w0Out = Join-Path $logDir "w0-$Port1.out"
$w0Err = Join-Path $logDir "w0-$Port1.err"
$w1Out = Join-Path $logDir "w1-$Port2.out"
$w1Err = Join-Path $logDir "w1-$Port2.err"

function Start-Worker {
    param(
        [int]$Id,
        [int]$Port,
        [string]$OutFile,
        [string]$ErrFile
    )
    # cmd /c keeps the child's stdout/stderr on files (a pipe would block
    # the single-threaded server once the access log fills it).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c `"`"$serverExe`" 1>`"$OutFile`" 2>`"$ErrFile`"`""
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["PULSE_BIND"] = "127.0.0.1"
    $psi.EnvironmentVariables["PULSE_PORT"] = "$Port"
    $psi.EnvironmentVariables["PULSE_WORKER_ID"] = "$Id"
    $psi.EnvironmentVariables["PULSE_REUSEPORT"] = "0"
    $psi.EnvironmentVariables["PULSE_LOG"] = "0"
    $psi.EnvironmentVariables["PULSE_STORE_PATH"] = (Join-Path $logDir "w$Id-events.jsonl")
    $psi.EnvironmentVariables["PULSE_AUDIT_PATH"] = (Join-Path $logDir "w$Id-audit.log")
    return [System.Diagnostics.Process]::Start($psi)
}

function Test-Health {
    param([int]$Port)
    $url = "http://127.0.0.1:$Port/health"
    for ($i = 0; $i -lt 75; $i++) {
        $code = ""
        try {
            $code = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 2 $url 2>$null | Out-String).Trim()
        } catch {
            $code = ""
        }
        if ($code -eq "200") { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Stop-Worker {
    param($Proc)
    if ($null -ne $Proc -and -not $Proc.HasExited) {
        & taskkill /T /F /PID $Proc.Id 2>$null | Out-Null
        $Proc.WaitForExit(5000) | Out-Null
    }
}

$w0 = $null
$w1 = $null
$green = $true
try {
    Write-Host "worker-smoke: starting worker 0 on 127.0.0.1:$Port1"
    $w0 = Start-Worker -Id 0 -Port $Port1 -OutFile $w0Out -ErrFile $w0Err
    Write-Host "worker-smoke: starting worker 1 on 127.0.0.1:$Port2"
    $w1 = Start-Worker -Id 1 -Port $Port2 -OutFile $w1Out -ErrFile $w1Err

    $h0 = Test-Health -Port $Port1
    $h1 = Test-Health -Port $Port2
    if ($h0) {
        Write-Host "[PASS] worker 0 GET /health 200 ($Port1)"
    } else {
        Write-Host "[FAIL] worker 0 GET /health not 200 ($Port1)"
        $green = $false
    }
    if ($h1) {
        Write-Host "[PASS] worker 1 GET /health 200 ($Port2)"
    } else {
        Write-Host "[FAIL] worker 1 GET /health not 200 ($Port2)"
        $green = $false
    }
} finally {
    Stop-Worker -Proc $w0
    Stop-Worker -Proc $w1
}

if (-not $green) {
    Write-Host "---- worker 0 log ----"
    if (Test-Path -LiteralPath $w0Out) { Get-Content -LiteralPath $w0Out -ErrorAction SilentlyContinue | Write-Host }
    if (Test-Path -LiteralPath $w0Err) { Get-Content -LiteralPath $w0Err -ErrorAction SilentlyContinue | Write-Host }
    Write-Host "---- worker 1 log ----"
    if (Test-Path -LiteralPath $w1Out) { Get-Content -LiteralPath $w1Out -ErrorAction SilentlyContinue | Write-Host }
    if (Test-Path -LiteralPath $w1Err) { Get-Content -LiteralPath $w1Err -ErrorAction SilentlyContinue | Write-Host }
    Write-Host "worker-smoke: RED"
    exit 1
}

Write-Host "worker-smoke: GREEN"
exit 0
