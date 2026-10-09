#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE RSS-growth probe (Linux/WSL): starts the server, serves /health
# at a fixed interval, samples VmRSS and reports growth per request with a
# 10s progress curve. Diagnostic for C-PULSE-14 (Linux request-path
# retention); the growth numbers are DATA -- the exit code only gates on a
# clean server start/stop.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/rss_probe.sh [--seconds N] [--interval-ms N] [--port N]
#                             [--server-exe PATH]
# Summary: probe-logs/rss-probe.summary.txt. Mirrors scripts/rss_probe.ps1.
# Exit: 0 = ran cleanly (growth is informational), 1 = server start/stop failed.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: rss_probe.sh [--seconds N] [--interval-ms N] [--port N] [--server-exe PATH]

  --seconds N      probe duration (default 120)
  --interval-ms N  delay between /health requests (default 500)
  --port N         listen port (default 18096)
  --server-exe P   PULSE binary (default out/pulse_app)
EOF
}

SECONDS_ARG=120
INTERVAL_MS=500
PORT=18096
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
SUMMARY="$LOG_DIR/rss-probe.summary.txt"
STORE="$LOG_DIR/rss-probe.jsonl"
rm -f "$STORE"

PULSE_PORT="$PORT" PULSE_LOG=0 PULSE_STORE_PATH="$STORE" \
  "$SERVER_EXE" >"$LOG_DIR/rss-probe-server.out" 2>&1 &
SRV=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$LOG_DIR/rss-probe-server.out" 2>/dev/null || true
  pulse_die "server did not listen on 127.0.0.1:$PORT"
fi
sleep 0.2

RSS0=$(proc_rss_kb "$SRV")
RSS0=${RSS0:-0}
START=$(date +%s)
{
  printf 'rss-probe: baseline rss_kb=%s interval_ms=%s for %ss\n' "$RSS0" "$INTERVAL_MS" "$SECONDS_ARG"
} | tee "$SUMMARY"

SLEEP_S=$(awk "BEGIN { printf \"%.3f\", $INTERVAL_MS / 1000 }")
REQS=0
FAILED=0
LAST_SAMPLE=$START
SAMPLE_N=0
SSD_RSS=$RSS0
SSD_REQS=0
while :; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  [ "$ELAPSED" -lt "$SECONDS_ARG" ] || break
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$(pulse_base)/health" || true)
  if [ "$CODE" = "200" ]; then
    REQS=$((REQS + 1))
  else
    FAILED=$((FAILED + 1))
  fi
  if [ $((NOW - LAST_SAMPLE)) -ge 10 ]; then
    RSS_NOW=$(proc_rss_kb "$SRV")
    RSS_NOW=${RSS_NOW:-0}
    LINE="$(pulse_now) elapsed=${ELAPSED}s requests=$REQS fail=$FAILED rss_kb=$RSS_NOW"
    printf '%s\n' "$LINE" | tee -a "$SUMMARY"
    LAST_SAMPLE=$NOW
    SAMPLE_N=$((SAMPLE_N + 1))
    if [ "$SAMPLE_N" -eq 2 ]; then
      SSD_RSS=$RSS_NOW
      SSD_REQS=$REQS
    fi
  fi
  sleep "$SLEEP_S"
done

RSS_END=$(proc_rss_kb "$SRV")
RSS_END=${RSS_END:-0}
GROWTH_KB=$((RSS_END - RSS0))
PER_REQ=$(awk "BEGIN { if ($REQS > 0) printf \"%.2f\", $GROWTH_KB / $REQS; else printf \"0\" }")
SSD_GROWTH_KB=$((RSS_END - SSD_RSS))
SSD_REQS_N=$((REQS - SSD_REQS))
SSD_PER=$(awk "BEGIN { if ($SSD_REQS_N > 0) printf \"%.2f\", $SSD_GROWTH_KB / $SSD_REQS_N; else printf \"0\" }")
{
  printf 'rss-probe summary (%s)\n' "$(pulse_now)"
  printf 'server: %s\n' "$SERVER_EXE"
  printf 'duration: %ss, interval %sms\n' "$SECONDS_ARG" "$INTERVAL_MS"
  printf 'requests: ok=%s fail=%s\n' "$REQS" "$FAILED"
  printf 'rss_kb: %s -> %s (growth %s KB, %s KB/request incl. warmup)\n' "$RSS0" "$RSS_END" "$GROWTH_KB" "$PER_REQ"
  printf 'steady (2nd sample onward): %s requests, growth %s KB, %s KB/request\n' "$SSD_REQS_N" "$SSD_GROWTH_KB" "$SSD_PER"
} | tee -a "$SUMMARY"

curl -s -o /dev/null -H 'X-Pulse-Quit: 1' "$(pulse_base)/health" || true
if ! wait_exit "$SRV" 15; then
  kill_tree "$SRV" 2
fi
wait "$SRV" 2>/dev/null
SRV_EXIT=$?
printf 'server_exit: %s\n' "$SRV_EXIT" | tee -a "$SUMMARY"
if [ "$SRV_EXIT" -eq 0 ]; then
  pulse_log "rss-probe: done"
  exit 0
fi
pulse_log "rss-probe: RED (server_exit=$SRV_EXIT)"
exit 1
