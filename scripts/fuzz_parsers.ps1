#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- deterministic parser fuzz gate.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds tests/fuzz_parsers.xi and runs it under a watchdog. The harness is
# deterministic (PCG seed) and covers the HTTP request parser, multipart,
# urlencoded forms and html_escape. Exit code 0 = green, 1 = findings, 124 =
# timeout, other = crash.
#
# -StrictNul turns the known upstream NUL-in-head finding
# (REL-20261106-1716-pulse) into a hard failure; use it to verify the parser
# fix once it lands.
# ============================================================================
[CmdletBinding()]
param(
    [int]$TimeoutSec = 300,
    [switch]$StrictNul
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build.ps1") "tests/fuzz_parsers.xi" -Name fuzz_parsers -TimeoutSec 300 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "fuzz harness build failed" }

if ($StrictNul) { $env:FUZZ_STRICT_NUL = "1" } else { Remove-Item Env:FUZZ_STRICT_NUL -ErrorAction SilentlyContinue }

$exe = Join-Path $repoRoot "out/fuzz_parsers.exe"
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("pulse-fuzz-" + [guid]::NewGuid().ToString("N"))
$outFile = "$base.out"
$errFile = "$base.err"
$proc = Start-Process -FilePath $exe -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile

$timedOut = $false
try {
    $proc | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
} catch {
    $timedOut = $true
}
if ($timedOut -and -not $proc.HasExited) {
    & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
}

$stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { "" }
$stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { "" }
Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
if ($stdout) { Write-Host $stdout.TrimEnd() }
if ($stderr) { Write-Host $stderr.TrimEnd() }

if ($timedOut) {
    Write-Host "fuzz: TIMEOUT after ${TimeoutSec}s -- process tree killed"
    exit 124
}
if ($proc.ExitCode -ne 0) {
    Write-Host "fuzz: FAILED (process exit $($proc.ExitCode))"
    exit $proc.ExitCode
}
Write-Host "fuzz: PASS"
exit 0
