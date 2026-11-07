# XIOM PULSE -- runner for the SSE/WS/OpenAPI gap probes (2026-11-07).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds one private server binary (unique name, out/pulse_gap_<base>.exe)
# and runs the three additive probes on unique ports 18700+:
#   ws_negative_corpus.py     -> W-09 negative frames (port base + 20)
#   sse_reconnect_probe.py    -> W-08/W-12 reconnect (port base + 21)
#   openapi_drift_probe.py    -> W-14 reverse drift (CLI only)
#   schema_matrix_probe.py    -> R-14 schema matrix (port base + 22)
#
# No existing test, CI file, src module, or docs file is touched. The probes
# create their own temp store/audit/upload paths and never write into the
# repository.
#
# Usage:
#   powershell -NoProfile -File scripts/gap_stream_probes.ps1
#   powershell -NoProfile -File scripts/gap_stream_probes.ps1 -SkipBuild
#   powershell -NoProfile -File scripts/gap_stream_probes.ps1 -Strict
#
# Exit: 0 = no FAIL (GAPs allowed unless -Strict), 1 = FAIL/strict GAP.

[CmdletBinding()]
param(
    [int]$BuildPortBase = 18700,
    [switch]$SkipBuild,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildName = "pulse_gap_$BuildPortBase"
$exe = Join-Path $repoRoot "out\$buildName.exe"
$wsPort = $BuildPortBase + 20
$ssePort = $BuildPortBase + 21
$schemaPort = $BuildPortBase + 22

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot "build.ps1") -File (Join-Path $repoRoot "src\server.xi") -Name $buildName -TimeoutSec 600
    if ($LASTEXITCODE -ne 0) {
        Write-Host "gap-probes: build failed with exit $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "gap-probes: server binary not found: $exe (run without -SkipBuild)"
    exit 2
}

$py = "python"
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { $py = "py" }
$strictArgs = @()
if ($Strict) { $strictArgs += "--strict" }

$rc = 0

Write-Host "gap-probes: WS negative corpus on 127.0.0.1:$wsPort"
& $py (Join-Path $PSScriptRoot "ws_negative_corpus.py") --exe $exe --port $wsPort @strictArgs
if ($LASTEXITCODE -ne 0) { $rc = 1 }

Write-Host "gap-probes: SSE reconnect probe on 127.0.0.1:$ssePort"
& $py (Join-Path $PSScriptRoot "sse_reconnect_probe.py") --exe $exe --port $ssePort @strictArgs
if ($LASTEXITCODE -ne 0) { $rc = 1 }

Write-Host "gap-probes: OpenAPI reverse drift (CLI)"
& $py (Join-Path $PSScriptRoot "openapi_drift_probe.py") --exe $exe @strictArgs
if ($LASTEXITCODE -ne 0) { $rc = 1 }

Write-Host "gap-probes: R-14 schema matrix on 127.0.0.1:$schemaPort"
& $py (Join-Path $PSScriptRoot "schema_matrix_probe.py") --exe $exe --port $schemaPort @strictArgs
if ($LASTEXITCODE -ne 0) { $rc = 1 }

if ($rc -eq 0) {
    Write-Host "gap-probes: GREEN (known GAPs are reported above)"
} else {
    Write-Host "gap-probes: RED (see FAIL/GAP lines above)"
}
exit $rc
