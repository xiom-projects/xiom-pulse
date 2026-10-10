#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- real-libcurl outbound transport probe runner (Linux/WSL).
# Applies the xiom.http 0.1.5 consumer recipe (bridge shims + a scratch
# libcurl.so symlink), starts a local PULSE server, runs
# tests/probes/probe_outbound_transport.xi (guard block -> allowlist ->
# real GET), then quits the server. Evidence-only: not part of the fleet.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:   bash scripts/outbound_transport_probe.sh
# Exit:    0 = green, 1 = probe red, 2 = setup failure.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGDIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOGDIR"

PORT="${PULSE_TRANSPORT_TEST_PORT:-18131}"
SCRATCH="$LOGDIR/outbound-kit-linux"
mkdir -p "$SCRATCH"
LIBCURL="/usr/lib/x86_64-linux-gnu/libcurl.so.4"
[ -f "$LIBCURL" ] || { printf 'libcurl.so.4 missing\n'; exit 2; }
ln -sf "$LIBCURL" "$SCRATCH/libcurl.so"

SHIMS="$(ls "$HOME"/.local/share/xiom/packages/xiom-http-0.1.5/*/bridge/xiom_http_shims.c 2>/dev/null | head -n 1)"
[ -n "$SHIMS" ] || { printf 'xiom_http_shims.c not found (install xiom.http@0.1.5)\n'; exit 2; }
export XIOM_STDLIB="${XIOM_STDLIB:-$HOME/.cache/xiom-pin/stdlib-4dd8844}"
XIOM_COMPILER="${XIOM_COMPILER:-$HOME/.local/bin/xiom}"

cd "$REPO_ROOT"
PULSE_PORT="$PORT" PULSE_BIND=127.0.0.1 PULSE_STORE_PATH="$LOGDIR/outbound-transport-store-linux.jsonl" \
  "$REPO_ROOT/out/pulse_app" >"$LOGDIR/outbound-transport-server-linux.out" 2>&1 &
SPID=$!
up=0
for _ in $(seq 1 40); do
  if curl -s --max-time 1 "http://127.0.0.1:$PORT/health" | grep -q ok; then up=1; break; fi
  sleep 0.25
done
if [ "$up" -ne 1 ]; then
  kill -9 "$SPID" 2>/dev/null || true
  printf 'server did not come up (see %s)\n' "$LOGDIR/outbound-transport-server-linux.out"
  exit 2
fi

PULSE_TRANSPORT_TEST_PORT="$PORT" "$XIOM_COMPILER" -o "$SCRATCH/transport-test" "$REPO_ROOT/tests/probes/probe_outbound_transport.xi" \
  --c-source "$SHIMS" --link curl --link-path "$SCRATCH" \
  >"$LOGDIR/outbound-transport-probe-linux.out" 2>&1
BUILD_RC=$?
if [ "$BUILD_RC" -ne 0 ]; then
  tail -n 12 "$LOGDIR/outbound-transport-probe-linux.out"
  printf 'probe build failed (rc=%s)\n' "$BUILD_RC"
  curl -s -H "X-Pulse-Quit: 1" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || true
  sleep 1
  kill "$SPID" 2>/dev/null || true
  exit 2
fi
PULSE_TRANSPORT_TEST_PORT="$PORT" "$SCRATCH/transport-test" \
  >>"$LOGDIR/outbound-transport-probe-linux.out" 2>&1
RC=$?

curl -s -H "X-Pulse-Quit: 1" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || true
sleep 1
kill "$SPID" 2>/dev/null || true
wait "$SPID" 2>/dev/null || true

tail -n 12 "$LOGDIR/outbound-transport-probe-linux.out"
if [ "$RC" -eq 0 ]; then
  printf 'outbound transport: GREEN (guard block + allowlist + real libcurl GET 200)\n'
  exit 0
fi
printf 'outbound transport: RED (probe rc=%s)\n' "$RC"
exit 1
