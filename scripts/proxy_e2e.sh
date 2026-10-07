#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE through-proxy E2E (Linux/WSL): nginx terminates TLS
# (self-signed) and proxies to PULSE on loopback; verify health, POST
# bodies, metrics and security headers over HTTPS.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/proxy_e2e.sh [--port N] [--proxy-port N]
#                             [--nginx-path PATH] [--server-exe PATH]
# Exit code: 0 = green, 1 = failed.
# Artifacts under probe-logs/proxy-e2e/. Mirrors scripts/proxy_e2e.ps1.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: proxy_e2e.sh [--port N] [--proxy-port N] [--nginx-path PATH]
                    [--server-exe PATH] [--openssl PATH]

  --port N         PULSE upstream port (default 18091)
  --proxy-port N   nginx TLS port (default 8443)
  --nginx-path P   nginx binary or directory (default: nginx on PATH)
  --server-exe P   PULSE binary (default out/pulse_app)
  --openssl P      openssl binary (default: openssl on PATH)
EOF
}

PORT=18091
PROXY_PORT=8443
NGINX_ARG=""
SERVER_EXE="$PULSE_REPO_ROOT/out/pulse_app"
OPENSSL_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT=${2:?missing value}; shift 2 ;;
    --proxy-port) PROXY_PORT=${2:?missing value}; shift 2 ;;
    --nginx-path) NGINX_ARG=${2:?missing value}; shift 2 ;;
    --server-exe) SERVER_EXE=${2:?missing value}; shift 2 ;;
    --openssl) OPENSSL_ARG=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -x "$SERVER_EXE" ] || pulse_die "server not built: $SERVER_EXE"

# --- resolve nginx + openssl ------------------------------------------------
if [ -n "$NGINX_ARG" ]; then
  if [ -d "$NGINX_ARG" ]; then
    NGINX="$NGINX_ARG/nginx"
  else
    NGINX="$NGINX_ARG"
  fi
else
  NGINX=$(command -v nginx || true)
fi
[ -n "$NGINX" ] && [ -x "$NGINX" ] || pulse_die "nginx not found (install nginx or pass --nginx-path)"

if [ -n "$OPENSSL_ARG" ]; then
  OPENSSL="$OPENSSL_ARG"
else
  OPENSSL=$(command -v openssl || true)
fi
[ -n "$OPENSSL" ] && [ -x "$OPENSSL" ] || pulse_die "openssl not found (install openssl or pass --openssl)"

# --- work dirs --------------------------------------------------------------
WORK="$PULSE_REPO_ROOT/probe-logs/proxy-e2e"
CONF_DIR="$WORK/conf"
CERT_DIR="$WORK/cert"
LOGS_DIR="$WORK/logs"
TEMP_ROOT="$WORK/temp"
mkdir -p "$CONF_DIR" "$CERT_DIR" "$LOGS_DIR" \
  "$TEMP_ROOT/client_body_temp" "$TEMP_ROOT/proxy_temp" \
  "$TEMP_ROOT/fastcgi_temp" "$TEMP_ROOT/uwsgi_temp" "$TEMP_ROOT/scgi_temp"

# --- self-signed cert -------------------------------------------------------
CRT="$CERT_DIR/pulse.crt"
KEY="$CERT_DIR/pulse.key"
if [ ! -f "$CRT" ] || [ ! -f "$KEY" ]; then
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CRT" -days 2 \
    -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    >/dev/null 2>&1 || pulse_die "cert generation failed"
fi
pulse_log "proxy-e2e: cert ready ($CRT)"

# --- nginx config -----------------------------------------------------------
# Absolute paths; nginx resolves relative paths against the prefix (-p).
CONF="$CONF_DIR/nginx.conf"
cat >"$CONF" <<EOF
worker_processes 1;
error_log $WORK/logs/error.log;
pid $WORK/logs/nginx.pid;
events { worker_connections 64; }
http {
    access_log $WORK/logs/access.log;
    # Distro nginx binaries default these to /var/lib/nginx/* (root-owned);
    # keep every temp dir under the work prefix so the test runs unprivileged.
    client_body_temp_path $TEMP_ROOT/client_body_temp;
    proxy_temp_path $TEMP_ROOT/proxy_temp;
    fastcgi_temp_path $TEMP_ROOT/fastcgi_temp;
    uwsgi_temp_path $TEMP_ROOT/uwsgi_temp;
    scgi_temp_path $TEMP_ROOT/scgi_temp;
    server {
        listen 127.0.0.1:$PROXY_PORT ssl;
        server_name localhost;
        ssl_certificate $CRT;
        ssl_certificate_key $KEY;
        add_header Strict-Transport-Security "max-age=31536000" always;
        server_tokens off;
        location / {
            proxy_pass http://127.0.0.1:$PORT;
            proxy_http_version 1.1;
            proxy_set_header Connection close;
            proxy_set_header X-Forwarded-For \$remote_addr;
            proxy_read_timeout 10s;
            proxy_send_timeout 10s;
        }
        location /metrics {
            allow 127.0.0.1;
            deny all;
            proxy_pass http://127.0.0.1:$PORT;
        }
    }
}
EOF

