#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE HTTP soak (Linux/WSL): run the server for N seconds, hammer
# /health, sample RSS/fds every minute, QUIT cleanly, write a summary.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/soak_http.sh --seconds 3600
# Exit code: 0 = no failures + clean shutdown, 1 = failed.
# Mirrors scripts/soak_http.ps1.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: soak_http.sh [--seconds N] [--port N] [--interval-ms N] [--server-exe PATH]

  --seconds N      soak duration (default 1800)
  --port N         listen port (default 8080)
  --interval-ms N  delay between requests (default 500)
  --server-exe P   PULSE binary (default out/pulse_app)
EOF
}

SECONDS_ARG=1800
PORT=8080
INTERVAL_MS=500
SERVER_EXE="$PULSE_REPO_ROOT/out/pulse_app"
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds) SECONDS_ARG=${2:?missing value}; shift 2 ;;
    --port) PORT=${2:?missing value}; shift 2 ;;
    --interval-ms) INTERVAL_MS=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
PROGRESS_FILE="$LOG_DIR/soak-http-progress.txt"
SUMMARY_FILE="$LOG_DIR/soak-http.summary.txt"
SERVER_LOG="$LOG_DIR/soak-http-server.out"

PULSE_PORT="$PORT" "$SERVER_EXE" >"$SERVER_LOG" 2>&1 &
SRV_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$SERVER_LOG" 2>/dev/null || true
  pulse_die "server did not listen on 127.0.0.1:$PORT"
fi
sleep 0.4

MEM0=$(proc_rss_kb "$SRV_PID")
FD0=$(proc_fd_count "$SRV_PID")
pulse_log "soak-http: baseline rss=${MEM0}KB fds=${FD0} for ${SECONDS_ARG}s"
printf '%s elapsed=0s ok=0 fail=0 rss=%s fds=%s\n' "$(pulse_now)" "$MEM0" "$FD0" >>"$PROGRESS_FILE"

OK=0
FAIL=0
START=$(date +%s)
LAST_SAMPLE=$START
SLEEP_S=$(awk "BEGIN { printf \"%.3f\", $INTERVAL_MS / 1000 }")

while :; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  [ "$ELAPSED" -lt "$SECONDS_ARG" ] || break

  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    "$(pulse_base)/health" 2>/dev/null || printf '000')
  if [ "$CODE" = "200" ]; then
    OK=$((OK + 1))
  else
    sleep 0.2
    CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
      "$(pulse_base)/health" 2>/dev/null || printf '000')
    if [ "$CODE" = "200" ]; then
      OK=$((OK + 1))
    else
      FAIL=$((FAIL + 1))
      printf '%s FAIL code=%s elapsed=%ss\n' "$(pulse_now)" "$CODE" "$ELAPSED" >>"$PROGRESS_FILE"
    fi
  fi

  NOW=$(date +%s)
  if [ $((NOW - LAST_SAMPLE)) -ge 60 ]; then
    MEM=$(proc_rss_kb "$SRV_PID")
    FDS=$(proc_fd_count "$SRV_PID")
    printf '%s elapsed=%ss ok=%s fail=%s rss=%s fds=%s\n' \
      "$(pulse_now)" "$((NOW - START))" "$OK" "$FAIL" "$MEM" "$FDS" >>"$PROGRESS_FILE"
    LAST_SAMPLE=$NOW
  fi

  sleep "$SLEEP_S"
done

MEM1=$(proc_rss_kb "$SRV_PID")
FD1=$(proc_fd_count "$SRV_PID")

pulse_quit
if ! wait_exit "$SRV_PID" 15; then
  pulse_log "soak-http: server did not exit after QUIT; killing"
  kill_tree "$SRV_PID" 2
fi
wait "$SRV_PID" 2>/dev/null
SRV_EXIT=$?

{
  printf 'soak-http summary (UTC %s)\n' "$(pulse_now)"
  printf 'server: %s\n' "$SERVER_EXE"
  printf 'duration: %ss, interval %sms\n' "$SECONDS_ARG" "$INTERVAL_MS"
  printf 'requests: ok=%s fail=%s\n' "$OK" "$FAIL"
  printf 'memory:   rss %sKB -> %sKB\n' "$MEM0" "$MEM1"
  printf 'fds:      %s -> %s\n' "$FD0" "$FD1"
  printf 'server_exit: %s\n' "$SRV_EXIT"
  printf -- '--- server log tail ---\n'
  tail -n 5 "$SERVER_LOG" 2>/dev/null || true
} | tee "$SUMMARY_FILE"

if [ "$FAIL" -eq 0 ] && [ "$SRV_EXIT" -eq 0 ]; then
  pulse_log "soak-http: GREEN"
  exit 0
fi
pulse_log "soak-http: RED"
exit 1
