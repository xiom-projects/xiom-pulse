# ============================================================================
# XIOM PULSE -- ORBITDB hard-kill conformance runner (Windows).
# Writer mode puts 999 committed keys + starts one UNCOMMITTED txn, writes a
# marker file, then waits. This runner hard-kills the writer tree and runs
# verify mode: prefix intact, uncommitted window discarded, append + reopen.
# See xiom-orbitdb docs/PULSE-INTEGRATION.md section 5.2/3.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:   .\scripts\interop_orbitdb_crash.ps1
# Exit:    0 = verify green, 1 = verify red, 2 = setup/handshake failure.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "dev-env.ps1") *> $null
# taskkill on an already-exited writer must not abort the harness.
$ErrorActionPreference = "Continue"

$probe = Join-Path $repoRoot "tests\interop\orbitdb\probe_pkg_orbitdb.xi"
$runPs1 = Join-Path $PSScriptRoot "run.ps1"
$tmp = Join-Path $repoRoot "tests\interop\orbitdb\.tmp"
$marker = Join-Path $tmp "crash-ready.marker"
$logDir = Join-Path $repoRoot "probe-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

function Start-Mode([string]$mode, [string]$outFile) {
    $errFile = "$outFile.err"
    # cmd wrapper: exit codes survive, and taskkill /T reaches the whole tree
    # (powershell -> xiom -> a.exe). Lesson: file redirection, never pipes.
    $cmdLine = "/c set ORBITDB_PROBE_MODE=$mode&& powershell -NoProfile -ExecutionPolicy Bypass -File `"$runPs1`" `"$probe`" -TimeoutSec 300 1>`"$outFile`" 2>`"$errFile`""
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = $cmdLine
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

$writer = Start-Mode "writer" (Join-Path $logDir "orbitdb-crash-writer.out")
$ready = $false
for ($i = 0; $i -lt 240; $i++) {
    if (Test-Path -LiteralPath $marker) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $ready) {
    & taskkill /T /F /PID $writer.Id 2>$null | Out-Null
    Write-Host "crash: writer marker timeout (see $logDir\orbitdb-crash-writer.out)"
    exit 2
}
& taskkill /T /F /PID $writer.Id 2>$null | Out-Null
Start-Sleep -Seconds 1

$verify = Start-Mode "verify" (Join-Path $logDir "orbitdb-crash-verify.out")
if (-not $verify.WaitForExit(300000)) {
    & taskkill /T /F /PID $verify.Id 2>$null | Out-Null
    Write-Host "crash: verify timeout"
    exit 2
}
Get-Content -LiteralPath (Join-Path $logDir "orbitdb-crash-verify.out") -ErrorAction SilentlyContinue | Write-Host
if ($verify.ExitCode -eq 0) {
    Write-Host "orbitdb crash: GREEN (hard kill -> prefix intact, uncommitted discarded, reopen OK)"
    exit 0
}
Write-Host "orbitdb crash: RED (verify rc=$($verify.ExitCode))"
exit 1
