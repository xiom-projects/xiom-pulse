# ============================================================================
# XIOM PULSE -- real-libcurl outbound transport probe runner (Windows).
# Applies the xiom.http 0.1.5 consumer recipe (bridge shims + curl.lib
# scratch copy + kit DLL on PATH), starts a local PULSE server, runs
# tests/probes/probe_outbound_transport.xi (guard block -> allowlist ->
# real GET), then quits the server. Evidence-only: not part of the fleet.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Kit default: E:\vcpkg\packages\curl_x64-windows (override CURL_KIT).
# Usage:   .\scripts\outbound_transport_probe.ps1
# Exit:    0 = green, 1 = probe red, 2 = setup failure.

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dev-env.ps1") *> $null

$port = if ($env:PULSE_TRANSPORT_TEST_PORT) { $env:PULSE_TRANSPORT_TEST_PORT } else { "18130" }
$logDir = Join-Path $repoRoot "probe-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$kit = if ($env:CURL_KIT) { $env:CURL_KIT } else { Join-Path $env:LOCALAPPDATA "xiom-tools\curl-for-win\curl-8.22.0_1-win64-mingw" }
$kitLib = Join-Path $kit "lib\libcurl.dll.a"
$kitBin = Join-Path $kit "bin"
if (-not (Test-Path -LiteralPath $kitLib)) { Write-Host "curl kit missing: $kitLib (set CURL_KIT)"; exit 2 }
$scratch = Join-Path $logDir "outbound-kit"
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
Copy-Item -LiteralPath $kitLib -Destination (Join-Path $scratch "curl.lib") -Force
# Keep the kit DLL beside the compiled probe exe: the loader searches the
# exe directory first, so no PATH juggling. The mingw import lib records
# the DLL as libcurl-x64.dll.
Copy-Item -LiteralPath (Join-Path $kitBin "libcurl-x64.dll") -Destination (Join-Path $scratch "libcurl-x64.dll") -Force

$shims = (Get-ChildItem "$env:LOCALAPPDATA\xiom\packages\xiom-http-0.1.5" -Recurse -Filter "xiom_http_shims.c" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
if (-not $shims) { Write-Host "xiom_http_shims.c not found (install xiom.http@0.1.5)"; exit 2 }

$env:PULSE_PORT = $port
$env:PULSE_BIND = "127.0.0.1"
$env:PULSE_STORE_PATH = Join-Path $logDir "outbound-transport-store.jsonl"
$srvOut = Join-Path $logDir "outbound-transport-server.out"
$srv = Start-Process -FilePath (Join-Path $repoRoot "out\pulse_app.exe") -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $srvOut -RedirectStandardError "$srvOut.err"
$up = $false
for ($i = 0; $i -lt 40; $i++) {
    $r = & curl.exe -s --max-time 1 "http://127.0.0.1:$port/health" 2>$null
    if ($r -like "*ok*") { $up = $true; break }
    Start-Sleep -Milliseconds 250
}
if (-not $up) {
    & taskkill /T /F /PID $srv.Id 2>$null | Out-Null
    Write-Host "server did not come up (see $srvOut)"
    exit 2
}

$probe = Join-Path $repoRoot "tests\probes\probe_outbound_transport.xi"
$out = Join-Path $logDir "outbound-transport-probe.out"
$err = "$out.err"
$exe = Join-Path $scratch "transport-test.exe"
# cmd /c with a quoted first token is a quoting trap; generated .cmd files
# carry the paths verbatim.
$compileCmdPath = Join-Path $scratch "compile.cmd"
$compileCmd = @"
@echo off
"$($env:XIOM_COMPILER)" -o "$exe" "$probe" --c-source "$shims" --link curl --link-path "$scratch" 1>"$out" 2>"$err"
exit /b %errorlevel%
"@
Set-Content -LiteralPath $compileCmdPath -Value $compileCmd -Encoding ascii
$c = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $compileCmdPath) -WorkingDirectory $repoRoot -NoNewWindow -PassThru
$null = $c.WaitForExit(300000)
# Start-Process -PassThru leaves ExitCode empty here; the artifact is the gate.
if (-not (Test-Path -LiteralPath $exe)) {
    Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Write-Host
    Get-Content -LiteralPath $err -ErrorAction SilentlyContinue | Write-Host
    Write-Host "probe build failed (no $exe)"
    exit 2
}
$runCmdPath = Join-Path $scratch "run.cmd"
$rcFile = Join-Path $scratch "run.rc"
Remove-Item -LiteralPath $rcFile -Force -ErrorAction SilentlyContinue
$runCmd = @"
@echo off
set PULSE_TRANSPORT_TEST_PORT=$port
set CURL_CA_BUNDLE=$kitBin\curl-ca-bundle.crt
"$exe" 1>>"$out" 2>>"$err"
echo %errorlevel% > "$rcFile"
exit /b %errorlevel%
"@
Set-Content -LiteralPath $runCmdPath -Value $runCmd -Encoding ascii
$p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $runCmdPath) -WorkingDirectory $scratch -NoNewWindow -PassThru
$null = $p.WaitForExit(300000)
if (-not (Test-Path -LiteralPath $rcFile)) {
    & taskkill /T /F /PID $p.Id 2>$null | Out-Null
    Write-Host "probe run did not complete"
    exit 2
}
$rc = [int](Get-Content -LiteralPath $rcFile -Raw).Trim()

$null = & curl.exe -s -H "X-Pulse-Quit: 1" "http://127.0.0.1:$port/health" 2>$null
if (-not $srv.WaitForExit(5000)) { & taskkill /T /F /PID $srv.Id 2>$null | Out-Null }
Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Write-Host

if ($rc -eq 0) {
    Write-Host "outbound transport: GREEN (guard block + allowlist + real libcurl GET 200)"
    exit 0
}
Write-Host "outbound transport: RED (probe rc=$rc)"
exit 1
