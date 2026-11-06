#!/usr/bin/env pwsh
# ============================================================================
# XIOM PULSE -- deterministic cookie/auth fuzz gate.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds tests/fuzz_cookie.xi and runs it under a watchdog. The harness is
# deterministic (PCG seed) and covers xiom.cookie request/Set-Cookie parsing
# and serialization plus the xiom.pulse.sessions session/CSRF helpers.
# Exit code 0 = green, 1 = findings, 124 = timeout, other = crash.
#
# -AllowKnownCrlf records the known parser CRLF-preservation finding instead
# of failing; use it to check the rest of the surface while the parser fix is
# pending. The default is strict (exit 1 on the finding).
# ============================================================================
[CmdletBinding()]
param(
    [int]$TimeoutSec = 300,
    [switch]$AllowKnownCrlf
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build.ps1") "tests/fuzz_cookie.xi" -Name fuzz_cookie -TimeoutSec 300 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "cookie fuzz harness build failed" }

if ($AllowKnownCrlf) { $env:FUZZ_COOKIE_ALLOW_CRLF = "1" } else { Remove-Item Env:FUZZ_COOKIE_ALLOW_CRLF -ErrorAction SilentlyContinue }

$exe = Join-Path $repoRoot "out/fuzz_cookie.exe"
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("pulse-fuzz-cookie-" + [guid]::NewGuid().ToString("N"))
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
    Write-Host "fuzz_cookie: TIMEOUT after ${TimeoutSec}s -- process tree killed"
    exit 124
}
if ($proc.ExitCode -ne 0) {
    Write-Host "fuzz_cookie: FAILED (process exit $($proc.ExitCode))"
    exit $proc.ExitCode
}
Write-Host "fuzz_cookie: PASS"
exit 0
