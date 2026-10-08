# ============================================================================
# XIOM PULSE data snapshot (Windows): copies the event store and the audit
# log (+ .1 rotation backup) into backups\<UTC timestamp>\ with a manifest
# (sizes + sha256), then prunes to the newest -Keep snapshots. When the kv
# backend is in use the segment directory is snapshotted instead
# (kv-store\ in the snapshot).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\backup.ps1
#   .\scripts\backup.ps1 -Store pulse-events.jsonl -Audit pulse-audit.log
#   .\scripts\backup.ps1 -KvDir pulse-kv    # kv backend snapshot
#   .\scripts\backup.ps1 -OutDir backups -Keep 7
#
# Defaults follow the server config: store $env:PULSE_STORE_PATH or
# pulse-events.jsonl, audit $env:PULSE_AUDIT_PATH or pulse-audit.log; with
# PULSE_STORE_BACKEND=kv the kv dir defaults to $env:PULSE_KV_DIR or
# pulse-kv. Restore procedure: docs\DEPLOYMENT.md ("Backup and restore").
# Exit code: 0 = snapshot written (missing sources are noted, not fatal).
# ============================================================================

param(
    [string]$Store = "",
    [string]$Audit = "",
    [string]$KvDir = "",
    [string]$OutDir = "backups",
    [int]$Keep = 7
)

$ErrorActionPreference = "Stop"

if (-not $Store) { $Store = if ($env:PULSE_STORE_PATH) { $env:PULSE_STORE_PATH } else { "pulse-events.jsonl" } }
if (-not $Audit) { $Audit = if ($env:PULSE_AUDIT_PATH) { $env:PULSE_AUDIT_PATH } else { "pulse-audit.log" } }
if (-not $KvDir -and $env:PULSE_STORE_BACKEND -eq "kv") {
    $KvDir = if ($env:PULSE_KV_DIR) { $env:PULSE_KV_DIR } else { "pulse-kv" }
}

$ts = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$dest = Join-Path $OutDir $ts
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$manifest = Join-Path $dest "MANIFEST.txt"
$kvSrcNote = if ($KvDir) { $KvDir } else { "-" }
@(
    "pulse backup snapshot",
    "created_utc: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    "store_src: $Store",
    "audit_src: $Audit",
    "kv_src: $kvSrcNote"
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

# Copy-KvDir snapshots the whole segment directory. The server keeps the
# dir open while running: for a consistent snapshot prefer compacting
# first (POST /api/events/compact) and note the restore-verification step
# in docs\DEPLOYMENT.md ("KV store").
function Copy-KvDir {
    param([string]$Src)
    if (Test-Path -LiteralPath $Src -PathType Container) {
        $dstKv = Join-Path $dest "kv-store"
        Copy-Item -LiteralPath $Src -Destination $dstKv -Recurse
        $files = Get-ChildItem -LiteralPath $dstKv -Recurse -File | Sort-Object FullName
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($dstKv.Length + 1).Replace('\', '/')
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower()
            Add-Content -LiteralPath $manifest -Value "kv-store/$rel`: copied size=$($f.Length) sha256=$hash"
        }
        Write-Host "backup: kv-store $($files.Count) files"
    } else {
        Add-Content -LiteralPath $manifest -Value "kv-store/: MISSING (skipped)"
        Write-Host "backup: kv-store missing (skipped)"
    }
}

Copy-One $Store "store.jsonl"
Copy-One $Audit "audit.log"
Copy-One "$Audit.1" "audit.log.1"
if ($KvDir) { Copy-KvDir $KvDir }

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
