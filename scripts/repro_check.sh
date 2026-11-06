#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- same-host reproducible-build gate (Unix payload).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds src/server.xi twice in this workspace with distinct names and compares
# the SHA-256 of the two executables. Same-host payload gate only; cross-host
# and zip reproducibility stay open (docs/REPRODUCIBLE-BUILD.md).
#
# Exit code 0 = identical, 1 = mismatch, other = build failure.
# Usage: bash scripts/repro_check.sh [--timeout 300]
# ============================================================================
set -euo pipefail

TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

bash scripts/build.sh src/server.xi --name repro_a --timeout-sec "$TIMEOUT" >/dev/null
bash scripts/build.sh src/server.xi --name repro_b --timeout-sec "$TIMEOUT" >/dev/null

a="$(hash_file out/repro_a)"
b="$(hash_file out/repro_b)"
size_a="$(wc -c < out/repro_a | tr -d ' ')"
size_b="$(wc -c < out/repro_b | tr -d ' ')"

rm -f out/repro_a out/repro_b

if [ "$a" != "$b" ]; then
  echo "repro: RED payload mismatch" >&2
  echo "  a=$a ($size_a bytes)" >&2
  echo "  b=$b ($size_b bytes)" >&2
  exit 1
fi
echo "repro: GREEN same-host payload sha256=$a ($size_a bytes)"
