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
# As of 2026-10-18:
#   compiler  v0.64.7  %LOCALAPPDATA%\xiom.new-v0.64.7\bin\xiom.exe
#             (fallback: the unversioned %LOCALAPPDATA%\xiom.new)
#   stdlib    latest RELEASE tag, extracted to
#             %LOCALAPPDATA%\xiom-pins\stdlib-tag-v0.64.7 (refresh the dir
#             name when a new stdlib release is cut; falls back to the
#             v0.64.6 tag dir, then the lane checkout)
#   packages  %LOCALAPPDATA%\xiom\packages (latest registry versions; the
#             owner directive is to consume the newest fixes)
#
# XIOM_RUNTIME_DIR is RETIRED on v0.64.0: release R65 makes the installed
# compiler link lib\runtime and lib\xiom without overrides. Verified from
# PULSE env-free (XIOM_STDLIB/XIOM_RUNTIME_DIR unset): probe_hello and
# probe_crypto (NIST SHA-256 KAT) both green, 2026-10-05.
#
# PATH warning: a v0.62.3 staging dir shadows xiom.new in PATH -- always
# set XIOM_COMPILER explicitly instead of relying on `xiom` from PATH.

$ErrorActionPreference = "Stop"

# An explicit XIOM_COMPILER wins (compiler A/B sweeps, e.g. a lane release
# build); the installed toolchain is only the default. Mirrors dev-env.sh.
if (-not $env:XIOM_COMPILER) {
    $latest = Join-Path $env:LOCALAPPDATA "xiom.new-v0.64.7\bin\xiom.exe"
    if (Test-Path -LiteralPath $latest) {
        $env:XIOM_COMPILER = $latest
    } else {
        $env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
    }
}
if (-not $env:XIOM_STDLIB) {
    $tagStdlib = Join-Path $env:LOCALAPPDATA "xiom-pins\stdlib-tag-v0.64.7"
    $prevStdlib = Join-Path $env:LOCALAPPDATA "xiom-pins\stdlib-tag-v0.64.6"
    if (Test-Path -LiteralPath $tagStdlib) {
        $env:XIOM_STDLIB = $tagStdlib
    } elseif (Test-Path -LiteralPath $prevStdlib) {
        $env:XIOM_STDLIB = $prevStdlib
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
Write-Host "dev-env: XIOM_RUNTIME_DIR retired (v0.64.0 R65 install-layout fix)"
