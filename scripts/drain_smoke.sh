#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE WP4 drain/supervisor smoke (Linux/WSL/macOS).
#
# 1) single worker: control /health 200, wrong-token drain 403, right-token
#    drain 200, exit 0, public port closed;
# 2) supervisor PULSE_WORKERS=2: both public ports 200, supervisor control
#    /health 200, drain 200, all children exit, all ports closed.
# Mirrors scripts/drain_smoke.ps1.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/drain_smoke.sh [--worker-port N] [--worker-control N]
#                               [--supervisor-base N] [--supervisor-control-base N]
# Exit code: 0 = green, 1 = failed.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: drain_smoke.sh [--worker-port N] [--worker-control N]
                      [--supervisor-base N] [--supervisor-control-base N]
EOF
}

WORKER_PORT=18361
WORKER_CONTROL=18362
SUPERVISOR_BASE=18371
SUPERVISOR_CONTROL_BASE=18375
while [ $# -gt 0 ]; do
  case "$1" in
    --worker-port) WORKER_PORT=${2:?missing value}; shift 2 ;;
    --worker-control) WORKER_CONTROL=${2:?missing value}; shift 2 ;;
    --supervisor-base) SUPERVISOR_BASE=${2:?missing value}; shift 2 ;;
    --supervisor-control-base) SUPERVISOR_CONTROL_BASE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! bash "$PULSE_SCRIPTS_DIR/build.sh" "$PULSE_REPO_ROOT/src/server.xi" \
     --name drain_app --timeout-sec 300; then
  pulse_log "drain-smoke: RED (build failed)"
  exit 1
fi
SERVER_EXE="$PULSE_REPO_ROOT/out/drain_app"
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs/drain-smoke"
mkdir -p "$LOG_DIR"
TOKEN="drain-smoke-token"

WORKER_PID=""
SUP_PID=""

kill_descendants() {
  local pid=$1
  local kids
  kids=$(pgrep -P "$pid" 2>/dev/null || true)
  for k in $kids; do kill_descendants "$k"; done
  kill -TERM "$pid" 2>/dev/null || true
}

cleanup() {
  if [ -n "$SUP_PID" ]; then kill_descendants "$SUP_PID"; fi
  if [ -n "$WORKER_PID" ]; then kill_descendants "$WORKER_PID"; fi
}
trap cleanup EXIT

http_code() {
  local method=$1 url=$2 tok=${3:-}
  if [ -n "$tok" ]; then
    curl -s -o /dev/null -w '%{http_code}' --max-time 2 -X "$method" \
      -H "X-Pulse-Control-Token: $tok" "$url" 2>/dev/null || true
  else
    curl -s -o /dev/null -w '%{http_code}' --max-time 2 -X "$method" \
      "$url" 2>/dev/null || true
  fi
}

