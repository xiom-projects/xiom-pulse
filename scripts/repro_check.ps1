#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- same-host reproducible-build gate (Windows payload).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds src/server.xi twice in this workspace with distinct names and compares
# the SHA-256 of the two executables. This is the same-host payload gate; it
# does not prove cross-host or zip reproducibility (see
# docs/REPRODUCIBLE-BUILD.md for the remaining deltas).
#
# Exit code 0 = identical, 1 = mismatch, other = build failure.
# ============================================================================
[CmdletBinding()]
param(
    [int]$TimeoutSec = 300
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build.ps1") "src/server.xi" -Name repro_a -TimeoutSec $TimeoutSec | Out-Null
if ($LASTEXITCODE -ne 0) { throw "repro build A failed" }
& (Join-Path $PSScriptRoot "build.ps1") "src/server.xi" -Name repro_b -TimeoutSec $TimeoutSec | Out-Null
if ($LASTEXITCODE -ne 0) { throw "repro build B failed" }

$a = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot "out/repro_a.exe")).Hash.ToLower()
$b = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot "out/repro_b.exe")).Hash.ToLower()
$sizeA = (Get-Item -LiteralPath (Join-Path $repoRoot "out/repro_a.exe")).Length
$sizeB = (Get-Item -LiteralPath (Join-Path $repoRoot "out/repro_b.exe")).Length

Remove-Item -LiteralPath (Join-Path $repoRoot "out/repro_a.exe"), (Join-Path $repoRoot "out/repro_b.exe") -ErrorAction SilentlyContinue

if ($a -ne $b) {
    Write-Host "repro: RED payload mismatch"
    Write-Host "  a=$a ($sizeA bytes)"
    Write-Host "  b=$b ($sizeB bytes)"
    exit 1
}
Write-Host "repro: GREEN same-host payload sha256=$a ($sizeA bytes)"
exit 0
