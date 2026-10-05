# XIOM PULSE dev environment -- dot-source in every terminal:
#   . .\scripts\dev-env.ps1
#
# Toolchain pin (fixed 2026-10-05; do not upgrade without the owner):
#   compiler v0.63.1 at %LOCALAPPDATA%\xiom.new\bin\xiom.exe
#   stdlib     E:\xiom-lang\stdlib
#   runtime    E:\xiom-lang\stdlib\runtime   (REQUIRED, see below)
#
# PATH warning: a v0.62.3 staging dir shadows xiom.new in PATH -- always
# set XIOM_COMPILER explicitly instead of relying on `xiom` from PATH.
#
# Why XIOM_RUNTIME_DIR is required: on installed v0.63.1 the AOT link only
# links xiom_runtime.c (the compiler never scans <install>\lib\runtime), so
# any program whose closure uses xiom_async_now_ms (the monotonic clock,
# including the stdlib test harness) fails with
#   lld-link: error: undefined symbol: xiom_async_now_ms
# The override makes the link include async_runtime.c, sha256_sw.c and the
# rest of the runtime dir. Finding + repro: xiom-packages commit 5b7547b0
# (docs/repro/runtime-link/). Re-check at every compiler pin bump; drop the
# override when release notes carry the runtime-discovery fix.

$ErrorActionPreference = "Stop"

$env:XIOM_COMPILER    = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
$env:XIOM_STDLIB      = "E:\xiom-lang\stdlib"
$env:XIOM_RUNTIME_DIR = "E:\xiom-lang\stdlib\runtime"

$missing = @()
if (-not (Test-Path -LiteralPath $env:XIOM_COMPILER))    { $missing += "XIOM_COMPILER   ($env:XIOM_COMPILER)" }
if (-not (Test-Path -LiteralPath $env:XIOM_STDLIB))      { $missing += "XIOM_STDLIB     ($env:XIOM_STDLIB)" }
if (-not (Test-Path -LiteralPath $env:XIOM_RUNTIME_DIR)) { $missing += "XIOM_RUNTIME_DIR ($env:XIOM_RUNTIME_DIR)" }

if ($missing.Count -gt 0) {
    Write-Warning "dev-env: missing toolchain paths:"
    $missing | ForEach-Object { Write-Warning "  $_" }
    return
}

$ver = & $env:XIOM_COMPILER --version 2>&1 | Select-Object -First 1
Write-Host "dev-env: $ver"
Write-Host "dev-env: XIOM_STDLIB      = $env:XIOM_STDLIB"
Write-Host "dev-env: XIOM_RUNTIME_DIR = $env:XIOM_RUNTIME_DIR (required workaround)"
