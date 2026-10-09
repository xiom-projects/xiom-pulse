#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE data snapshot (Linux): copies the event store and the audit
# log (+ .1 rotation backup) into backups/<UTC timestamp>/ with a manifest
# (sizes + sha256), then prunes to the newest --keep snapshots. When the
# kv backend is in use the segment directory is snapshotted instead
# (kv-store/ in the snapshot).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/backup.sh                          # defaults below
#   scripts/backup.sh --store pulse-events.jsonl --audit pulse-audit.log
#   scripts/backup.sh --kv-dir pulse-kv        # kv backend snapshot
#   scripts/backup.sh --out-dir backups --keep 7
#
# Defaults follow the server config: store $PULSE_STORE_PATH or
# pulse-events.jsonl, audit $PULSE_AUDIT_PATH or pulse-audit.log; with
# PULSE_STORE_BACKEND=kv the kv dir defaults to $PULSE_KV_DIR or pulse-kv.
# Restore procedure: docs/DEPLOYMENT.md ("Backup and restore").
# Exit code: 0 = snapshot written (missing sources are noted, not fatal).
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: backup.sh [--store PATH] [--audit PATH] [--kv-dir DIR] [--out-dir DIR] [--keep N]

  --store P    event store path (default: $PULSE_STORE_PATH or pulse-events.jsonl)
  --audit P    audit log path (default: $PULSE_AUDIT_PATH or pulse-audit.log)
  --kv-dir D   kv segment directory (default with PULSE_STORE_BACKEND=kv:
               $PULSE_KV_DIR or pulse-kv)
  --out-dir D  snapshot root (default: backups/)
  --keep N     snapshots to retain, newest first (default: 7)
EOF
}

STORE="${PULSE_STORE_PATH:-pulse-events.jsonl}"
AUDIT="${PULSE_AUDIT_PATH:-pulse-audit.log}"
KV_DIR=""
if [ "${PULSE_STORE_BACKEND:-jsonl}" = "kv" ]; then
  KV_DIR="${PULSE_KV_DIR:-pulse-kv}"
fi
OUT_DIR="backups"
KEEP=7
while [ $# -gt 0 ]; do
  case "$1" in
    --store) STORE=${2:?missing value}; shift 2 ;;
    --audit) AUDIT=${2:?missing value}; shift 2 ;;
    --kv-dir) KV_DIR=${2:?missing value}; shift 2 ;;
    --out-dir) OUT_DIR=${2:?missing value}; shift 2 ;;
    --keep) KEEP=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y%m%d-%H%M%S)
DEST="$OUT_DIR/$TS"
mkdir -p "$DEST"

MANIFEST="$DEST/MANIFEST.txt"
{
  printf 'pulse backup snapshot\n'
  printf 'created_utc: %s\n' "$(pulse_now)"
  printf 'store_src: %s\n' "$STORE"
  printf 'audit_src: %s\n' "$AUDIT"
  printf 'kv_src: %s\n' "${KV_DIR:--}"
} >"$MANIFEST"

copy_one() { # SRC DEST_NAME
  local src=$1 name=$2
  if [ -f "$src" ]; then
    cp "$src" "$DEST/$name"
    local size hash
    size=$(wc -c <"$DEST/$name" | tr -d ' ')
    hash=$(pulse_sha256 "$DEST/$name")
    printf '%s: copied size=%s sha256=%s\n' "$name" "$size" "$hash" >>"$MANIFEST"
    pulse_log "backup: $name size=$size"
  else
    printf '%s: MISSING (skipped)\n' "$name" >>"$MANIFEST"
    pulse_log "backup: $name missing (skipped)"
  fi
}

# copy_kv_dir snapshots the whole segment directory. The server keeps the
# dir open while running: for a consistent snapshot prefer compacting
# first (POST /api/events/compact) and note the restore-verification step
# in docs/DEPLOYMENT.md ("KV store").
copy_kv_dir() { # DIR
  local src=$1
  if [ -d "$src" ]; then
    cp -R "$src" "$DEST/kv-store"
    local n=0 rel size hash
    while IFS= read -r f; do
      n=$((n + 1))
      rel=${f#"$DEST/kv-store/"}
      size=$(wc -c <"$f" | tr -d ' ')
      hash=$(pulse_sha256 "$f")
      printf 'kv-store/%s: copied size=%s sha256=%s\n' "$rel" "$size" "$hash" >>"$MANIFEST"
    done < <(find "$DEST/kv-store" -type f | sort)
    pulse_log "backup: kv-store $n files"
  else
    printf 'kv-store/: MISSING (skipped)\n' >>"$MANIFEST"
    pulse_log "backup: kv-store missing (skipped)"
  fi
}

copy_one "$STORE" "store.jsonl"
copy_one "$AUDIT" "audit.log"
copy_one "$AUDIT.1" "audit.log.1"
if [ -n "$KV_DIR" ]; then
  copy_kv_dir "$KV_DIR"
fi

if [ "$KEEP" -gt 0 ]; then
  # Snapshot dirs are UTC timestamps; lexical desc == newest first.
  ( cd "$OUT_DIR" && ls -1d [0-9]* 2>/dev/null | sort -r | tail -n "+$((KEEP + 1))" | while IFS= read -r old; do
      rm -rf "$old"
      printf 'pruned: %s\n' "$old" >>"$DEST/../pruned.log"
      pulse_log "backup: pruned $old"
    done )
fi

pulse_log "backup: snapshot $DEST"
exit 0
