#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE data snapshot (Linux): copies the event store and the audit
# log (+ .1 rotation backup) into backups/<UTC timestamp>/ with a manifest
# (sizes + sha256), then prunes to the newest --keep snapshots.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/backup.sh                          # defaults below
#   scripts/backup.sh --store pulse-events.jsonl --audit pulse-audit.log
#   scripts/backup.sh --out-dir backups --keep 7
#
# Defaults follow the server config: store $PULSE_STORE_PATH or
# pulse-events.jsonl, audit $PULSE_AUDIT_PATH or pulse-audit.log.
# Restore procedure: docs/DEPLOYMENT.md ("Backup and restore").
# Exit code: 0 = snapshot written (missing sources are noted, not fatal).
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: backup.sh [--store PATH] [--audit PATH] [--out-dir DIR] [--keep N]

  --store P    event store path (default: $PULSE_STORE_PATH or pulse-events.jsonl)
  --audit P    audit log path (default: $PULSE_AUDIT_PATH or pulse-audit.log)
  --out-dir D  snapshot root (default: backups/)
  --keep N     snapshots to retain, newest first (default: 7)
EOF
}

STORE="${PULSE_STORE_PATH:-pulse-events.jsonl}"
AUDIT="${PULSE_AUDIT_PATH:-pulse-audit.log}"
OUT_DIR="backups"
KEEP=7
while [ $# -gt 0 ]; do
  case "$1" in
    --store) STORE=${2:?missing value}; shift 2 ;;
    --audit) AUDIT=${2:?missing value}; shift 2 ;;
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
} >"$MANIFEST"

copy_one() { # SRC DEST_NAME
  local src=$1 name=$2
  if [ -f "$src" ]; then
    cp "$src" "$DEST/$name"
    local size hash
    size=$(wc -c <"$DEST/$name" | tr -d ' ')
    hash=$(sha256sum "$DEST/$name" | cut -d' ' -f1)
    printf '%s: copied size=%s sha256=%s\n' "$name" "$size" "$hash" >>"$MANIFEST"
    pulse_log "backup: $name size=$size"
  else
    printf '%s: MISSING (skipped)\n' "$name" >>"$MANIFEST"
    pulse_log "backup: $name missing (skipped)"
  fi
}

copy_one "$STORE" "store.jsonl"
copy_one "$AUDIT" "audit.log"
copy_one "$AUDIT.1" "audit.log.1"

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
