# ============================================================================
# XIOM PULSE data snapshot (Windows): copies the event store and the audit
# log (+ .1 rotation backup) into backups\<UTC timestamp>\ with a manifest
# (sizes + sha256), then prunes to the newest -Keep snapshots.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\backup.ps1
#   .\scripts\backup.ps1 -Store pulse-events.jsonl -Audit pulse-audit.log
#   .\scripts\backup.ps1 -OutDir backups -Keep 7
#
# Defaults follow the server config: store $env:PULSE_STORE_PATH or
# pulse-events.jsonl, audit $env:PULSE_AUDIT_PATH or pulse-audit.log.
# Restore procedure: docs\DEPLOYMENT.md ("Backup and restore").
# Exit code: 0 = snapshot written (missing sources are noted, not fatal).
# ============================================================================

param(
    [string]$Store = "",
    [string]$Audit = "",
    [string]$OutDir = "backups",
    [int]$Keep = 7
)

$ErrorActionPreference = "Stop"

if (-not $Store) { $Store = if ($env:PULSE_STORE_PATH) { $env:PULSE_STORE_PATH } else { "pulse-events.jsonl" } }
if (-not $Audit) { $Audit = if ($env:PULSE_AUDIT_PATH) { $env:PULSE_AUDIT_PATH } else { "pulse-audit.log" } }

$ts = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$dest = Join-Path $OutDir $ts
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$manifest = Join-Path $dest "MANIFEST.txt"
@(
    "pulse backup snapshot",
    "created_utc: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    "store_src: $Store",
    "audit_src: $Audit"
) | Set-Content -LiteralPath $manifest

function Copy-One {
    param([string]$Src, [string]$Name)
    if (Test-Path -LiteralPath $Src -PathType Leaf) {
        $dst = Join-Path $dest $Name
        Copy-Item -LiteralPath $Src -Destination $dst
        $size = (Get-Item -LiteralPath $dst).Length
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash.ToLower()
        Add-Content -LiteralPath $manifest -Value "$Name`: copied size=$size sha256=$hash"
        Write-Host "backup: $Name size=$size"
    } else {
        Add-Content -LiteralPath $manifest -Value "$Name`: MISSING (skipped)"
        Write-Host "backup: $Name missing (skipped)"
    }
}

Copy-One $Store "store.jsonl"
Copy-One $Audit "audit.log"
Copy-One "$Audit.1" "audit.log.1"

if ($Keep -gt 0 -and (Test-Path -LiteralPath $OutDir)) {
    $old = Get-ChildItem -LiteralPath $OutDir -Directory |
        Where-Object { $_.Name -match '^\d{8}-\d{6}$' } |
        Sort-Object Name -Descending | Select-Object -Skip $Keep
    foreach ($d in $old) {
        Remove-Item -Recurse -Force -LiteralPath $d.FullName
        Write-Host "backup: pruned $($d.Name)"
    }
}

Write-Host "backup: snapshot $dest"
exit 0
