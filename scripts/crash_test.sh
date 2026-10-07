#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE crash/reopen test (Linux/WSL): write events, hard-kill the
# server (SIGKILL), leave a torn line, reopen, verify the prefix is intact
# and the store heals for the next append.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/crash_test.sh [--port N] [--events N] [--server-exe PATH]
# Exit code: 0 = green, 1 = failed. Mirrors scripts/crash_test.ps1.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: crash_test.sh [--port N] [--events N] [--server-exe PATH]

  --port N         listen port (default 18084)
  --events N       events written before the crash (default 20)
  --server-exe P   PULSE binary (default out/pulse_app)
EOF
}

PORT=18084
EVENTS=20
SERVER_EXE="$PULSE_REPO_ROOT/out/pulse_app"
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=${2:?missing value}; shift 2 ;;
    --events) EVENTS=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
STORE="$LOG_DIR/crash-store.jsonl"
rm -f "$STORE"

start_pulse() { # LOGFILE
  PULSE_PORT="$PORT" PULSE_STORE_PATH="$STORE" "$SERVER_EXE" >"$1" 2>&1 &
  SRV=$!
  if ! wait_listen "$PORT" 10; then
    tail -n 20 "$1" 2>/dev/null || true
    pulse_die "server did not listen on 127.0.0.1:$PORT"
  fi
  sleep 0.2
}

get_count() {
  local R C
  R=$(http_get /api/events/count)
  C=$(printf '%s' "$R" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2 || true)
  if [ -z "$C" ]; then
    pulse_die "count not found in: $R"
  fi
  printf '%s' "$C"
}

# --- phase 1: write events --------------------------------------------------
start_pulse "$LOG_DIR/crash-server1.out"
SRV1=$SRV
LAST=""
i=1
while [ "$i" -le "$EVENTS" ]; do
  LAST=$(post_json /api/events "{\"kind\":\"evt\",\"n\":$i}")
  i=$((i + 1))
done
pulse_check "post events 200" "$LAST" "200 OK"
C1=$(get_count)
pulse_check_eq "count after writes" "$C1" "$EVENTS"

# --- phase 2: crash + torn line --------------------------------------------
kill -KILL "$SRV1" 2>/dev/null || true
wait "$SRV1" 2>/dev/null || true
sleep 0.3
printf '%s' '{"torn":' >>"$STORE"
SIZE_BEFORE=$(wc -c <"$STORE" | tr -d ' ')
pulse_log "crash: killed server, store=${SIZE_BEFORE} bytes, appended torn line"

# --- phase 3: reopen --------------------------------------------------------
start_pulse "$LOG_DIR/crash-server2.out"
SRV2=$SRV
C2=$(get_count)
pulse_check_eq "prefix intact after crash+torn" "$C2" "$EVENTS"
R=$(post_json /api/events '{"kind":"evt","n":999}')
pulse_check "append after torn heals" "$R" "200 OK"
C3=$(get_count)
pulse_check_eq "count after heal append" "$C3" "$((EVENTS + 1))"
R=$(http_get /api/events)
pulse_check "list has last event" "$R" '"n":999'

# --- shutdown ---------------------------------------------------------------
http_get /health >/dev/null 2>&1 || true
pulse_quit
if ! wait_exit "$SRV2" 15; then
  kill_tree "$SRV2" 2
fi
wait "$SRV2" 2>/dev/null
SRV_EXIT=$?

pulse_summary "crash"
if [ "$PULSE_FAIL" -eq 0 ] && [ "$SRV_EXIT" -eq 0 ]; then
  pulse_log "crash: GREEN"
  exit 0
fi
pulse_log "crash: RED (server_exit=$SRV_EXIT)"
exit 1
