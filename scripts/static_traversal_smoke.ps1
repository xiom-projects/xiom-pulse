#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- static symlink/canonical + traversal security smoke (Windows).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Creates a temp site root with a symlink (or a Windows junction fallback
# when native symlink creation is not permitted), an outside canary, and an
# encoded/backslash/NUL traversal table for the site, /assets/ and upload
# filenames. Native symlink creation is skipped cleanly when the host
# disallows it; the junction fallback still exercises the canonical escape.
#
# Usage:
#   .\scripts\static_traversal_smoke.ps1
#   .\scripts\static_traversal_smoke.ps1 -Port 18401 -AllowKnownGaps
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18401,
    [string]$ServerExe = "",
    [switch]$AllowKnownGaps,
    [switch]$Keep,
    [switch]$NoBuild,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) {
    $name = "pulse_traversal_$Port"
    if (-not $NoBuild) {
        & (Join-Path $PSScriptRoot "build.ps1") "src/server.xi" -Name $name -TimeoutSec 600
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    $ServerExe = Join-Path $repoRoot "out\$name.exe"
}
if (-not [System.IO.Path]::IsPathRooted($ServerExe)) { $ServerExe = Join-Path $repoRoot $ServerExe }
if (-not (Test-Path -LiteralPath $ServerExe)) {
    Write-Error "static traversal smoke: server binary not found: $ServerExe"
    exit 2
}
if (-not $Python) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $py) { Write-Error "static traversal smoke: python/python3 not found"; exit 2 }
    $Python = $py.Source
}

$smokeArgs = @("scripts/security_smoke.py", "static", "--server-exe", $ServerExe, "--port", "$Port")
if ($AllowKnownGaps) { $smokeArgs += "--allow-known-gaps" }
if ($Keep) { $smokeArgs += "--keep" }

Push-Location $repoRoot
try {
    & $Python @smokeArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
