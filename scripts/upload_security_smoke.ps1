#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- upload MIME/extension/total-cap security smoke (Windows).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Exercises multipart uploads with disallowed MIME/extension, double and
# uppercase extensions, an oversized total body, per-part and part-count
# caps, duplicate fields, duplicate part headers, oversized part headers,
# and traversal filenames. Enforced controls print PASS; missing controls
# print GAP:<severity> and are reported, never fixed here.
#
# Usage:
#   .\scripts\upload_security_smoke.ps1
#   .\scripts\upload_security_smoke.ps1 -Port 18402 -AllowKnownGaps
# ============================================================================
[CmdletBinding()]
param(
    [int]$Port = 18402,
    [string]$ServerExe = "",
    [switch]$AllowKnownGaps,
    [switch]$Keep,
    [switch]$NoBuild,
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ServerExe) {
    $name = "pulse_upload_$Port"
    if (-not $NoBuild) {
        & (Join-Path $PSScriptRoot "build.ps1") "src/server.xi" -Name $name -TimeoutSec 600
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    $ServerExe = Join-Path $repoRoot "out\$name.exe"
}
if (-not [System.IO.Path]::IsPathRooted($ServerExe)) { $ServerExe = Join-Path $repoRoot $ServerExe }
if (-not (Test-Path -LiteralPath $ServerExe)) {
    Write-Error "upload security smoke: server binary not found: $ServerExe"
    exit 2
}
if (-not $Python) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $py) { Write-Error "upload security smoke: python/python3 not found"; exit 2 }
    $Python = $py.Source
}

$smokeArgs = @("scripts/security_smoke.py", "upload", "--server-exe", $ServerExe, "--port", "$Port")
if ($AllowKnownGaps) { $smokeArgs += "--allow-known-gaps" }
if ($Keep) { $smokeArgs += "--keep" }

Push-Location $repoRoot
try {
    & $Python @smokeArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
