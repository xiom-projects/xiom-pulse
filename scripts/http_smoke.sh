#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE HTTP smoke (Linux/WSL): start the compiled server, exercise
# every route with curl, QUIT, and verify the clean shutdown.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/http_smoke.sh [--port N] [--server-exe PATH]
# Exit code: 0 = all checks green, 1 = failed.
# Mirrors scripts/http_smoke.ps1 (same checks, same counter gates).
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: http_smoke.sh [--port N] [--server-exe PATH]

  --port N         listen port (default 8080)
  --server-exe P   PULSE binary (default out/pulse_app)
EOF
}

PORT=8080
SERVER_EXE="$PULSE_REPO_ROOT/out/pulse_app"
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE (run scripts/build.sh src/server.xi --name pulse_app)"

# --- 0. CLI pre-flight (--version / --check-config) -------------------------
VER_OUT=$("$SERVER_EXE" --version 2>&1)
VER_RC=$?
pulse_check "cli version text" "$VER_OUT" "xiom-pulse"
pulse_check_eq "cli version rc" "$VER_RC" "0"
CFG_OUT=$("$SERVER_EXE" --check-config 2>&1)
CFG_RC=$?
pulse_check "cli check-config text" "$CFG_OUT" "port="
pulse_check_eq "cli check-config rc" "$CFG_RC" "0"
CFG_WARN_OUT=$(PULSE_PORT=abc "$SERVER_EXE" --check-config 2>&1)
CFG_WARN_RC=$?
pulse_check "cli check-config warns" "$CFG_WARN_OUT" "warning:"
pulse_check_eq "cli check-config warn rc" "$CFG_WARN_RC" "0"
OA_OUT=$("$SERVER_EXE" openapi 2>&1)
OA_RC=$?
pulse_check "cli openapi text" "$OA_OUT" "3.1.0"
pulse_check_eq "cli openapi rc" "$OA_RC" "0"
RT_OUT=$("$SERVER_EXE" routes 2>&1)
RT_RC=$?
pulse_check "cli routes text" "$RT_OUT" "GET /health"
pulse_check_eq "cli routes rc" "$RT_RC" "0"
V_OUT=$("$SERVER_EXE" version 2>&1)
V_RC=$?
pulse_check "cli version subcommand" "$V_OUT" "xiom-pulse"
pulse_check_eq "cli version subcommand rc" "$V_RC" "0"
CC_OUT=$("$SERVER_EXE" check-config 2>&1)
CC_RC=$?
pulse_check "cli check-config subcommand" "$CC_OUT" "port="
pulse_check_eq "cli check-config subcommand rc" "$CC_RC" "0"

LOG_DIR="$PULSE_REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
SERVER_LOG="$LOG_DIR/http-smoke.out"

PULSE_CORS_ORIGIN='*' PULSE_PORT="$PORT" PULSE_UPLOAD_DIR="$LOG_DIR/smoke-uploads" "$SERVER_EXE" >"$SERVER_LOG" 2>&1 &
SRV_PID=$!

if ! wait_listen "$PORT" 10; then
  printf -- '---- server log ----\n'
  tail -n 20 "$SERVER_LOG" 2>/dev/null || true
  pulse_die "server did not listen on 127.0.0.1:$PORT"
fi
sleep 0.2

# --- 1. GET /health ---------------------------------------------------------
R=$(http_get /health)
pulse_check "health 200" "$R" "200 OK"
pulse_check "health json" "$R" '{"status":"ok"}'
pulse_check "date header" "$R" "Date: "

# --- 2. GET /api/version ----------------------------------------------------
R=$(http_get /api/version)
pulse_check "version 200" "$R" "200 OK"
pulse_check "version name" "$R" '"name":"xiom-pulse"'
pulse_check "version value" "$R" '"version":"0.2.0"'

# --- 3. POST /api/echo valid ------------------------------------------------
R=$(post_json /api/echo '{"a":1}')
pulse_check "echo 200" "$R" "200 OK"
pulse_check "echo body" "$R" '{"echo":{"a":1}}'

# --- 4. POST /api/echo invalid ----------------------------------------------
R=$(post_json /api/echo 'notjson')
pulse_check "echo invalid 400" "$R" "400 Bad Request"
pulse_check "echo invalid json" "$R" '"code":"invalid_json"'

