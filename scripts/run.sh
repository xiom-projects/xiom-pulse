#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE runner -- compile+run one XIOM file under the tracked toolchain,
# with a hard watchdog and fail-closed exit-code handling.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/run.sh tests/probes/probe_hello.xi
#   scripts/run.sh tests/probes/probe_crypto.xi --timeout-sec 300
#   scripts/run.sh tests/probes/probe_crypto.xi --no-runtime-dir   # A/B probe
#
# Exit code: the program's reported exit code (1 on compile failure,
# 124 on watchdog timeout). Never treats a timeout or an empty run as green.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: run.sh <file.xi> [--timeout-sec N] [--no-runtime-dir] [--quiet]

  --timeout-sec N    watchdog seconds (default 120)
  --no-runtime-dir   drop the retired XIOM_RUNTIME_DIR override (A/B probe)
  --quiet            do not echo program output
EOF
}

FILE=""
TIMEOUT_SEC=120
NO_RUNTIME_DIR=0
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    --no-runtime-dir) NO_RUNTIME_DIR=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) FILE=$1; shift ;;
  esac
done
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -f "$FILE" ] || pulse_die "file not found: $FILE"

pulse_env_ready

if [ "$NO_RUNTIME_DIR" -eq 1 ]; then
  unset XIOM_RUNTIME_DIR
fi

FILE_ABS=$(realpath "$FILE")
OUT=$(pulse_tmp)
TIMEOUT_BIN=$(pulse_timeout_bin)
if [ -n "$TIMEOUT_BIN" ]; then
  ( cd "$PULSE_REPO_ROOT" && exec "$TIMEOUT_BIN" "$TIMEOUT_SEC" "$XIOM_COMPILER" --run "$FILE_ABS" ) >"$OUT" 2>&1
else
  pulse_log "run: no timeout/gtimeout available; running without a watchdog (job timeout applies)"
  ( cd "$PULSE_REPO_ROOT" && exec "$XIOM_COMPILER" --run "$FILE_ABS" ) >"$OUT" 2>&1
fi
RC=$?

if [ "$RC" -eq 124 ]; then
  sed -n '1,200p' "$OUT"
  rm -f "$OUT" "$PULSE_REPO_ROOT/a.out" "$PULSE_REPO_ROOT/a.exe" "$PULSE_REPO_ROOT/a.exe.ll"
  pulse_log "run: TIMEOUT after ${TIMEOUT_SEC}s"
  exit 124
fi

[ "$QUIET" -eq 0 ] && sed -n '1,200p' "$OUT"

# `xiom --run` prints the program's exit code on its own "exit code:" line and
# can exit 0 even when the program crashed; trust the reported code.
PROGRAM_EXIT=""
LINE=$(grep -oE 'exit code:[[:space:]]*-?[0-9]+' "$OUT" | tail -n 1 || true)
if [ -n "$LINE" ]; then
  PROGRAM_EXIT=$(printf '%s' "$LINE" | grep -oE -- '-?[0-9]+$')
fi
rm -f "$OUT" "$PULSE_REPO_ROOT/a.out" "$PULSE_REPO_ROOT/a.exe" "$PULSE_REPO_ROOT/a.exe.ll"

if [ -n "$PROGRAM_EXIT" ]; then
  pulse_log "run: program_exit=$PROGRAM_EXIT compiler_exit=$RC"
  exit "$PROGRAM_EXIT"
fi
pulse_log "run: compiler_exit=$RC (no 'exit code:' line)"
exit "$RC"
