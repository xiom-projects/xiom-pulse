#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- raw framing security smoke (Unix).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds a uniquely named server binary (pulse_framing_<port>) unless
# --server-exe/--no-build is supplied, then runs scripts/security_smoke.py
# framing against it. Exit code = the engine's exit code (0 = green).
#
# Usage:
#   bash scripts/framing_smoke.sh
#   bash scripts/framing_smoke.sh --port 18400 --allow-known-gaps
#   bash scripts/framing_smoke.sh --server-exe out/pulse_app --no-build
# ============================================================================
set -u

PORT=18400
SERVER_EXE=""
ALLOW=0
STRICT=0
KEEP=0
NOBUILD=0
PY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=${2:?missing --port value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing --server-exe value}; shift 2 ;;
    --allow-known-gaps) ALLOW=1; shift ;;
    --strict-nul) STRICT=1; shift ;;
    --keep) KEEP=1; shift ;;
    --no-build) NOBUILD=1; shift ;;
    --python) PY=${2:?missing --python value}; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -z "$SERVER_EXE" ]; then
  NAME="pulse_framing_$PORT"
  if [ "$NOBUILD" -eq 0 ]; then
    bash scripts/build.sh src/server.xi --name "$NAME" --timeout-sec 600 || exit $?
  fi
  SERVER_EXE="out/$NAME"
fi
if [ ! -f "$SERVER_EXE" ]; then
  printf 'framing smoke: server binary not found: %s\n' "$SERVER_EXE" >&2
  exit 2
fi

if [ -z "$PY" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PY=python3
  elif command -v python >/dev/null 2>&1; then
    PY=python
  else
    printf 'framing smoke: python3/python not found\n' >&2
    exit 2
  fi
fi

ARGS=(scripts/security_smoke.py framing --server-exe "$SERVER_EXE" --port "$PORT")
[ "$ALLOW" -eq 1 ] && ARGS+=(--allow-known-gaps)
[ "$STRICT" -eq 1 ] && ARGS+=(--strict-nul)
[ "$KEEP" -eq 1 ] && ARGS+=(--keep)

exec "$PY" "${ARGS[@]}"
