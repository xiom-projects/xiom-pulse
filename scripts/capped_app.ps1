# XIOM PULSE -- run the app with a hard RSS watchdog (Windows).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Owner directive (2026-10-20): cap app RAM on workstation checks so a leak
# cannot crash the PC. Default 2048 MB; override with -MaxMB or
# PULSE_MAX_RSS_MB. The watchdog polls WorkingSet64 and kills the process
# tree when the cap is exceeded (exit 137). Use this wrapper for every
# manual/long app run on the workstation.
param(
    [int]$MaxMB = $(if ($env:PULSE_MAX_RSS_MB) { [int]$env:PULSE_MAX_RSS_MB } else { 2048 }),
    [int]$PollMs = 250,
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$AppArgs
)

if ($MaxMB -lt 64) { Write-Error "MaxMB must be >= 64"; exit 2 }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Error "not found: $Exe"; exit 2 }

if ($null -eq $AppArgs) { $AppArgs = @() }
if ($AppArgs.Count -gt 0) {
    $p = Start-Process -FilePath $Exe -ArgumentList $AppArgs -PassThru -NoNewWindow
} else {
    $p = Start-Process -FilePath $Exe -PassThru -NoNewWindow
}
if ($null -eq $p) {
    Write-Error "capped-app: failed to start $Exe"
    exit 2
}
$capBytes = [int64]$MaxMB * 1MB
while ($null -ne $p -and -not $p.HasExited) {
    $p.Refresh()
    if ($p.WorkingSet64 -gt $capBytes) {
        Write-Warning ("capped-app: RSS {0:N0} MB > {1} MB; killing PID {2}" -f ($p.WorkingSet64 / 1MB), $MaxMB, $p.Id)
        & taskkill /T /F /PID $p.Id 2>$null | Out-Null
        exit 137
    }
    Start-Sleep -Milliseconds $PollMs
}
exit $p.ExitCode
