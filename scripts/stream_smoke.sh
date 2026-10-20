#!/usr/bin/env bash
# XIOM PULSE -- live SSE + WebSocket smoke (Linux/WSL wrapper).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Starts the product server, runs scripts/stream_smoke.py against it, then
# quits the server with X-Pulse-Quit. Shared protocol checks live in Python.
set -u
. "$(dirname "$0")/lib.sh"

PORT=18097
SERVER_EXE="./out/pulse_app"
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --server-exe) SERVER_EXE="$2"; shift 2 ;;
    -h|--help) echo "usage: $0 [--port N] [--server-exe PATH]"; exit 0 ;;
    *) pulse_die "unknown argument: $1" ;;
  esac
done

cd "$PULSE_REPO_ROOT" || pulse_die "repo root not found"
[ -x "$SERVER_EXE" ] || pulse_die "server binary not found: $SERVER_EXE"
LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
SRV_LOG="$LOG_DIR/stream-smoke-server-$(date +%Y%m%d%H%M%S).log"

export PULSE_PORT="$PORT"
export PULSE_RATE_LIMIT=0
export PULSE_RATE_ROUTES=""
"$SERVER_EXE" >"$SRV_LOG" 2>&1 &
SRV_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 30 "$SRV_LOG" 2>/dev/null || true
  kill_tree "$SRV_PID" 2
  pulse_die "server did not listen on 127.0.0.1:$PORT"
fi

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
"$PY" "$PULSE_REPO_ROOT/scripts/stream_smoke.py" --port "$PORT"
RC=$?

pulse_quit
if ! wait_exit "$SRV_PID" 10; then
  kill_tree "$SRV_PID" 2
fi
wait "$SRV_PID" 2>/dev/null

if [ "$RC" -ne 0 ]; then
  pulse_log "---- server log ----"
  tail -n 20 "$SRV_LOG" 2>/dev/null || true
  pulse_log "--------------------"
fi
exit "$RC"
