#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE rate-limit smoke (Linux/WSL): start the server with
# PULSE_RATE_LIMIT=2, burst 8 rapid requests, expect some 429 +
# Retry-After, then a refill pass.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/rate_smoke.sh [--port N] [--server-exe PATH]
# Exit code: 0 = green, 1 = failed. Mirrors scripts/rate_smoke.ps1.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: rate_smoke.sh [--port N] [--server-exe PATH]

  --port N         listen port (default 18086)
  --server-exe P   PULSE binary (default out/pulse_app)
EOF
}

PORT=18086
SERVER_EXE="$PULSE_REPO_ROOT/out/pulse_app"
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
SERVER_LOG="$LOG_DIR/rate-smoke-server.out"

PULSE_PORT="$PORT" PULSE_RATE_LIMIT=2 PULSE_RATE_BURST=2 \
  "$SERVER_EXE" >"$SERVER_LOG" 2>&1 &
SRV_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$SERVER_LOG" 2>/dev/null || true
  pulse_die "server did not listen on 127.0.0.1:$PORT"
fi
sleep 0.2

OK=0
LIMITED=0
OTHER=0
R429=""
i=0
while [ "$i" -lt 8 ]; do
  R=$(http_get /health)
  case "$R" in
    *"HTTP/1.1 200"*) OK=$((OK + 1)) ;;
    *"HTTP/1.1 429"*)
      LIMITED=$((LIMITED + 1))
      [ -n "$R429" ] || R429=$R
      ;;
    *) OTHER=$((OTHER + 1)) ;;
  esac
  i=$((i + 1))
done

sleep 1.3
AFTER=$(http_get /health)
AFTER_OK=no
case "$AFTER" in
  *"HTTP/1.1 200"*) AFTER_OK=yes ;;
esac

pulse_quit
if ! wait_exit "$SRV_PID" 15; then
  kill_tree "$SRV_PID" 2
fi
wait "$SRV_PID" 2>/dev/null
SRV_EXIT=$?

# --- per-route policy leg ---------------------------------------------------
# Global off; only GET /health has a 1 req/s bucket. /api/version must stay
# untouched, and /health must refill after a second.
SERVER_LOG2="$LOG_DIR/rate-smoke-route-server.out"
PULSE_PORT="$PORT" PULSE_RATE_LIMIT=0 PULSE_RATE_ROUTES="GET /health=1/1" \
  "$SERVER_EXE" >"$SERVER_LOG2" 2>&1 &
SRV2_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$SERVER_LOG2" 2>/dev/null || true
  pulse_die "route-rate server did not listen on 127.0.0.1:$PORT"
fi
sleep 0.2

P1=$(http_get /health)
P2=$(http_get /health)
V1=$(http_get /api/version)
V2=$(http_get /api/version)
sleep 1.2
P3=$(http_get /health)

pulse_quit
if ! wait_exit "$SRV2_PID" 15; then
  kill_tree "$SRV2_PID" 2
fi
wait "$SRV2_PID" 2>/dev/null
SRV2_EXIT=$?

ROUTE_OK=no
if printf '%s' "$P1" | grep -q "HTTP/1.1 200" && \
   printf '%s' "$P2" | grep -q "HTTP/1.1 429" && \
   printf '%s' "$V1" | grep -q "HTTP/1.1 200" && \
   printf '%s' "$V2" | grep -q "HTTP/1.1 200" && \
   printf '%s' "$P3" | grep -q "HTTP/1.1 200"; then
  ROUTE_OK=yes
fi
ROUTE_RETRY=no
case "$P2" in
  *"Retry-After:"*) ROUTE_RETRY=yes ;;
esac

pulse_log "rate-smoke: burst 200=$OK 429=$LIMITED other=$OTHER; after-refill_200=$AFTER_OK; server_exit=$SRV_EXIT"
pulse_log "rate-smoke: route policy 200/429/200/200/200=$ROUTE_OK; retry=$ROUTE_RETRY; server_exit=$SRV2_EXIT"

RETRY_OK=no
case "$R429" in
  *"Retry-After:"*) RETRY_OK=yes ;;
esac

if [ "$OK" -ge 2 ] && [ "$LIMITED" -ge 1 ] && [ "$OTHER" -eq 0 ] && \
   [ "$AFTER_OK" = "yes" ] && [ "$SRV_EXIT" -eq 0 ] && [ "$RETRY_OK" = "yes" ] && \
   [ "$ROUTE_OK" = "yes" ] && [ "$ROUTE_RETRY" = "yes" ] && [ "$SRV2_EXIT" -eq 0 ]; then
  pulse_log "rate-smoke: GREEN"
  exit 0
fi
pulse_log "rate-smoke: RED (retry_header=$RETRY_OK route_ok=$ROUTE_OK route_retry=$ROUTE_RETRY)"
pulse_log "---- 429 sample ----"
printf '%s\n' "$R429"
pulse_log "---- route samples ----"
printf '%s\n' "$P1" "$P2"
pulse_log "-----------------------"
exit 1
