#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- raw framing security smoke (Windows).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds a uniquely named server binary (pulse_framing_<port>) unless
# -ServerExe/-NoBuild is supplied, then runs scripts/security_smoke.py
# framing against it. Exit code = the engine's exit code (0 = green).
#
# Usage:
#   .\scripts\framing_smoke.ps1
#   .\scripts\framing_smoke.ps1 -Port 18400 -AllowKnownGaps
#   .\scripts\framing_smoke.ps1 -ServerExe .\out\pulse_app.exe -NoBuild
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18400,
    [string]$ServerExe = "",
    [switch]$AllowKnownGaps,
    [switch]$StrictNul,
    [switch]$Keep,
    [switch]$NoBuild,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) {
    $name = "pulse_framing_$Port"
    if (-not $NoBuild) {
        & (Join-Path $PSScriptRoot "build.ps1") "src/server.xi" -Name $name -TimeoutSec 600
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    $ServerExe = Join-Path $repoRoot "out\$name.exe"
}
if (-not [System.IO.Path]::IsPathRooted($ServerExe)) { $ServerExe = Join-Path $repoRoot $ServerExe }
if (-not (Test-Path -LiteralPath $ServerExe)) {
    Write-Error "framing smoke: server binary not found: $ServerExe"
    exit 2
}
if (-not $Python) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $py) { Write-Error "framing smoke: python/python3 not found"; exit 2 }
    $Python = $py.Source
}

$smokeArgs = @("scripts/security_smoke.py", "framing", "--server-exe", $ServerExe, "--port", "$Port")
if ($AllowKnownGaps) { $smokeArgs += "--allow-known-gaps" }
if ($StrictNul) { $smokeArgs += "--strict-nul" }
if ($Keep) { $smokeArgs += "--keep" }

Push-Location $repoRoot
try {
    & $Python @smokeArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