# --- start PULSE ------------------------------------------------------------
PULSE_LOG="$WORK/pulse-server.out"
PULSE_PORT="$PORT" "$SERVER_EXE" >"$PULSE_LOG" 2>&1 &
PULSE_PID=$!
if ! wait_listen "$PORT" 10; then
  tail -n 20 "$PULSE_LOG" 2>/dev/null || true
  pulse_die "PULSE did not listen on 127.0.0.1:$PORT"
fi

# --- start nginx (foreground master; file-redirected) ------------------------
NGINX_OUT="$WORK/nginx-stdout.out"
NGINX_ERR="$WORK/nginx-stderr.out"
"$NGINX" -p "$WORK" -c conf/nginx.conf -g 'daemon off;' \
  >"$NGINX_OUT" 2>&1 &
NG_PID=$!

if ! wait_listen "$PROXY_PORT" 10; then
  pulse_log "proxy-e2e: nginx did not start; error log:"
  tail -n 10 "$LOGS_DIR/error.log" 2>/dev/null || true
  pulse_log "proxy-e2e: stderr:"
  tail -n 10 "$NGINX_ERR" 2>/dev/null || true
  kill_tree "$NG_PID" 2
  kill_tree "$PULSE_PID" 2
  exit 1
fi
pulse_log "proxy-e2e: nginx listening on 127.0.0.1:$PROXY_PORT -> $PORT"

BASE="https://127.0.0.1:$PROXY_PORT"

# --- checks over TLS --------------------------------------------------------
R=$(curl -sk -i --max-time 8 "$BASE/health")
pulse_check "tls health 200" "$R" "200 OK"
pulse_check "tls health body" "$R" '{"status":"ok"}'
pulse_check "hsts header" "$R" "Strict-Transport-Security"
pulse_check "proxy server header" "$R" "Server: nginx"
pulse_check "no upstream server leak" "$R" "xiom-pulse" no

BODY_FILE=$(pulse_tmp)
printf '%s' '{"via":"nginx"}' >"$BODY_FILE"
R=$(curl -sk -i --max-time 8 -X POST -H 'Content-Type: application/json' \
  --data-binary "@$BODY_FILE" "$BASE/api/echo")
rm -f "$BODY_FILE"
pulse_check "tls post 200" "$R" "200 OK"
pulse_check "tls post echo" "$R" '{"echo":{"via":"nginx"}}'

R=$(curl -sk -i --max-time 8 "$BASE/metrics")
pulse_check "tls metrics 200" "$R" "200 OK"
pulse_check "tls metrics text" "$R" "pulse_http_requests_total"

R=$(curl -sk -i --max-time 8 "$BASE/nope")
pulse_check "tls 404" "$R" "404 Not Found"
pulse_check "tls 404 rid" "$R" '"rid":"r-'

# --- stop -------------------------------------------------------------------
kill_tree "$NG_PID" 5
pulse_quit
if ! wait_exit "$PULSE_PID" 15; then
  kill_tree "$PULSE_PID" 2
fi
wait "$PULSE_PID" 2>/dev/null
PULSE_EXIT=$?

pulse_log "--- pulse log tail ---"
tail -n 4 "$PULSE_LOG" 2>/dev/null || true
pulse_summary "proxy-e2e"
pulse_log "proxy-e2e: pulse_exit=$PULSE_EXIT"

if [ "$PULSE_FAIL" -eq 0 ] && [ "$PULSE_EXIT" -eq 0 ]; then
  pulse_log "proxy-e2e: GREEN"
  exit 0
fi
pulse_log "proxy-e2e: RED"
exit 1
