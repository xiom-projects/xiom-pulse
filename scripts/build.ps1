#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE builder -- compile one XIOM file to out\<name>.exe under the
# pinned toolchain, with a hard compile watchdog.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\build.ps1 tests\probes\probe_tcp_server.xi
#   .\scripts\build.ps1 tests\probes\probe_tcp_server.xi -Name srv
# Exit code: compiler exit code (0 = built).
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$File,
    [string]$Name = "",
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved; check scripts\dev-env.ps1" }
}

$filePath = (Resolve-Path -LiteralPath $File).Path
if (-not $Name) { $Name = [System.IO.Path]::GetFileNameWithoutExtension($filePath) }
$outDir = Join-Path $repoRoot "out"
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outExe = Join-Path $outDir "$Name.exe"

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("pulse-build-" + [guid]::NewGuid().ToString("N"))
$outFile = "$base.out"
$errFile = "$base.err"

Write-Host "build: $filePath -> $outExe"
$proc = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("-o", $outExe, $filePath) `
    -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile

$timedOut = $false
try {
    $proc | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
} catch {
    $timedOut = $true
}
if ($timedOut -and -not $proc.HasExited) {
    & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
}

$stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { "" }
$stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { "" }
Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
$output = "$stdout$stderr"
if ($output.Length -gt 0) { Write-Host $output.TrimEnd() }

if ($timedOut) {
    Write-Host "build: TIMEOUT after ${TimeoutSec}s -- process tree killed"
    exit 124
}
if ($proc.ExitCode -ne 0) {
    Write-Host "build: FAILED (compiler exit $($proc.ExitCode))"
    exit $proc.ExitCode
}
if (-not (Test-Path -LiteralPath $outExe)) {
    Write-Host "build: compiler exit 0 but $outExe missing"
    exit 1
}
Write-Host "build: OK $outExe"
exit 0
