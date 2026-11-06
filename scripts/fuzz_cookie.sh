#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- deterministic cookie/auth fuzz gate (Unix).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds tests/fuzz_cookie.xi and runs it under a watchdog. Exit code 0 =
# green, 1 = findings, 124 = timeout, other = crash.
# --allow-known-crlf records the known parser CRLF-preservation finding
# instead of failing; the default is strict.
# Usage: bash scripts/fuzz_cookie.sh [--timeout 300] [--allow-known-crlf]
# ============================================================================
set -euo pipefail

TIMEOUT=300
ALLOW_CRLF=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --allow-known-crlf) ALLOW_CRLF=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/build.sh tests/fuzz_cookie.xi --name fuzz_cookie --timeout-sec 300 >/dev/null
if [ "$ALLOW_CRLF" = "1" ]; then export FUZZ_COOKIE_ALLOW_CRLF=1; fi

./out/fuzz_cookie &
pid=$!
( sleep "$TIMEOUT"; kill -9 "$pid" 2>/dev/null || true ) &
watchdog=$!
status=0
wait "$pid" || status=$?
kill "$watchdog" 2>/dev/null || true
if [ "$status" -eq 137 ]; then
  echo "fuzz_cookie: TIMEOUT after ${TIMEOUT}s" >&2
  exit 124
fi
exit "$status"
