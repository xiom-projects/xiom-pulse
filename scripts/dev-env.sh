#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE dev environment (Linux/WSL) -- dot-source in every terminal:
#   . scripts/dev-env.sh
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# VERSION POLICY (owner decision 2026-10-05): PULSE tracks the LATEST
# compiler / stdlib / packages to harden the ecosystem by real-world use.
# There is no fixed pin; record the exact versions and lane hashes in
# SESSION.md at every wrap.
#
# As of 2026-10-19 (mirrors scripts/dev-env.ps1 on Windows):
#   compiler  v0.64.9 (versioned install ~/.local/share/xiom-v0649; falls
#             back to v0647 / the canonical ~/.local/share/xiom / PATH)
#   stdlib    $XIOM_STDLIB if set; else the latest RELEASE tag extracted to
#             ~/.cache/xiom-pin/stdlib-tag-v0.64.9 (refresh on a new stdlib
#             release); else the v0.64.7 / v0.64.6 tag dirs; else the WSL-mounted lane
#             checkout /mnt/e/xiom-lang/stdlib; else the compiler's
#             bundled lib/xiom
#   packages  <xiom_home>/packages (latest registry versions; owner
#             directive is to consume the newest fixes)
#
# XIOM_RUNTIME_DIR is RETIRED on v0.64.0: release R65 links the installed
# lib/runtime + lib/xiom without overrides (verified env-free on Windows and
# on the Linux build, 2026-10-05/07). The variable is always cleared here.
#
# Safe to source repeatedly; never exits the caller on warnings.
# ============================================================================

# --- compiler resolution ----------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ]; then
  if [ -x "$HOME/.local/share/xiom-v0649/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/share/xiom-v0649/bin/xiom"
  elif [ -x "$HOME/.local/share/xiom-v0648/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/share/xiom-v0648/bin/xiom"
  elif command -v xiom >/dev/null 2>&1; then
    XIOM_COMPILER="$(command -v xiom)"
  elif [ -x "$HOME/.local/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/bin/xiom"
  elif [ -x "$HOME/.local/share/xiom/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/share/xiom/bin/xiom"
  fi
fi
[ -n "${XIOM_COMPILER:-}" ] && export XIOM_COMPILER

# --- retired runtime override ----------------------------------------------
unset XIOM_RUNTIME_DIR

# --- stdlib -----------------------------------------------------------------
if [ -z "${XIOM_STDLIB:-}" ]; then
  if [ -d "$HOME/.cache/xiom-pin/stdlib-tag-v0.64.9" ]; then
    XIOM_STDLIB="$HOME/.cache/xiom-pin/stdlib-tag-v0.64.9"
  elif [ -d "$HOME/.cache/xiom-pin/stdlib-tag-v0.64.8" ]; then
    XIOM_STDLIB="$HOME/.cache/xiom-pin/stdlib-tag-v0.64.8"
  elif [ -d "$HOME/.cache/xiom-pin/stdlib-tag-v0.64.7" ]; then
    XIOM_STDLIB="$HOME/.cache/xiom-pin/stdlib-tag-v0.64.7"
  elif [ -d /mnt/e/xiom-lang/stdlib ]; then
    # WSL on the development machine: fall back to the lane checkout.
    XIOM_STDLIB=/mnt/e/xiom-lang/stdlib
  fi
fi
[ -n "${XIOM_STDLIB:-}" ] && export XIOM_STDLIB

# --- report -----------------------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'dev-env: WARNING XIOM_COMPILER not found (install the Linux toolchain or export XIOM_COMPILER)\n' >&2
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; else exit 0; fi
fi

_ver="$("$XIOM_COMPILER" --version 2>&1 | head -n 1)"
printf 'dev-env: %s\n' "$_ver"
printf 'dev-env: XIOM_COMPILER = %s\n' "$XIOM_COMPILER"
printf 'dev-env: XIOM_STDLIB   = %s\n' "${XIOM_STDLIB:-<unset: compiler bundled stdlib>}"
printf 'dev-env: XIOM_RUNTIME_DIR retired (v0.64.0 R65 install-layout fix)\n'
unset _ver
