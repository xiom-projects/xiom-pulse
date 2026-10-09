#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE builder (Linux/WSL) -- compile one XIOM file to out/<name>,
# with a hard compile watchdog. Mirrors scripts/build.ps1.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/build.sh src/server.xi --name pulse_app
#   scripts/build.sh tests/probes/probe_tcp_server2.xi
#
# Exit code: compiler exit code (0 = built, 124 = watchdog).
# The exe icon step of the PS twin is Windows-only (rcedit); on Linux the
# service icon is the /favicon.ico route, so --no-icon is a no-op here.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: build.sh <file.xi> [--name NAME] [--timeout-sec N] [--no-icon]

  --name NAME        output binary name (default: source basename)
  --timeout-sec N    watchdog seconds (default 180)
  --no-icon          accepted for PS-flag parity (no-op on Linux)
EOF
}

FILE=""
NAME=""
TIMEOUT_SEC=180
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    --no-icon) shift ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) FILE=$1; shift ;;
  esac
done
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -f "$FILE" ] || pulse_die "file not found: $FILE"

pulse_env_ready

if [ -z "$NAME" ]; then
  NAME=$(basename "$FILE" .xi)
fi
OUT_DIR="$PULSE_REPO_ROOT/out"
mkdir -p "$OUT_DIR"
OUT_BIN="$OUT_DIR/$NAME"

FILE_ABS=$(realpath "$FILE")
pulse_log "build: $FILE -> $OUT_BIN"
TMP=$(pulse_tmp)
TIMEOUT_BIN=$(pulse_timeout_bin)
if [ -n "$TIMEOUT_BIN" ]; then
  ( cd "$PULSE_REPO_ROOT" && exec "$TIMEOUT_BIN" "$TIMEOUT_SEC" "$XIOM_COMPILER" -o "$OUT_BIN" "$FILE_ABS" ) >"$TMP" 2>&1
else
  pulse_log "build: no timeout/gtimeout available; building without a watchdog (job timeout applies)"
  ( cd "$PULSE_REPO_ROOT" && exec "$XIOM_COMPILER" -o "$OUT_BIN" "$FILE_ABS" ) >"$TMP" 2>&1
fi
RC=$?
sed -n '1,400p' "$TMP"
rm -f "$TMP"

if [ "$RC" -eq 124 ]; then
  pulse_log "build: TIMEOUT after ${TIMEOUT_SEC}s"
  exit 124
fi
if [ "$RC" -ne 0 ]; then
  pulse_log "build: FAILED (compiler exit $RC)"
  exit "$RC"
fi
if [ ! -x "$OUT_BIN" ]; then
  pulse_log "build: compiler exit 0 but $OUT_BIN missing"
  exit 1
fi
pulse_log "build: OK $OUT_BIN"
exit 0
