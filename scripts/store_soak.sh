#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE storage soak (Linux/WSL): continuous event writes over HTTP,
# periodic count verification, compaction, hard kill, reopen and count
# re-verification.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/store_soak.sh --seconds 600
# Exit code: 0 = green, 1 = failed.
# Summary: probe-logs/store-soak.summary.txt
# Mirrors scripts/store_soak.ps1.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: store_soak.sh [--seconds N] [--interval-ms N] [--port N] [--server-exe PATH]

  --seconds N      soak duration (default 600)
  --interval-ms N  delay between writes (default 200)
  --port N         listen port (default 18089)
  --server-exe P   PULSE binary (default out/pulse_app)
EOF
}

SECONDS_ARG=600
INTERVAL_MS=200
PORT=18089
SERVER_EXE="$PULSE_REPO_ROOT/out/pulse_app"
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds) SECONDS_ARG=${2:?missing value}; shift 2 ;;
    --interval-ms) INTERVAL_MS=${2:?missing value}; shift 2 ;;
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
STORE="$LOG_DIR/store-soak.jsonl"
SUMMARY_FILE="$LOG_DIR/store-soak.summary.txt"
SERVER_LOG="$LOG_DIR/store-soak-server.out"
rm -f "$STORE"

start_pulse() {
  PULSE_PORT="$PORT" PULSE_STORE_PATH="$STORE" PULSE_LOG=0 \
    "$SERVER_EXE" >"$SERVER_LOG" 2>&1 &
  SRV=$!
  if ! wait_listen "$PORT" 10; then
    tail -n 20 "$SERVER_LOG" 2>/dev/null || true
    pulse_die "server did not listen on 127.0.0.1:$PORT"
  fi
  sleep 0.2
}

get_count() {
  local R C
  R=$(http_get /api/events/count)
  C=$(printf '%s' "$R" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2 || true)
  [ -n "$C" ] || pulse_die "count not found: $R"
  printf '%s' "$C"
}

start_pulse
SRV1=$SRV
BASELINE=$(get_count)
pulse_log "store-soak: baseline count=$BASELINE for ${SECONDS_ARG}s"

OK=0
FAIL=0
MISMATCH=0
START=$(date +%s)
LAST_CHECK=$START
SLEEP_S=$(awk "BEGIN { printf \"%.3f\", $INTERVAL_MS / 1000 }")
i=0
while :; do
  NOW=$(date +%s)
  [ $((NOW - START)) -lt "$SECONDS_ARG" ] || break
  i=$((i + 1))
  R=$(post_json /api/events "{\"kind\":\"soak\",\"n\":$i}")
  case "$R" in
    *"HTTP/1.1 200"*) OK=$((OK + 1)) ;;
    *) FAIL=$((FAIL + 1)) ;;
  esac

  NOW=$(date +%s)
  if [ $((NOW - LAST_CHECK)) -ge 60 ]; then
    C=$(get_count)
    EXPECTED=$((BASELINE + OK))
    if [ "$C" -ne "$EXPECTED" ]; then
      MISMATCH=$((MISMATCH + 1))
      printf '%s MISMATCH count=%s expected=%s\n' "$(pulse_now)" "$C" "$EXPECTED" >>"$SUMMARY_FILE"
    fi
    pulse_log "store-soak: elapsed=$((NOW - START))s ok=$OK fail=$FAIL count=$C"
    LAST_CHECK=$NOW
  fi
  sleep "$SLEEP_S"
done

# --- compaction -------------------------------------------------------------
R=$(post_empty /api/events/compact)
COMPACT_OK=no
case "$R" in
  *"HTTP/1.1 200"*) COMPACT_OK=yes ;;
esac
COUNT_COMPACT=$(get_count)

# --- hard kill + reopen -----------------------------------------------------
kill -KILL "$SRV1" 2>/dev/null || true
wait "$SRV1" 2>/dev/null || true
sleep 0.3
start_pulse
SRV2=$SRV
COUNT_REOPEN=$(get_count)

http_get /health >/dev/null 2>&1 || true
pulse_quit
if ! wait_exit "$SRV2" 15; then
  kill_tree "$SRV2" 2
fi
wait "$SRV2" 2>/dev/null
SRV_EXIT=$?

EXPECTED_FINAL=$((BASELINE + OK))
# kv mode writes no JSONL file: report store_bytes empty (PS twin parity)
# instead of letting the redirection fail noisily.
STORE_BYTES=""
if [ -f "$STORE" ]; then
  STORE_BYTES=$(wc -c <"$STORE" | tr -d ' ')
fi
{
  printf 'store-soak summary (UTC %s)\n' "$(pulse_now)"
  printf 'duration: %ss, interval %sms\n' "$SECONDS_ARG" "$INTERVAL_MS"
  printf 'writes: ok=%s fail=%s\n' "$OK" "$FAIL"
  printf 'baseline=%s count_after_compact=%s count_after_reopen=%s expected=%s\n' \
    "$BASELINE" "$COUNT_COMPACT" "$COUNT_REOPEN" "$EXPECTED_FINAL"
  printf 'compaction_ok=%s count_mismatches=%s\n' "$COMPACT_OK" "$MISMATCH"
  printf 'server_exit=%s store_bytes=%s\n' "$SRV_EXIT" "$STORE_BYTES"
} | tee "$SUMMARY_FILE"

if [ "$FAIL" -eq 0 ] && [ "$MISMATCH" -eq 0 ] && [ "$COMPACT_OK" = "yes" ] && \
   [ "$COUNT_COMPACT" -eq "$EXPECTED_FINAL" ] && \
   [ "$COUNT_REOPEN" -eq "$EXPECTED_FINAL" ] && [ "$SRV_EXIT" -eq 0 ]; then
  pulse_log "store-soak: GREEN"
  exit 0
fi
pulse_log "store-soak: RED"
exit 1
