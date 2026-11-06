#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE -- dynamic site scaffold smoke (Unix).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds examples/site/main.xi, starts it on a local port, and checks the
# server-rendered pages, the urlencoded form (success + validation), assets,
# the custom 404 and the traversal guard. Exit code = failures (0 = green).
# Usage: bash scripts/site_smoke.sh [--port 18095]
# ============================================================================
set -euo pipefail

PORT=18095
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

expect() {
  local name="$1"; shift
  if "$@"; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name"
    fail=$((fail + 1))
  fi
}

bash scripts/build.sh examples/site/main.xi --name site_example --timeout-sec 300 >/dev/null

PULSE_PORT="$PORT" PULSE_LOG=0 SITE_ROOT=examples/site ./out/site_example &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

ready=0
i=0
while [ "$i" -lt 60 ]; do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ready=1; break; fi
  sleep 0.2
  i=$((i + 1))
done
[ "$ready" -eq 1 ] || { echo "site server did not become ready on port $PORT" >&2; exit 1; }

tmp="$(mktemp)"
status() { curl -s -o "$tmp" -w '%{http_code}' "$1"; }
status_ctype() { curl -s -o /dev/null -w '%{http_code} %{content_type}' "$1"; }
post_status() { curl -s -o "$tmp" -w '%{http_code}' -X POST -H "Content-Type: $1" --data "$2" "http://127.0.0.1:$PORT$3"; }

s=$(status "http://127.0.0.1:$PORT/")
expect "home 200" [ "$s" = "200" ]
grep -q "PULSE site example" "$tmp"
expect "home layout" grep -q 'class="bar"' "$tmp"
expect "home footer" grep -q 'class="foot"' "$tmp"

s=$(status "http://127.0.0.1:$PORT/about")
expect "about 200" [ "$s" = "200" ]
expect "about copy" grep -q "About this site" "$tmp"

s=$(status "http://127.0.0.1:$PORT/features")
expect "features loop" grep -q "application/x-www-form-urlencoded form parsing" "$tmp"

s=$(status "http://127.0.0.1:$PORT/contact")
expect "contact form" grep -q '<form method="post" action="/contact">' "$tmp"

s=$(post_status "application/x-www-form-urlencoded" "name=Ada+Lovelace&message=Hello+%26+welcome%21+%3Cb%3E" "/contact")
expect "form success 200" [ "$s" = "200" ]
expect "form reflected name" grep -q "Thanks, Ada Lovelace." "$tmp"
expect "form escaped value" grep -q "Hello &amp; welcome! &lt;b&gt;" "$tmp"

s=$(post_status "application/x-www-form-urlencoded" "message=only" "/contact")
expect "form validation 400" [ "$s" = "400" ]
expect "form validation message" grep -q "Name is required." "$tmp"

s=$(post_status "application/json" "{}" "/contact")
expect "form wrong content-type 415" [ "$s" = "415" ]

out=$(status_ctype "http://127.0.0.1:$PORT/assets/style.css")
expect "asset css 200 text/css" [ "$out" = "200 text/css" ]

s=$(status "http://127.0.0.1:$PORT/nope")
expect "custom 404 status" [ "$s" = "404" ]
expect "custom 404 copy" grep -q "Page not found" "$tmp"
expect "custom 404 path" grep -q "/nope" "$tmp"

out=$(curl --path-as-is -s -o /dev/null -w '%{http_code} %{content_type}' "http://127.0.0.1:$PORT/assets/../main.xi")
case "$out" in
  200*) echo "[FAIL] asset traversal blocked"; fail=$((fail + 1)) ;;
  *) echo "[PASS] asset traversal blocked" ;;
esac

rm -f "$tmp"

if [ "$fail" -eq 0 ]; then
  echo "site-smoke: GREEN"
  exit 0
fi
echo "site-smoke: RED failures=$fail"
exit 1
