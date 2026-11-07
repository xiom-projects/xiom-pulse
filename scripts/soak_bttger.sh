#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- bttger-mix soak wrapper (Linux/WSL/macOS).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Thin wrapper over scripts/soak_bttger.py; every flag is passed through.
# Exact 24 h WP1 gate command:
#   bash scripts/soak_bttger.sh --seconds 86400 --rate 100 --port 18800 \
#       --max-rss-mb 256 --rebuild
#
# 60 s validation command:
#   bash scripts/soak_bttger.sh --seconds 60 --rate 100 --max-rss-mb 256 --rebuild
#
# Exit codes: 0 = gate PASS, 1 = gate FAIL, 2 = usage error, 130 = SIGINT.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_CMD=()
if [ -n "${PYTHON:-}" ]; then
  read -r -a PYTHON_CMD <<<"$PYTHON"
else
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && \
       "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      PYTHON_CMD=("$cand")
      break
    fi
  done
  if [ "${#PYTHON_CMD[@]}" -eq 0 ] && command -v py >/dev/null 2>&1; then
    if py -3 -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      PYTHON_CMD=(py -3)
    fi
  fi
fi
if [ "${#PYTHON_CMD[@]}" -eq 0 ]; then
  printf 'soak-bttger: Python 3 not found (set PYTHON or install python3)\n' >&2
  exit 1
fi

exec "${PYTHON_CMD[@]}" "$SCRIPT_DIR/soak_bttger.py" "$@"
