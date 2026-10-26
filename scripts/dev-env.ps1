# XIOM PULSE dev environment -- dot-source in every terminal:
#   . .\scripts\dev-env.ps1
#
# VERSION POLICY (owner decision 2026-10-05): PULSE tracks the LATEST
# compiler / stdlib / packages to harden the ecosystem by real-world use.
# There is no fixed pin; record the exact versions and lane hashes in
# SESSION.md at every wrap. If a latest-version regression breaks the
# fleet, file the finding, note the last known-good version in SESSION.md
# as a ROLLBACK OPTION (owner-visible), and keep moving on other slices.
#
# As of 2026-10-26:
#   compiler  v0.65.1  %LOCALAPPDATA%\xiom.new-v0.65.1\bin\xiom.exe
#             (fallbacks: v0.65.0, v0.64.8, then the unversioned xiom.new)
#   stdlib    latest RELEASE tag, extracted to
#             %LOCALAPPDATA%\xiom-pins\stdlib-tag-v0.65.0 (refresh the dir
#             name when a new stdlib release is cut; falls back to the
#             v0.64.9 / v0.64.8 / v0.64.7 tag dirs, then the lane checkout)
#   packages  %LOCALAPPDATA%\xiom-pulse-home\packages -- LANE-LOCAL since
#             2026-10-24: the shared %LOCALAPPDATA%\xiom\packages is wiped
#             by fleet repins (2026-10-10/12/15/16 and again 2026-10-24).
#             The lane home carries the 12 manifest deps at pinned
#             versions; set XIOM_HOME after sourcing to override.
#
# XIOM_RUNTIME_DIR is RETIRED on v0.64.0: release R65 makes the installed
# compiler link lib\runtime and lib\xiom without overrides. Verified from
# PULSE env-free (XIOM_STDLIB/XIOM_RUNTIME_DIR unset): probe_hello and
# probe_crypto (NIST SHA-256 KAT) both green, 2026-10-05.
#
# PATH warning: a v0.62.3 staging dir shadows xiom.new in PATH -- always
# set XIOM_COMPILER explicitly instead of relying on `xiom` from PATH.

$ErrorActionPreference = "Stop"

# Lane-local package home. The shared default was clobbered repeatedly by
# other lanes' toolchain/package swaps, so PULSE resolves its deps from here
# unless the caller set a non-default XIOM_HOME on purpose.
$sharedHome = Join-Path $env:LOCALAPPDATA "xiom"
$laneHome = Join-Path $env:LOCALAPPDATA "xiom-pulse-home"
if (-not $env:XIOM_HOME -or $env:XIOM_HOME -eq $sharedHome) {
    if (Test-Path -LiteralPath $laneHome) { $env:XIOM_HOME = $laneHome }
}

# An explicit XIOM_COMPILER wins (compiler A/B sweeps, e.g. a lane release
# build); the installed toolchain is only the default. Mirrors dev-env.sh.
if (-not $env:XIOM_COMPILER) {
    $latest = Join-Path $env:LOCALAPPDATA "xiom.new-v0.65.1\bin\xiom.exe"
    $prev = Join-Path $env:LOCALAPPDATA "xiom.new-v0.65.0\bin\xiom.exe"
    $prev2 = Join-Path $env:LOCALAPPDATA "xiom.new-v0.64.8\bin\xiom.exe"
    if (Test-Path -LiteralPath $latest) {
        $env:XIOM_COMPILER = $latest
    } elseif (Test-Path -LiteralPath $prev) {
        $env:XIOM_COMPILER = $prev
    } elseif (Test-Path -LiteralPath $prev2) {
        $env:XIOM_COMPILER = $prev2
    } else {
        $env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
    }
}
if (-not $env:XIOM_STDLIB) {
    $tagStdlib = Join-Path $env:LOCALAPPDATA "xiom-pins\stdlib-tag-v0.65.1"
    $prevStdlib = Join-Path $env:LOCALAPPDATA "xiom-pins\stdlib-tag-v0.65.0"
    $prev2Stdlib = Join-Path $env:LOCALAPPDATA "xiom-pins\stdlib-tag-v0.64.9"
    $prev3Stdlib = Join-Path $env:LOCALAPPDATA "xiom-pins\stdlib-tag-v0.64.8"
    if (Test-Path -LiteralPath $tagStdlib) {
        $env:XIOM_STDLIB = $tagStdlib
    } elseif (Test-Path -LiteralPath $prevStdlib) {
        $env:XIOM_STDLIB = $prevStdlib
    } elseif (Test-Path -LiteralPath $prev2Stdlib) {
        $env:XIOM_STDLIB = $prev2Stdlib
    } elseif (Test-Path -LiteralPath $prev3Stdlib) {
        $env:XIOM_STDLIB = $prev3Stdlib
    } else {
        $env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
    }
}
Remove-Item Env:XIOM_RUNTIME_DIR -ErrorAction SilentlyContinue   # retired

$missing = @()
if (-not (Test-Path -LiteralPath $env:XIOM_COMPILER)) { $missing += "XIOM_COMPILER ($env:XIOM_COMPILER)" }
if (-not (Test-Path -LiteralPath $env:XIOM_STDLIB))   { $missing += "XIOM_STDLIB   ($env:XIOM_STDLIB)" }

if ($missing.Count -gt 0) {
    Write-Warning "dev-env: missing toolchain paths:"
    $missing | ForEach-Object { Write-Warning "  $_" }
    return
}

$ver = (& $env:XIOM_COMPILER --version 2>&1 | Select-Object -First 1)
Write-Host "dev-env: $ver"
Write-Host "dev-env: XIOM_STDLIB = $env:XIOM_STDLIB"
Write-Host "dev-env: XIOM_HOME   = $env:XIOM_HOME"
Write-Host "dev-env: XIOM_RUNTIME_DIR retired (v0.64.0 R65 install-layout fix)"
