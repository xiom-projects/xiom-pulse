# ============================================================================
# XIOM PULSE release packager (Windows): build, stage and zip one artifact
# per the ops naming convention: pulse-<ver>-<os>-<arch>.zip + .sha256.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\release.ps1                    # version parsed from src\pulse.xi
#   .\scripts\release.ps1 -Version 0.2.0 -OutDir dist
#   .\scripts\release.ps1 -NoBuild           # reuse out\pulse_app.exe as-is
#
# Exit code: 0 = artifact + checksum written.
# ============================================================================

param(
    [string]$Version = "",
    [string]$OutDir = "",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dev-env.ps1")

if (-not $Version) {
    $m = Select-String -Path (Join-Path $repoRoot "src\pulse.xi") -Pattern '"([0-9]+\.[0-9]+\.[0-9]+)"'
    if ($m) { $Version = $m.Matches[0].Groups[1].Value }
}
if (-not $Version) { throw "could not determine version (pass -Version)" }

if (-not $OutDir) { $OutDir = Join-Path $repoRoot "dist" }

if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot "build.ps1") (Join-Path $repoRoot "src\server.xi") -Name pulse_app
    if ($LASTEXITCODE -ne 0) { throw "build failed" }
}
$exe = Join-Path $repoRoot "out\pulse_app.exe"
if (-not (Test-Path -LiteralPath $exe)) { throw "out\pulse_app.exe missing (build first)" }

$name = "pulse-$Version-windows-x64"
$stage = Join-Path $OutDir $name
if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force -LiteralPath $stage }
New-Item -ItemType Directory -Path (Join-Path $stage "resources\img") -Force | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $stage "pulse_app.exe")
Copy-Item -LiteralPath (Join-Path $repoRoot "resources\img\pulse-ico.ico") -Destination (Join-Path $stage "resources\img\pulse-ico.ico")
Copy-Item -LiteralPath (Join-Path $repoRoot "README.md") -Destination (Join-Path $stage "README.md")
Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE-APACHE") -Destination (Join-Path $stage "LICENSE-APACHE")
Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE-MIT") -Destination (Join-Path $stage "LICENSE-MIT")
Copy-Item -LiteralPath (Join-Path $repoRoot "NOTICE") -Destination (Join-Path $stage "NOTICE")

$zip = Join-Path $OutDir "$name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -Force -LiteralPath $zip }
if (Test-Path -LiteralPath "$zip.sha256") { Remove-Item -Force -LiteralPath "$zip.sha256" }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower()
Set-Content -LiteralPath "$zip.sha256" -Value "$hash  $name.zip" -NoNewline

Write-Host "release: artifact $zip"
Write-Host "release: checksum $zip.sha256"
Write-Host "release: contents:"
Get-ChildItem -Recurse -File -LiteralPath $stage | ForEach-Object { $_.FullName.Replace($stage + "\", "") } | Sort-Object
exit 0
