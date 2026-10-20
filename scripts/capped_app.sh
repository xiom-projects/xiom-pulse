#!/usr/bin/env bash
# XIOM PULSE -- run the app with a hard RSS watchdog (Linux/WSL).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Owner directive (2026-10-20): cap app RAM on workstation checks so a leak
# cannot crash the PC. Default 2048 MB; override PULSE_MAX_RSS_MB. Polls
# VmRSS (Linux) or ps RSS (macOS/BSD) and kills the process tree with KILL
# when the cap is exceeded (exit 137). Use this wrapper for every
# manual/long app run on the workstation.
set -u
MAX_MB=${PULSE_MAX_RSS_MB:-2048}
if [ "$#" -lt 1 ]; then
  echo "usage: $0 <exe> [args...]   (PULSE_MAX_RSS_MB=$MAX_MB)" >&2
  exit 2
fi
if [ "$MAX_MB" -lt 64 ]; then
  echo "capped-app: PULSE_MAX_RSS_MB must be >= 64" >&2
  exit 2
fi
CAP_KB=$((MAX_MB * 1024))

"$@" &
PID=$!
trap 'kill -TERM "$PID" 2>/dev/null || true' INT TERM
while kill -0 "$PID" 2>/dev/null; do
  RSS=""
  if [ -r "/proc/$PID/status" ]; then
    RSS=$(awk '/VmRSS/ {print $2}' "/proc/$PID/status" 2>/dev/null)
  else
    RSS=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
  fi
  if [ -n "$RSS" ] && [ "$RSS" -gt "$CAP_KB" ]; then
    echo "capped-app: RSS ${RSS}KB > ${MAX_MB}MB; killing PID $PID" >&2
    kill -KILL "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    exit 137
  fi
  sleep 0.25
done
wait "$PID"
exit $?
