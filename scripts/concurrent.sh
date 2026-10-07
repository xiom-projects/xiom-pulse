#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE concurrency driver (Linux/WSL): open N simultaneous TCP
# connections, then exchange one request per connection.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/concurrent.sh --clients 64
# Exit code: 0 = all N served, 1 = failed.
# Mirrors scripts/concurrent.ps1. NOTE: probe_tcp_server2 hardcodes
# 127.0.0.1:19080, so --port only affects the client side.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: concurrent.sh [--clients N] [--port N] [--path P] [--server-exe PATH]

  --clients N      simultaneous connections (default 64)
  --port N         server port (default 19080; probe is fixed at 19080)
  --path P         request path (default /health)
  --server-exe P   probe server binary (default out/tcp_srv2)
EOF
}

CLIENTS=64
PORT=19080
REQ_PATH="/health"
SERVER_EXE="$PULSE_REPO_ROOT/out/tcp_srv2"
while [ $# -gt 0 ]; do
  case "$1" in
    --clients) CLIENTS=${2:?missing value}; shift 2 ;;
    --port) PORT=${2:?missing value}; shift 2 ;;
    --path) REQ_PATH=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE (run scripts/build.sh tests/probes/probe_tcp_server2.xi)"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
SERVER_LOG="$LOG_DIR/concurrent-server.out"

"$SERVER_EXE" >"$SERVER_LOG" 2>&1 &
SRV_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$SERVER_LOG" 2>/dev/null || true
  pulse_die "probe server did not listen on 127.0.0.1:$PORT"
fi
sleep 0.2

MEM0=$(proc_rss_kb "$SRV_PID")
FD0=$(proc_fd_count "$SRV_PID")

# --- open N simultaneous connections ----------------------------------------
FDS=()
CONNECT_FAIL=0
i=0
while [ "$i" -lt "$CLIENTS" ]; do
  if exec {nfd}<>"/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
    FDS+=("$nfd")
  else
    CONNECT_FAIL=$((CONNECT_FAIL + 1))
  fi
  i=$((i + 1))
done
CONNECTED=${#FDS[@]}
pulse_log "concurrent: connected=$CONNECTED/$CLIENTS connect_fail=$CONNECT_FAIL"

MEM1=$(proc_rss_kb "$SRV_PID")
FD1=$(proc_fd_count "$SRV_PID")

# --- exchange one request per connection ------------------------------------
OK=0
FAIL=0
for fd in "${FDS[@]}"; do
  printf 'GET %s HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nConnection: close\r\n\r\n' \
    "$REQ_PATH" "$PORT" >&"$fd" 2>/dev/null || { FAIL=$((FAIL + 1)); eval "exec $fd>&-"; continue; }
  LINE=""
  if IFS= read -r -t 5 -u "$fd" LINE; then
    case "$LINE" in
      "HTTP/1.1 200"*) OK=$((OK + 1)) ;;
      *) FAIL=$((FAIL + 1)) ;;
    esac
  else
    FAIL=$((FAIL + 1))
  fi
  eval "exec $fd>&-"
done
pulse_log "concurrent: ok=$OK fail=$FAIL"

# --- QUIT (header for the app, QUIT marker for probe_tcp_server2) ----------
tcp_probe_quit
if ! wait_exit "$SRV_PID" 15; then
  pulse_log "concurrent: server did not exit; killing"
  kill_tree "$SRV_PID" 2
fi
wait "$SRV_PID" 2>/dev/null
SRV_EXIT=$?

pulse_log "--- server output ---"
tail -n 4 "$SERVER_LOG" 2>/dev/null || true
pulse_log "concurrent: rss ${MEM0}KB -> ${MEM1}KB; fds ${FD0} -> ${FD1}"
pulse_log "concurrent: server_exit=$SRV_EXIT"

SERVED=$(grep -oE 'served=[0-9]+' "$SERVER_LOG" | tail -n 1 | cut -d= -f2 || true)
SERVED=${SERVED:-"-1"}
pulse_log "concurrent: served=$SERVED expected=$CLIENTS"

if [ "$CONNECTED" -eq "$CLIENTS" ] && [ "$CONNECT_FAIL" -eq 0 ] && \
   [ "$FAIL" -eq 0 ] && [ "$OK" -eq "$CLIENTS" ] && \
   [ "$SRV_EXIT" -eq 0 ] && [ "$SERVED" -eq "$CLIENTS" ]; then
  pulse_log "concurrent: GREEN"
  exit 0
fi
pulse_log "concurrent: RED"
exit 1
