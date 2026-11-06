#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- deterministic fuzz gate (Unix).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds tests/fuzz_parsers.xi and runs it under a watchdog. Exit code 0 =
# green, 1 = findings, 124 = timeout, other = crash.
# --strict-nul turns the known upstream NUL-in-head finding
# (REL-20261106-1716-pulse) into a hard failure.
# Usage: bash scripts/fuzz_parsers.sh [--timeout 300] [--strict-nul]
# ============================================================================
set -euo pipefail

TIMEOUT=300
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --strict-nul) STRICT=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/build.sh tests/fuzz_parsers.xi --name fuzz_parsers --timeout-sec 300 >/dev/null
if [ "$STRICT" = "1" ]; then export FUZZ_STRICT_NUL=1; fi

./out/fuzz_parsers &
pid=$!
( sleep "$TIMEOUT"; kill -9 "$pid" 2>/dev/null || true ) &
watchdog=$!
status=0
wait "$pid" || status=$?
kill "$watchdog" 2>/dev/null || true
if [ "$status" -eq 137 ]; then
  echo "fuzz: TIMEOUT after ${TIMEOUT}s" >&2
  exit 124
fi
exit "$status"
