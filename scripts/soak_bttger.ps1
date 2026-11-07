#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- bttger-mix soak wrapper (Windows / PowerShell).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Thin wrapper over scripts/soak_bttger.py (same flags, PowerShell names).
# Exact 24 h WP1 gate command:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\soak_bttger.ps1 `
#       -Seconds 86400 -Rate 100 -Port 18800 -MaxRssMb 256 -Rebuild
#
# 60 s validation command:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\soak_bttger.ps1 `
#       -Seconds 60 -Rate 100 -MaxRssMb 256 -Rebuild
#
# Exit codes: 0 = gate PASS, 1 = gate FAIL, 2 = usage error, 130 = SIGINT.
# ============================================================================
[CmdletBinding()]
param(
    [double]$Seconds = 60,
    [double]$Rate = 100,
    [int]$Port = 18800,
    [double]$MaxRssMb = 256,
    [double]$WarmupSeconds = 5,
    [int]$Connections = 1,
    [string]$ServerExe = "",
    [int]$SampleMs = 0,
    [double]$RateTolerance = 0.02,
    [string]$Only = "",
    [string]$JsonOut = "",
    [switch]$Rebuild,
    [switch]$NoBuild,
    [switch]$NoVerifyBodies,
    [switch]$NoFailFast,
    [switch]$FailOnProjection
)

$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "soak_bttger.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Error "soak-bttger: missing $scriptPath"
    exit 1
}

$pythonExe = $env:PYTHON
$pythonPrefix = @()
if (-not $pythonExe) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $pythonExe = $cmd.Source }
}
if (-not $pythonExe) {
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) {
        $pythonExe = $cmd.Source
        $pythonPrefix = @("-3")
    }
}
if (-not $pythonExe) {
    Write-Error "soak-bttger: Python 3 not found (set PYTHON or install python)"
    exit 1
}

$argsList = @($pythonPrefix) + @(
    $scriptPath,
    "--seconds", "$Seconds",
    "--rate", "$Rate",
    "--port", "$Port",
    "--max-rss-mb", "$MaxRssMb",
    "--warmup-seconds", "$WarmupSeconds",
    "--connections", "$Connections",
    "--sample-ms", "$SampleMs",
    "--rate-tolerance", "$RateTolerance"
)
if ($ServerExe) { $argsList += @("--server-exe", $ServerExe) }
if ($Only) { $argsList += @("--only", $Only) }
if ($JsonOut) { $argsList += @("--json-out", $JsonOut) }
if ($Rebuild) { $argsList += "--rebuild" }
if ($NoBuild) { $argsList += "--no-build" }
if ($NoVerifyBodies) { $argsList += "--no-verify-bodies" }
if ($NoFailFast) { $argsList += "--no-fail-fast" }
if ($FailOnProjection) { $argsList += "--fail-on-projection" }

& $pythonExe @argsList
exit $LASTEXITCODE