# --- 4b. Transfer-Encoding: chunked decoded; gzip 501; TE+CL 400 ------------
R=$(post_json /api/echo '{"chunked":1}' -H 'Transfer-Encoding: chunked')
pulse_check "chunked 200" "$R" "200 OK"
pulse_check "chunked echo body" "$R" '{"echo":{"chunked":1}}'
R=$(post_json /api/echo '{"x":1}' -H 'Transfer-Encoding: chunked' -H 'Content-Length: 7')
pulse_check "te+cl rejected 400" "$R" "400 Bad Request"
R=$(post_json /api/echo '{"x":1}' -H 'Transfer-Encoding: gzip')
pulse_check "te gzip rejected 501" "$R" "501 Not Implemented"

# --- 5. 404 -----------------------------------------------------------------
R=$(http_get /nope)
pulse_check "unknown 404" "$R" "404 Not Found"
pulse_check "404 has rid" "$R" '"rid":"r-'
pulse_check "404 error status" "$R" '"status":404'

# --- 6. 405 -----------------------------------------------------------------
R=$(curl -s -i -X DELETE "$(pulse_base)/health")
pulse_check "wrong method 405" "$R" "405 Method Not Allowed"

# --- 7. longer body ---------------------------------------------------------
R=$(post_json /api/echo '{"longer":"payload","n":42}')
pulse_check "echo longer 200" "$R" "200 OK"
pulse_check "echo longer body" "$R" '{"longer":"payload","n":42}'

# --- 7b. Expect: 100-continue (interim answered before the body) ------------
R=$(post_json /api/echo '{"e":1}' -H 'Expect: 100-continue')
pulse_check "expect 100-continue 200" "$R" "200 OK"

# --- 8. router param + metrics ---------------------------------------------
R=$(http_get /api/items/42)
pulse_check "item 200" "$R" "200 OK"
pulse_check "item body" "$R" '{"item":"42"}'
R=$(http_get /metrics)
pulse_check "metrics 200" "$R" "200 OK"
pulse_check "metrics text" "$R" "pulse_http_requests_total"
pulse_check "metrics store gauge" "$R" "pulse_store_records"
pulse_check "metrics app info" "$R" "pulse_app_info"
pulse_check "metrics uptime" "$R" "pulse_uptime_seconds"

