#!/usr/bin/env python3
# XIOM PULSE -- request-gate ordering harness (middleware Phase A).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Pins the gate order that the accept-loop ladder implements today, BEFORE
# the nine-stage middleware refactor (docs/DESIGN-MIDDLEWARE-JOBS.md 3.3):
#   1. CSRF 403 beats rate-limit 429 for mutating cookie requests.
#   2. OPTIONS bypasses both CSRF and the rate limiter.
#   3. X-Pulse-Quit is honored only after a well-formed parse.
#   4. Too-large bodies answer 413, malformed requests answer 400.
#   5. A clean quit still exits 0.
#
# The harness starts its OWN server (CSRF + rate limit enabled, isolated
# store/audit dirs) so the main smoke server keeps its config.
#
# Usage: python gate_order.py --server-exe out/pulse_app.exe [--port 18096]
# Exit code: 0 = all checks green, 1 = failed.

import argparse
import http.client
import os
import socket
import subprocess
import sys
import tempfile
import time

PASS = 0
FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        print("[PASS] " + name)
        PASS += 1
    else:
        print("[FAIL] " + name + ((" (" + detail + ")") if detail else ""))
        FAIL += 1


def request(port, method, path, headers=None, body=None, timeout=8):
    hdrs = dict(headers or {})
    hdrs["Connection"] = "close"
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request(method, path, body=body, headers=hdrs)
        resp = conn.getresponse()
        data = resp.read()
        raw_headers = resp.getheaders()
        return resp.status, raw_headers, data
    finally:
        conn.close()


def cookie_header(raw_headers):
    pairs = []
    for name, value in raw_headers:
        if name.lower() == "set-cookie":
            pairs.append(value.split(";")[0].strip())
    return "; ".join(pairs)


