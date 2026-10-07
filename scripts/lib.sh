#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- shared helpers for the bash script twins (Linux/WSL).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Sourced by every scripts/*.sh; never executed directly.
# Conventions:
#   * normal logs go to stdout (safe to redirect into an evidence file)
#   * the PULSE server is a single process: stop it by PID (TERM, then KILL)
#   * every script gates its own exit code (0 green / 1 red / 124 timeout)
# ============================================================================

if [ -n "${PULSE_LIB_SOURCED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
PULSE_LIB_SOURCED=1

PULSE_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PULSE_REPO_ROOT="$(dirname "$PULSE_SCRIPTS_DIR")"

# --- logging ----------------------------------------------------------------

pulse_log() { printf '%s\n' "$*"; }

pulse_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

pulse_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- environment ------------------------------------------------------------

# pulse_env_ready -- resolve XIOM_COMPILER (source dev-env.sh) or fail.
pulse_env_ready() {
  if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
    # shellcheck source=dev-env.sh
    . "$PULSE_SCRIPTS_DIR/dev-env.sh"
  fi
  if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
    pulse_die "XIOM_COMPILER not resolved; check scripts/dev-env.sh"
  fi
}

# --- temp files -------------------------------------------------------------

pulse_tmp() {
  mktemp "${TMPDIR:-/tmp}/pulse-XXXXXX"
}

# --- process helpers --------------------------------------------------------

# wait_listen PORT [TIMEOUT_S] -- bounded readiness poll that opens NO
# connection (checks the LISTEN state in /proc/net/tcp). A connect-based
# probe would be counted as a served request by the raw probe servers and
# break their served= gates.
wait_listen() {
  local port=$1 timeout_s=${2:-10} i=0 max hex files
  max=$(( timeout_s * 5 ))
  hex=$(printf '%04X' "$port")
  files="/proc/net/tcp"
  [ -r /proc/net/tcp6 ] && files="$files /proc/net/tcp6"
  while [ "$i" -lt "$max" ]; do
    # shellcheck disable=SC2086
    if awk -v p="$hex" '$4 == "0A" && toupper($2) ~ (":" p "$") { f=1 } END { exit f ? 0 : 1 }' $files 2>/dev/null; then
      return 0
    fi
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

# wait_exit PID TIMEOUT_S -- true (0) once the process is gone.
wait_exit() {
  local pid=$1 timeout_s=${2:-5} i=0 max
  max=$(( timeout_s * 10 ))
  while [ "$i" -lt "$max" ]; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

# kill_tree PID [TIMEOUT_S] -- TERM, wait, KILL. Single-process assumption.
kill_tree() {
  local pid=$1 timeout_s=${2:-5}
  kill -TERM "$pid" 2>/dev/null || true
  wait_exit "$pid" "$timeout_s" || kill -KILL "$pid" 2>/dev/null || true
}

# proc_rss_kb PID -- resident set size in KB (Linux /proc).
proc_rss_kb() {
  local pid=$1
  awk '/VmRSS/ { print $2 }' "/proc/$pid/status" 2>/dev/null
}

# proc_fd_count PID -- open file descriptors (Linux /proc).
proc_fd_count() {
  local pid=$1
  ls "/proc/$pid/fd" 2>/dev/null | wc -l | tr -d ' '
}

# --- HTTP helpers -----------------------------------------------------------
# Scripts set PORT and PULSE_BASE (PULSE_BASE optional).

pulse_base() {
  printf 'http://127.0.0.1:%s' "${PORT:-8080}"
}

# http_get PATH [curl args...]
http_get() {
  local path=$1
  shift
  curl -s -i "$@" "$(pulse_base)$path"
}

# http_stat CODE_FILE CURL [args...] -- status code of a request; body to file.
# (kept simple: scripts use curl -o /dev/null -w '%{http_code}' directly)

# post_json PATH BODY [curl args...] -- POST a JSON string via a body file
# (mirrors the PS 5.1 lesson: never pass JSON as a native argv token).
post_json() {
  local path=$1 body=$2
  shift 2
  local f rc
  f=$(pulse_tmp) || return 1
  printf '%s' "$body" >"$f"
  curl -s -i -X POST -H 'Content-Type: application/json' --data-binary "@$f" \
    "$@" "$(pulse_base)$path"
  rc=$?
  rm -f "$f"
  return $rc
}

# post_empty PATH [curl args...] -- POST with a zero-length body.
post_empty() {
  local path=$1
  shift
  curl -s -i -X POST "$@" "$(pulse_base)$path"
}

# pulse_quit -- asks the PULSE app to shut down (X-Pulse-Quit header).
pulse_quit() {
  curl -s -o /dev/null -H 'X-Pulse-Quit: 1' "$(pulse_base)/health" || true
}

# tcp_probe_quit -- quits either the PULSE app (header) or probe_tcp_server2
# (literal "QUIT" in the request line).
tcp_probe_quit() {
  curl -s -o /dev/null -H 'X-Pulse-Quit: 1' "$(pulse_base)/health?QUIT" || true
}

# --- check counters ---------------------------------------------------------

PULSE_PASS=0
PULSE_FAIL=0

# pulse_check NAME HAYSTACK NEEDLE [WANT=yes]
pulse_check() {
  local name=$1 hay=$2 needle=$3 want=${4:-yes} has=no
  case "$hay" in
    *"$needle"*) has=yes ;;
  esac
  if [ "$has" = "$want" ]; then
    printf '[PASS] %s\n' "$name"
    PULSE_PASS=$((PULSE_PASS + 1))
  else
    printf '[FAIL] %s (want "%s" present=%s)\n' "$name" "$needle" "$want"
    printf -- '---- body ----\n%s\n--------------\n' "$hay"
    PULSE_FAIL=$((PULSE_FAIL + 1))
  fi
}

# pulse_check_eq NAME ACTUAL EXPECTED -- exact numeric/string equality.
pulse_check_eq() {
  local name=$1 actual=$2 expected=$3
  if [ "$actual" = "$expected" ]; then
    printf '[PASS] %s\n' "$name"
    PULSE_PASS=$((PULSE_PASS + 1))
  else
    printf '[FAIL] %s (actual=%s expected=%s)\n' "$name" "$actual" "$expected"
    PULSE_FAIL=$((PULSE_FAIL + 1))
  fi
}

pulse_summary() { # LABEL
  printf '%s: pass=%s fail=%s\n' "$1" "$PULSE_PASS" "$PULSE_FAIL"
}
