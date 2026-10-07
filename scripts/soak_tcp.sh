#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE soak driver (Linux/WSL): start the compiled probe server, run
# the XIOM client twice, soak with curl, QUIT, and report stability.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/soak_tcp.sh --seconds 60
# Exit code: 0 = all green, 1 = failed.
# Mirrors scripts/soak_tcp.ps1. probe_tcp_server2 hardcodes :19080.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: soak_tcp.sh [--seconds N] [--port N] [--interval-ms N]
                   [--server-exe PATH] [--client-exe PATH]

  --seconds N      soak duration (default 60)
  --port N         server port (default 19080; probe is fixed at 19080)
  --interval-ms N  delay between requests (default 400)
  --server-exe P   probe server (default out/tcp_srv2)
  --client-exe P   XIOM probe client (default out/tcp_cli2)
EOF
}

SECONDS_ARG=60
PORT=19080
INTERVAL_MS=400
SERVER_EXE="$PULSE_REPO_ROOT/out/tcp_srv2"
CLIENT_EXE="$PULSE_REPO_ROOT/out/tcp_cli2"
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds) SECONDS_ARG=${2:?missing value}; shift 2 ;;
    --port) PORT=${2:?missing value}; shift 2 ;;
    --interval-ms) INTERVAL_MS=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    --client-exe) CLIENT_EXE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE (run scripts/build.sh tests/probes/probe_tcp_server2.xi)"
[ -x "$CLIENT_EXE" ] || pulse_die "client not built: $CLIENT_EXE (run scripts/build.sh tests/probes/probe_tcp_client2.xi)"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
SERVER_LOG="$LOG_DIR/soak-tcp.out"

pulse_log "soak: starting $SERVER_EXE"
"$SERVER_EXE" >"$SERVER_LOG" 2>&1 &
SRV_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$SERVER_LOG" 2>/dev/null || true
  pulse_die "probe server did not listen on 127.0.0.1:$PORT"
fi

# --- x2 XIOM client runs ----------------------------------------------------
C1=1
C2=1
if "$CLIENT_EXE"; then C1=0; else C1=$?; fi
if "$CLIENT_EXE"; then C2=0; else C2=$?; fi

# --- soak -------------------------------------------------------------------
MEM0=$(proc_rss_kb "$SRV_PID")
FD0=$(proc_fd_count "$SRV_PID")
pulse_log "soak: ${SECONDS_ARG}s, interval ${INTERVAL_MS}ms; baseline rss=${MEM0}KB fds=${FD0}"

OK=0
FAIL=0
START=$(date +%s)
SLEEP_S=$(awk "BEGIN { printf \"%.3f\", $INTERVAL_MS / 1000 }")
while :; do
  NOW=$(date +%s)
  [ $((NOW - START)) -lt "$SECONDS_ARG" ] || break
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    "$(pulse_base)/soak" 2>/dev/null || printf '000')
  if [ "$CODE" = "200" ]; then
    OK=$((OK + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  sleep "$SLEEP_S"
done

MEM1=$(proc_rss_kb "$SRV_PID")
FD1=$(proc_fd_count "$SRV_PID")

# --- QUIT -------------------------------------------------------------------
tcp_probe_quit
if ! wait_exit "$SRV_PID" 15; then
  pulse_log "soak: server did not exit after QUIT; killing"
  kill_tree "$SRV_PID" 2
fi
wait "$SRV_PID" 2>/dev/null
SRV_EXIT=$?

pulse_log "--- server output ---"
tail -n 6 "$SERVER_LOG" 2>/dev/null || true
pulse_log "--- soak result ---"
pulse_log "soak: client1_exit=$C1 client2_exit=$C2 ok=$OK fail=$FAIL"
pulse_log "soak: rss ${MEM0}KB -> ${MEM1}KB; fds ${FD0} -> ${FD1}"
pulse_log "soak: server_exit=$SRV_EXIT"

SERVED=$(grep -oE 'served=[0-9]+' "$SERVER_LOG" | tail -n 1 | cut -d= -f2 || true)
SERVED=${SERVED:-"-1"}
pulse_log "soak: served=$SERVED expected>=$((OK + 2))"

# QUIT is not counted as served; expect served == ok + 2 client runs.
if [ "$C1" -eq 0 ] && [ "$C2" -eq 0 ] && [ "$FAIL" -eq 0 ] && \
   [ "$SRV_EXIT" -eq 0 ] && [ "$SERVED" -eq "$((OK + 2))" ]; then
  pulse_log "soak: GREEN"
  exit 0
fi
pulse_log "soak: RED"
exit 1