# --- 9. cookie sessions -----------------------------------------------------
JAR=$(pulse_tmp)
R=$(post_json /api/session/login '{"user":"carol"}' -b "$JAR" -c "$JAR")
pulse_check "login 200" "$R" "200 OK"
pulse_check "login set-cookie" "$R" "Set-Cookie: sid="
pulse_check "login csrf cookie" "$R" "Set-Cookie: csrf="
pulse_check "login user" "$R" '"user":"carol"'
CSRF=$(printf '%s' "$R" | grep -oE '"csrf":"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)
if [ -n "$CSRF" ]; then
  pulse_check "login csrf body" yes yes
else
  pulse_check "login csrf body" no yes
fi
R=$(http_get /api/me -b "$JAR")
pulse_check "me 200 with cookie" "$R" "200 OK"
pulse_check "me user" "$R" '"user":"carol"'
R=$(http_get /api/me)
pulse_check "me 401 without cookie" "$R" "401 Unauthorized"
R=$(post_empty /api/session/logout -b "$JAR")
pulse_check "logout 403 without csrf" "$R" "403 Forbidden"
R=$(post_empty /api/session/logout -b "$JAR" -H "X-CSRF-Token: $CSRF")
pulse_check "logout 200 with csrf" "$R" "200 OK"
pulse_check "logout clears cookie" "$R" "Max-Age=0"
R=$(http_get /api/me -b "$JAR")
pulse_check "me 401 after logout" "$R" "401 Unauthorized"
rm -f "$JAR"

# --- 10. JWT HS256 issue + verify + tamper ----------------------------------
R=$(post_json /api/token '{"user":"carol"}')
pulse_check "token 200" "$R" "200 OK"
TOK=$(printf '%s' "$R" | grep -oE '"token":"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)
if [ -n "$TOK" ]; then
  pulse_check "token issued" yes yes
  R=$(post_json /api/token/verify "{\"token\":\"$TOK\"}")
  pulse_check "token verify 200" "$R" "200 OK"
  pulse_check "token verify body" "$R" '"ok":true'
  pulse_check "token verify payload" "$R" '"payload":'
  # Append a char: deterministic 401 (replacing the last base64url char is
  # flaky -- trailing padding bits can decode to the same signature bytes).
  TAM="${TOK}x"
  R=$(post_json /api/token/verify "{\"token\":\"$TAM\"}")
  pulse_check "token tamper 401" "$R" "401 Unauthorized"
else
  pulse_check "token issued" no yes
fi

# --- 11. JSONL event store routes -------------------------------------------
R=$(post_json /api/events '{"kind":"smoke","n":1}')
pulse_check "events post 200" "$R" "200 OK"
pulse_check "events post stored" "$R" '"stored":true'
R=$(http_get /api/events/count)
pulse_check "events count 200" "$R" "200 OK"
pulse_check "events count body" "$R" '"count":'
R=$(http_get /api/events)
pulse_check "events list 200" "$R" "200 OK"
pulse_check "events list body" "$R" '"events":'
R=$(http_get "/api/events?limit=1")
pulse_check "events limit 200" "$R" "200 OK"
R=$(http_get "/api/events?kind=smoke")
pulse_check "events kind 200" "$R" "200 OK"
pulse_check "events kind body" "$R" "smoke"

# --- 11b. Pagination: durable seq cursor + RFC 8288 Link header (0.2) -------
R=$(post_json /api/events '{"kind":"page","n":1}')
pulse_check "page event 1 200" "$R" "200 OK"
R=$(post_json /api/events '{"kind":"page","n":2}')
pulse_check "page event 2 200" "$R" "200 OK"
R=$(http_get "/api/events?limit=2")
pulse_check "paginate 200" "$R" "200 OK"
pulse_check "paginate seq field" "$R" '"seq":'
pulse_check "paginate next cursor" "$R" '"next_cursor":'
pulse_check "paginate link next" "$R" 'rel="next"'
pulse_check "paginate link cursor" "$R" "before="
R=$(http_get "/api/events?limit=2&before=1")
pulse_check "paginate before1 empty" "$R" '"events":[]'
pulse_check "paginate before1 no next" "$R" '"next_cursor":0'
R=$(http_get "/api/events?before=xyz")
pulse_check "paginate bad cursor 400" "$R" "400 Bad Request"
pulse_check "paginate bad cursor code" "$R" '"code":"invalid_cursor"'

# --- 11c. Idempotency keys on event writes (0.2) ----------------------------
R1=$(post_json /api/events '{"kind":"idem","n":1}' -H 'Idempotency-Key: smoke-idem-1')
pulse_check "idem first 200" "$R1" "200 OK"
pulse_check "idem first seq" "$R1" '"seq":'
R2=$(post_json /api/events '{"kind":"idem","n":1}' -H 'Idempotency-Key: smoke-idem-1')
pulse_check "idem replay 200" "$R2" "200 OK"
pulse_check "idem replay dedup" "$R2" '"deduplicated":true'
C1=$(printf '%s' "$R1" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2)
C2=$(printf '%s' "$R2" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2)
if [ -n "$C1" ] && [ "$C1" = "$C2" ]; then
  pulse_check "idem replay count stable" yes yes
else
  pulse_check "idem replay count stable" "c1=$C1 c2=$C2" yes
fi
LONGKEY=$(printf 'a%.0s' $(seq 1 201))
R=$(post_json /api/events '{"kind":"idem"}' -H "Idempotency-Key: $LONGKEY")
pulse_check "idem bad key 400" "$R" "400 Bad Request"
pulse_check "idem bad key code" "$R" '"code":"invalid_idempotency_key"'

R=$(post_empty /api/events/compact)
pulse_check "events compact 200" "$R" "200 OK"
pulse_check "events compact ok" "$R" '"ok":true'

# --- 12. app icon + landing page --------------------------------------------
R=$(http_get /favicon.ico)
pulse_check "favicon 200" "$R" "200 OK"
pulse_check "favicon type" "$R" "Content-Type: image/x-icon"
pulse_check "favicon length" "$R" "Content-Length: "
R=$(http_get /)
pulse_check "landing 200" "$R" "200 OK"
pulse_check "landing title" "$R" "XIOM PULSE"
pulse_check "landing html" "$R" "text/html"

# --- 12b. showcase assets (/assets/) ----------------------------------------
ETFILE=$(pulse_tmp)
R=$(curl -s -i --etag-save "$ETFILE" "$(pulse_base)/assets/hello.txt")
pulse_check "assets 200" "$R" "200 OK"
pulse_check "assets type" "$R" "Content-Type: text/plain"
pulse_check "assets body" "$R" "XIOM PULSE static asset demo"
R=$(curl -s -i --etag-compare "$ETFILE" "$(pulse_base)/assets/hello.txt")
pulse_check "assets 304" "$R" "304 Not Modified"
rm -f "$ETFILE"
R=$(curl -s -i --path-as-is "$(pulse_base)/assets/../xiom.toml")
pulse_check "assets traversal 404" "$R" "404 Not Found"

# --- 12c. HEAD + CORS -------------------------------------------------------
R=$(curl -s -I "$(pulse_base)/health")
pulse_check "head 200" "$R" "200 OK"
pulse_check "head content-length" "$R" "Content-Length: 15"
R=$(http_get /health -H 'Origin: http://example.test')
pulse_check "cors allow origin" "$R" "Access-Control-Allow-Origin: *"
R=$(curl -s -i -X OPTIONS -H 'Origin: http://example.test' \
  -H 'Access-Control-Request-Method: POST' "$(pulse_base)/api/events")
pulse_check "cors preflight 204" "$R" "204 No Content"
pulse_check "cors preflight methods" "$R" "Access-Control-Allow-Methods:"

# --- 13b. OpenAPI contract served -------------------------------------------
R=$(http_get /openapi.json)
pulse_check "openapi 200" "$R" "200 OK"
pulse_check "openapi title" "$R" "XIOM PULSE"

# --- 13c. /v1 alias namespace (0.2) -----------------------------------------
R=$(http_get /v1/health)
pulse_check "v1 health 200" "$R" "200 OK"
pulse_check "v1 health json" "$R" '{"status":"ok"}'
R=$(http_get /v1/api/version)
pulse_check "v1 version 200" "$R" "200 OK"
pulse_check "v1 version name" "$R" '"name":"xiom-pulse"'
R=$(http_get "/v1/api/events?limit=1")
pulse_check "v1 events 200" "$R" "200 OK"
R=$(http_get /v1/nope)
pulse_check "v1 unknown 404" "$R" "404 Not Found"

# --- 13d. Multipart upload (0.2) --------------------------------------------
TF=/tmp/pulse-smoke-up.txt
printf 'hello upload' > "$TF"
R=$(curl -s -i -F "file=@$TF;type=text/plain" "$(pulse_base)/api/uploads")
pulse_check "upload 200" "$R" "200 OK"
pulse_check "upload stored" "$R" '"stored":1'
pulse_check "upload original" "$R" '"original":"pulse-smoke-up.txt"'
pulse_check "upload bytes" "$R" '"bytes":12'
R=$(curl -s -i -H "Content-Type: multipart/form-data" --data-binary "nope" "$(pulse_base)/api/uploads")
pulse_check "upload no boundary 415" "$R" "415 Unsupported Media Type"
pulse_check "upload no boundary code" "$R" '"code":"unsupported_media_type"'
rm -f "$TF"

# --- 13. QUIT ---------------------------------------------------------------
pulse_quit
if ! wait_exit "$SRV_PID" 10; then
  pulse_log "smoke: server did not exit after QUIT; killing"
  kill_tree "$SRV_PID" 2
fi
wait "$SRV_PID" 2>/dev/null
SRV_EXIT=$?

pulse_log "--- server log tail ---"
tail -n 8 "$SERVER_LOG" 2>/dev/null || true
pulse_summary "smoke"
pulse_log "smoke: server_exit=$SRV_EXIT"

if [ "$PULSE_FAIL" -eq 0 ] && [ "$SRV_EXIT" -eq 0 ]; then
  pulse_log "smoke: GREEN"
  exit 0
fi
pulse_log "smoke: RED"
exit 1
