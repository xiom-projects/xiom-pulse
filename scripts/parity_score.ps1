# XIOM PULSE -- parity score from docs/PARITY-MATRIX.md.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Computes the weighted capability-parity score for the two tiers (Beacon =
# package, Station = standalone), plus assessed coverage and the biggest
# weighted gaps. Status points: P=1, E=1 (capped), A=0.5, M/?=0, N/A ignored.
# Weights: P0=3, P1=2, P2=1. See docs/PARITY-VISION.md.
#
# Usage: .\scripts\parity_score.ps1 [-Path docs\PARITY-MATRIX.md] [-Top 12]
param(
    [string]$Path = "",
    [int]$Top = 12
)
$ErrorActionPreference = "Stop"
if (-not $Path) { $Path = Join-Path (Split-Path -Parent $PSScriptRoot) "docs\PARITY-MATRIX.md" }
if (-not (Test-Path -LiteralPath $Path)) { Write-Host "missing $Path"; exit 2 }

$weights = @{ "P0" = 3; "P1" = 2; "P2" = 1 }
$points  = @{ "P" = 1.0; "E" = 1.0; "A" = 0.5; "M" = 0.0; "?" = 0.0 }
$statuses = @("P", "E", "A", "M", "?")

$rows = @()
$lineNo = 0
foreach ($line in Get-Content -LiteralPath $Path) {
    $lineNo++
    if ($line -notmatch '^\|\s*([A-Z]-\d+)\s*\|') { continue }
    $cells = $line.Split("|")
    if ($cells.Count -lt 8) { continue }
    $id = $cells[1].Trim()
    $cap = $cells[2].Trim()
    $pri = $cells[3].Trim().ToUpper()
    $beacon = $cells[4].Trim().ToUpper()
    $station = $cells[5].Trim().ToUpper()
    if (-not $weights.ContainsKey($pri)) { Write-Warning "line ${lineNo}: unknown priority '$pri'"; continue }
    $rows += [pscustomobject]@{ Id = $id; Cap = $cap; Pri = $pri; Beacon = $beacon; Station = $station }
}

function Score-Tier([string]$tier) {
    $sumW = 0.0; $sumP = 0.0; $assessedW = 0.0; $applicable = 0; $assessedN = 0
    $gaps = @()
    foreach ($r in $rows) {
        $s = $r.$tier
        if ($s -eq "N/A" -or $s -eq "NA") { continue }
        $applicable++
        $w = [double]$weights[$r.Pri]
        $sumW += $w
        $p = 0.0
        if ($points.ContainsKey($s)) { $p = [double]$points[$s] }
        else { Write-Warning "$($r.Id): unknown status '$s' in $tier (counted 0)" }
        $sumP += $w * $p
        if ($s -ne "?") { $assessedW += $w; $assessedN++ }
        if ($p -lt 1.0) {
            $gaps += [pscustomobject]@{ Id = $r.Id; Cap = $r.Cap; Pri = $r.Pri; Tier = $tier; Status = $s; Loss = $w * (1.0 - $p) }
        }
    }
    $pct = if ($sumW -gt 0) { 100.0 * $sumP / $sumW } else { 0.0 }
    $cov = if ($sumW -gt 0) { 100.0 * $assessedW / $sumW } else { 0.0 }
    return [pscustomobject]@{ Tier = $tier; Pct = $pct; Coverage = $cov; Applicable = $applicable; Assessed = $assessedN; Gaps = $gaps }
}

$b = Score-Tier "Beacon"
$s = Score-Tier "Station"

Write-Host ("PULSE parity score -- {0}" -f (Split-Path -Leaf $Path))
Write-Host ("rows: {0} (Beacon applicable {1}, Station applicable {2})" -f $rows.Count, $b.Applicable, $s.Applicable)
Write-Host ("Beacon  (package):   {0,5:N1}%   assessed coverage {1,5:N1}%  ({2}/{3} rows)" -f $b.Pct, $b.Coverage, $b.Assessed, $b.Applicable)
Write-Host ("Station (standalone):{0,5:N1}%   assessed coverage {1,5:N1}%  ({2}/{3} rows)" -f $s.Pct, $s.Coverage, $s.Assessed, $s.Applicable)

$allGaps = @($b.Gaps + $s.Gaps) | Sort-Object -Property Loss -Descending | Select-Object -First $Top
Write-Host ""
Write-Host ("Top {0} weighted gaps:" -f $Top)
foreach ($g in $allGaps) {
    Write-Host ("  {0,-5} {1,-8} {2,-6} {3,-4} loss {4:N1}  {5}" -f $g.Id, $g.Tier, $g.Pri, $g.Status, $g.Loss, $g.Cap)
}

# Machine-readable summary for wraps.
Write-Host ""
Write-Host ("PARITY beacon={0:N1}% station={1:N1}% beacon_cov={2:N1}% station_cov={3:N1}%" -f $b.Pct, $s.Pct, $b.Coverage, $s.Coverage)
exit 0