wait_code() {
  local url=$1 i=0 code=""
  while [ "$i" -lt 75 ]; do
    code=$(http_code GET "$url")
    if [ "$code" = "200" ]; then return 0; fi
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

GREEN=yes

# --- single worker ----------------------------------------------------------
pulse_log "drain-smoke: starting worker on 127.0.0.1:$WORKER_PORT (control $WORKER_CONTROL)"
(
  cd "$PULSE_REPO_ROOT" || exit 1
  exec env PULSE_BIND=127.0.0.1 PULSE_PORT="$WORKER_PORT" \
    PULSE_WORKERS=1 PULSE_WORKER_CHILD=0 \
    PULSE_CONTROL_PORT="$WORKER_CONTROL" PULSE_CONTROL_TOKEN="$TOKEN" \
    PULSE_LOG=0 \
    PULSE_STORE_PATH="$LOG_DIR/worker-events.jsonl" \
    PULSE_AUDIT_PATH="$LOG_DIR/worker-audit.log" \
    "$SERVER_EXE"
) >"$LOG_DIR/worker.out" 2>"$LOG_DIR/worker.err" &
WORKER_PID=$!

if wait_code "http://127.0.0.1:$WORKER_CONTROL/health"; then
  pulse_log "[PASS] control GET /health 200"
else
  pulse_log "[FAIL] control GET /health not 200"
  GREEN=no
fi
C=$(http_code POST "http://127.0.0.1:$WORKER_CONTROL/drain")
if [ "$C" = "403" ]; then pulse_log "[PASS] drain without token 403"; else pulse_log "[FAIL] drain without token=$C (want 403)"; GREEN=no; fi
C=$(http_code POST "http://127.0.0.1:$WORKER_CONTROL/drain" "wrong")
if [ "$C" = "403" ]; then pulse_log "[PASS] drain with wrong token 403"; else pulse_log "[FAIL] drain with wrong token=$C (want 403)"; GREEN=no; fi
C=$(http_code POST "http://127.0.0.1:$WORKER_CONTROL/drain" "$TOKEN")
if [ "$C" = "200" ]; then pulse_log "[PASS] drain with token 200"; else pulse_log "[FAIL] drain with token=$C (want 200)"; GREEN=no; fi

if wait_exit "$WORKER_PID" 5; then
  wait "$WORKER_PID"
  WRC=$?
else
  WRC=127
fi
if [ "$WRC" -eq 0 ]; then
  pulse_log "[PASS] worker exited 0 after drain"
else
  pulse_log "[FAIL] worker exit=$WRC after drain"
  GREEN=no
fi
WORKER_PID=""
C=$(http_code GET "http://127.0.0.1:$WORKER_PORT/health")
if [ "$C" != "200" ]; then pulse_log "[PASS] public port closed after drain"; else pulse_log "[FAIL] public port still 200 after drain"; GREEN=no; fi

# --- supervisor (2 workers) -------------------------------------------------
pulse_log "drain-smoke: starting supervisor (2 workers) on $SUPERVISOR_BASE/$((SUPERVISOR_BASE + 1))"
(
  cd "$PULSE_REPO_ROOT" || exit 1
  exec env PULSE_BIND=127.0.0.1 PULSE_PORT="$SUPERVISOR_BASE" \
    PULSE_WORKERS=2 PULSE_WORKER_CHILD=0 \
    PULSE_CONTROL_PORT="$SUPERVISOR_CONTROL_BASE" PULSE_CONTROL_TOKEN="$TOKEN" \
    PULSE_LOG=0 \
    PULSE_STORE_PATH="$LOG_DIR/sup-events.jsonl" \
    PULSE_AUDIT_PATH="$LOG_DIR/sup-audit.log" \
    "$SERVER_EXE"
) >"$LOG_DIR/supervisor.out" 2>"$LOG_DIR/supervisor.err" &
SUP_PID=$!

H0=no; H1=no
wait_code "http://127.0.0.1:$SUPERVISOR_BASE/health" && H0=yes
wait_code "http://127.0.0.1:$((SUPERVISOR_BASE + 1))/health" && H1=yes
if [ "$H0" = "yes" ] && [ "$H1" = "yes" ]; then
  pulse_log "[PASS] both workers GET /health 200"
else
  pulse_log "[FAIL] worker health: w0=$H0 w1=$H1"
  GREEN=no
fi

SUP_CTL=$((SUPERVISOR_CONTROL_BASE - 1))
if wait_code "http://127.0.0.1:$SUP_CTL/health"; then
  pulse_log "[PASS] supervisor control GET /health 200"
else
  pulse_log "[FAIL] supervisor control GET /health not 200"
  GREEN=no
fi
C=$(http_code POST "http://127.0.0.1:$SUP_CTL/drain" "$TOKEN")
if [ "$C" = "200" ]; then pulse_log "[PASS] supervisor drain 200"; else pulse_log "[FAIL] supervisor drain=$C (want 200)"; GREEN=no; fi

if wait_exit "$SUP_PID" 15; then
  wait "$SUP_PID"
  SRC=$?
else
  SRC=127
fi
if [ "$SRC" -eq 0 ]; then
  pulse_log "[PASS] supervisor exited 0 after drain"
else
  pulse_log "[FAIL] supervisor exit=$SRC after drain"
  GREEN=no
fi
SUP_PID=""
sleep 0.5
P0=$(http_code GET "http://127.0.0.1:$SUPERVISOR_BASE/health")
P1=$(http_code GET "http://127.0.0.1:$((SUPERVISOR_BASE + 1))/health")
if [ "$P0" != "200" ] && [ "$P1" != "200" ]; then
  pulse_log "[PASS] all public ports closed after supervisor drain"
else
  pulse_log "[FAIL] public ports after supervisor drain: $P0/$P1"
  GREEN=no
fi

if [ "$GREEN" = "yes" ]; then
  pulse_log "drain-smoke: GREEN"
  exit 0
fi

pulse_log "---- worker log ----"
tail -n 40 "$LOG_DIR/worker.out" "$LOG_DIR/worker.err" 2>/dev/null || true
pulse_log "---- supervisor log ----"
tail -n 40 "$LOG_DIR/supervisor.out" "$LOG_DIR/supervisor.err" 2>/dev/null || true
pulse_log "drain-smoke: RED"
exit 1