def wait_ready(port, timeout=12.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.create_connection(("127.0.0.1", port), 1.0)
            s.close()
            return True
        except OSError:
            time.sleep(0.15)
    return False


def raw_exchange(port, payload, timeout=8.0):
    s = socket.create_connection(("127.0.0.1", port), timeout)
    try:
        s.settimeout(timeout)
        s.sendall(payload)
        chunks = []
        while True:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        s.close()


def status_line(raw):
    if not raw:
        return ""
    return raw.split(b"\r\n", 1)[0].decode("latin1", "replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server-exe", required=True)
    ap.add_argument("--port", type=int, default=18096)
    ap.add_argument("--out-dir", default="")
    args = ap.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    exe = args.server_exe
    if not os.path.isabs(exe):
        exe = os.path.join(repo_root, exe)
    if not os.path.isfile(exe):
        print("gate-order: server exe missing: " + exe)
        return 1

    if args.out_dir:
        run_dir = args.out_dir
        if not os.path.isabs(run_dir):
            run_dir = os.path.join(repo_root, run_dir)
        os.makedirs(run_dir, exist_ok=True)
    else:
        run_dir = tempfile.mkdtemp(prefix="pulse-gate-order-")

    env = dict(os.environ)
    env.update({
        "PULSE_PORT": str(args.port),
        "PULSE_CSRF": "1",
        "PULSE_RATE_LIMIT": "1",
        "PULSE_RATE_BURST": "1",
        "PULSE_CORS_ORIGIN": "*",
        "PULSE_READ_TIMEOUT": "4000",
        "PULSE_WRITE_TIMEOUT": "4000",
        "PULSE_IDLE_TIMEOUT": "2000",
        "PULSE_STORE_PATH": os.path.join(run_dir, "store.jsonl"),
        "PULSE_AUDIT_PATH": os.path.join(run_dir, "audit.log"),
        "PULSE_UPLOAD_DIR": os.path.join(run_dir, "uploads"),
    })
    log_path = os.path.join(run_dir, "server.out")
    log = open(log_path, "wb")
    proc = subprocess.Popen([exe], cwd=repo_root, env=env,
                            stdout=log, stderr=subprocess.STDOUT)
    try:
        if not wait_ready(args.port):
            check("gate server ready", False, "no listener on %d" % args.port)
            return 1
        check("gate server ready", True)

        # Login establishes the session + csrf cookies; the login itself
        # consumes the single burst token.
        status, hdrs, body = request(
            args.port, "POST", "/api/session/login",
            {"Content-Type": "application/json"}, b'{"user":"gate"}')
        cookies = cookie_header(hdrs)
        check("gate login 200", status == 200, "status=%d" % status)
        check("gate login cookies", "csrf=" in cookies and "sid=" in cookies,
              cookies)

        # 413 vs 400: a body over the 1 MiB cap answers payload_too_large;
        # a malformed request line answers bad_request (checked below).
        time.sleep(1.1)
        big = b"x" * (1048576 + 24)
        status, _, body = request(
            args.port, "POST", "/api/echo",
            {"Content-Type": "application/octet-stream"}, big)
        text = body.decode("latin1", "replace")
        check("gate 413 too large",
              status == 413 and "payload_too_large" in text,
              "status=%d body=%s" % (status, text[:80]))

        # CSRF 403 must beat rate-limit 429: empty the bucket with two
        # back-to-back GETs, then send the mutating cookie request BEFORE
        # the next refill. Retry when a refill slips between the calls.
        precedence = False
        rate_active = False
        for _attempt in range(4):
            time.sleep(1.1)  # refill one token
            s1, _, _ = request(args.port, "GET", "/health")
            s2, _, _ = request(args.port, "GET", "/health")
            s3, _, _ = request(
                args.port, "POST", "/api/events",
                {"Content-Type": "application/json", "Cookie": cookies},
                b'{"kind":"gate","n":1}')
            if s1 == 200 and s2 == 429:
                rate_active = True
                if s3 == 403:
                    precedence = True
                    break
            if s3 == 403 and s2 != 429:
                # CSRF ran, but the limiter was not provably exhausted.
                continue
        check("gate rate limiter active", rate_active)
        check("gate csrf before rate", precedence)

        # OPTIONS preflight must bypass CSRF and the limiter even when the
        # bucket is empty (204, not 403/429).
        options_ok = False
        for _attempt in range(4):
            time.sleep(1.1)
            s1, _, _ = request(args.port, "GET", "/health")
            s2, _, _ = request(args.port, "GET", "/health")
            s3, _, _ = request(
                args.port, "OPTIONS", "/api/events",
                {"Origin": "http://example.com",
                 "Access-Control-Request-Method": "POST",
                 "Cookie": cookies})
            if s1 == 200 and s2 == 429 and s3 == 204:
                options_ok = True
                break
        check("gate options bypasses csrf+rate", options_ok)

        # Quit is honored only after a well-formed parse: a malformed head
        # carrying the quit header gets 400 and the loop stays alive.
        time.sleep(1.1)
        raw = raw_exchange(
            args.port, b"BAD\r\nX-Pulse-Quit: 1\r\nHost: gate\r\n\r\n")
        check("gate malformed quit gets 400",
              "400" in status_line(raw), status_line(raw))
        time.sleep(1.1)
        status, _, _ = request(args.port, "GET", "/health")
        check("gate loop alive after malformed quit", status == 200,
              "status=%d" % status)

        # A well-formed quit stops the loop cleanly. The current contract is
        # a silent close (no response bytes), so a disconnect is expected.
        quit_closed = False
        try:
            request(args.port, "GET", "/health", {"X-Pulse-Quit": "1"})
        except (http.client.RemoteDisconnected, ConnectionResetError):
            quit_closed = True
        check("gate quit closes connection", quit_closed)
        exited = True
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            exited = False
        check("gate clean exit", exited and proc.returncode == 0,
              "exited=%s rc=%s" % (exited, proc.returncode))
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        log.close()

    print("gate-order: pass=%d fail=%d log=%s" % (PASS, FAIL, log_path))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
