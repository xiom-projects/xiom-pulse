#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- ORBITDB hard-kill conformance runner (Linux).
# Writer mode puts 999 committed keys + starts one UNCOMMITTED txn, writes a
# marker file, then waits. This runner SIGKILLs the writer group and runs
# verify mode: prefix intact, uncommitted window discarded, append + reopen.
# See xiom-orbitdb docs/PULSE-INTEGRATION.md section 5.2/3.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:   bash scripts/interop_orbitdb_crash.sh
# Exit:    0 = verify green, 1 = verify red, 2 = setup/handshake failure.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGDIR="$REPO_ROOT/probe-logs"
TMP="$REPO_ROOT/tests/interop/orbitdb/.tmp"
PROBE="$REPO_ROOT/tests/interop/orbitdb/probe_pkg_orbitdb.xi"
MARKER="$TMP/crash-ready.marker"
mkdir -p "$LOGDIR" "$TMP"
rm -f "$MARKER"

# setsid gives the writer its own process group so SIGKILL reaches
# bash -> timeout -> xiom -> a.out.
ORBITDB_PROBE_MODE=writer setsid bash "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 300 \
  >"$LOGDIR/orbitdb-crash-writer.out" 2>&1 &
WPID=$!

ready=0
for _ in $(seq 1 240); do
  if [ -f "$MARKER" ]; then
    ready=1
    break
  fi
  sleep 0.5
done
if [ "$ready" -ne 1 ]; then
  kill -9 -"$WPID" 2>/dev/null || kill -9 "$WPID" 2>/dev/null || true
  printf 'crash: writer marker timeout (see %s)\n' "$LOGDIR/orbitdb-crash-writer.out"
  exit 2
fi
kill -9 -"$WPID" 2>/dev/null || kill -9 "$WPID" 2>/dev/null || true
sleep 1

ORBITDB_PROBE_MODE=verify bash "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 300 \
  >"$LOGDIR/orbitdb-crash-verify.out" 2>&1
RC=$?
grep -e 'verify:' -e '\[PASS\]' -e '\[FAIL\]' "$LOGDIR/orbitdb-crash-verify.out" | tail -n 4
if [ "$RC" -eq 0 ]; then
  printf 'orbitdb crash: GREEN (hard kill -> prefix intact, uncommitted discarded, reopen OK)\n'
  exit 0
fi
printf 'orbitdb crash: RED (verify rc=%s)\n' "$RC"
exit 1
