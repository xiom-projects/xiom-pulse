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
    [int]$TimeoutSec = 180,
    [string]$Icon = "resources\img\pulse-ico.ico",
    [switch]$NoIcon
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

# --- Windows exe icon (workaround until `xiom --icon` ships, v0.64.1+) -----
# Uses rcedit when available; not an error when missing (the service also
# serves the same icon at /favicon.ico). See docs/COMPILER-FINDINGS-PULSE.md.
if (-not $NoIcon -and $Icon) {
    $iconPath = Join-Path $repoRoot $Icon
    if (Test-Path -LiteralPath $iconPath) {
        $rcedit = Get-Command rcedit -ErrorAction SilentlyContinue
        if ($null -eq $rcedit) { $rcedit = Get-Command rcedit-x64 -ErrorAction SilentlyContinue }
        if ($null -eq $rcedit) {
            # Fallbacks: npm global shim/binary, then the pinned tools dir CI
            # and local installs use (the toolchain does not ship --icon yet).
            $candidates = @(
                (Join-Path $env:APPDATA "npm\rcedit.cmd"),
                (Join-Path $env:APPDATA "npm\node_modules\rcedit\bin\rcedit-x64.exe"),
                (Join-Path $env:LOCALAPPDATA "xiom-tools\rcedit-x64.exe")
            )
            foreach ($c in $candidates) {
                if ($c -and (Test-Path -LiteralPath $c)) {
                    $rcedit = [pscustomobject]@{ Source = $c }
                    break
                }
            }
        }
        if ($null -ne $rcedit) {
            & $rcedit.Source $outExe --set-icon $iconPath 2>&1 | Out-Null
            if ($?) {
                Write-Host "build: exe icon set via rcedit ($iconPath)"
            } else {
                Write-Host "build: WARNING rcedit failed to set the icon"
            }
        } else {
            Write-Host "build: rcedit not found -- exe icon not set (install rcedit or wait for 'xiom --icon')"
        }
    }
}

Write-Host "build: OK $outExe"
exit 0
