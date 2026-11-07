#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE N-ports worker smoke (Linux/WSL): build a uniquely named
# binary, run two workers on distinct ports (the portable baseline), probe
# GET /health on both, then kill both and report GREEN/RED.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/worker_smoke.sh [--port1 N] [--port2 N]
# Exit code: 0 = green, 1 = failed. Mirrors scripts/worker_smoke.ps1.
#
# This deliberately does NOT set PULSE_REUSEPORT=1: N distinct ports is the
# portable baseline. The reuseport path is exercised by the app startup log.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: worker_smoke.sh [--port1 N] [--port2 N]

  --port1 N   first worker port (default 18201)
  --port2 N   second worker port (default 18202)
EOF
}

PORT1=18201
PORT2=18202
while [ $# -gt 0 ]; do
  case "$1" in
    --port1) PORT1=${2:?missing value}; shift 2 ;;
    --port2) PORT2=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! bash "$PULSE_SCRIPTS_DIR/build.sh" "$PULSE_REPO_ROOT/src/server.xi" \
     --name worker_app --timeout-sec 300; then
  pulse_log "worker-smoke: RED (build failed)"
  exit 1
fi
SERVER_EXE="$PULSE_REPO_ROOT/out/worker_app"
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs/worker-smoke"
mkdir -p "$LOG_DIR"

PID1=""
PID2=""
cleanup() {
  if [ -n "$PID1" ]; then kill_tree "$PID1" 5; fi
  if [ -n "$PID2" ]; then kill_tree "$PID2" 5; fi
}
trap cleanup EXIT

pulse_log "worker-smoke: starting worker 0 on 127.0.0.1:$PORT1"
(
  cd "$PULSE_REPO_ROOT" || exit 1
  exec env PULSE_BIND=127.0.0.1 PULSE_PORT="$PORT1" PULSE_WORKER_ID=0 \
    PULSE_REUSEPORT=0 PULSE_LOG=0 \
    PULSE_STORE_PATH="$LOG_DIR/w0-events.jsonl" \
    PULSE_AUDIT_PATH="$LOG_DIR/w0-audit.log" \
    "$SERVER_EXE"
) >"$LOG_DIR/w0-$PORT1.out" 2>&1 &
PID1=$!

pulse_log "worker-smoke: starting worker 1 on 127.0.0.1:$PORT2"
(
  cd "$PULSE_REPO_ROOT" || exit 1
  exec env PULSE_BIND=127.0.0.1 PULSE_PORT="$PORT2" PULSE_WORKER_ID=1 \
    PULSE_REUSEPORT=0 PULSE_LOG=0 \
    PULSE_STORE_PATH="$LOG_DIR/w1-events.jsonl" \
    PULSE_AUDIT_PATH="$LOG_DIR/w1-audit.log" \
    "$SERVER_EXE"
) >"$LOG_DIR/w1-$PORT2.out" 2>&1 &
PID2=$!

wait_listen "$PORT1" 15 || true
wait_listen "$PORT2" 15 || true

health_code() {
  local port=$1 i=0 code=""
  while [ "$i" -lt 75 ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
      "http://127.0.0.1:$port/health" 2>/dev/null || true)
    if [ "$code" = "200" ]; then
      printf '200'
      return 0
    fi
    sleep 0.2
    i=$((i + 1))
  done
  printf '%s' "$code"
}

H1=$(health_code "$PORT1")
H2=$(health_code "$PORT2")

GREEN=yes
if [ "$H1" = "200" ]; then
  pulse_log "[PASS] worker 0 GET /health 200 ($PORT1)"
else
  pulse_log "[FAIL] worker 0 GET /health not 200 ($PORT1, got '$H1')"
  GREEN=no
fi
if [ "$H2" = "200" ]; then
  pulse_log "[PASS] worker 1 GET /health 200 ($PORT2)"
else
  pulse_log "[FAIL] worker 1 GET /health not 200 ($PORT2, got '$H2')"
  GREEN=no
fi

kill_tree "$PID1" 10
wait "$PID1" 2>/dev/null || true
PID1=""
kill_tree "$PID2" 10
wait "$PID2" 2>/dev/null || true
PID2=""

if [ "$GREEN" = "yes" ]; then
  pulse_log "worker-smoke: GREEN"
  exit 0
fi

pulse_log "---- worker 0 log ----"
tail -n 40 "$LOG_DIR/w0-$PORT1.out" "$LOG_DIR/w0-$PORT1.err" 2>/dev/null || true
pulse_log "---- worker 1 log ----"
tail -n 40 "$LOG_DIR/w1-$PORT2.out" "$LOG_DIR/w1-$PORT2.err" 2>/dev/null || true
pulse_log "worker-smoke: RED"
exit 1
