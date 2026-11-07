#!/usr/bin/env python3
# ============================================================================
# XIOM PULSE -- live stream-auth smoke (PULSE_WS_AUTH=jwt) for Unix CI.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Unix twin of scripts/ws_auth_smoke.ps1. Starts the product server with
# PULSE_WS_AUTH=jwt and checks the upgrade path end to end:
#   1. WS handshake without a token        -> 401 + WWW-Authenticate: Bearer
#   2. WS handshake with an invalid token  -> 401
#   3. WS handshake with ?token=<jwt>      -> 101 (Sec-WebSocket-Accept)
#   4. SSE without a token                 -> 401
#   5. SSE with ?token=<jwt>               -> 200 text/event-stream + ticks
#   6. access log redacts the token        -> token=REDACTED, raw token absent
#
# Usage: python3 scripts/ws_auth_smoke.py [--exe out/pulse_app] [--port 18303]
# Exit: 0 = all checks pass, 1 = failures, 2 = server start failed.
# ============================================================================

import argparse
import base64
import hashlib
import hmac
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

PASS = 0
FAIL = 0
WS_KEY = "dGhlIHNhbXBsZSBub25jZQ=="
WS_ACCEPT = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print("[PASS] " + name)
    else:
        FAIL += 1
        print("[FAIL] %s (%s)" % (name, detail))


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def mint_jwt(secret):
    header = b64url(
        json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode()
    )
    payload = b64url(
        json.dumps(
            {"sub": "smoke", "exp": int(time.time()) + 300}, separators=(",", ":")
        ).encode()
    )
    signing_input = (header + "." + payload).encode()
    signature = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    return header + "." + payload + "." + signature


def health_once(port, timeout=2.0):
    req = urllib.request.Request(
        "http://127.0.0.1:%d/health" % port, headers={"Connection": "close"}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            resp.read(64)
            return resp.status == 200
    except (urllib.error.URLError, OSError):
        return False


def wait_ready(proc, port, timeout_s=20.0):
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            return False
        if health_once(port):
            return True
        time.sleep(0.1)
    return False


def raw_request(port, request, timeout, marker=None):
    """Send one raw request and return the bytes the server wrote.

    marker=None stops at the end of the headers (401/101 checks);
    marker=b"..." reads the body until the marker or the read timeout.
    """
    sock = socket.create_connection(("127.0.0.1", port), timeout)
    sock.settimeout(timeout)
    data = b""
    try:
        sock.sendall(request.encode("ascii"))
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                break
            data += chunk
            if marker is None and b"\r\n\r\n" in data:
                break
            if marker is not None and marker in data:
                break
    except (socket.timeout, OSError):
        pass
    finally:
        sock.close()
    return data.decode("utf-8", "replace")


def ws_request(port, target):
    return (
        "GET %s HTTP/1.1\r\n"
        "Host: 127.0.0.1:%d\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: %s\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n" % (target, port, WS_KEY)
    )


def sse_request(port, target):
    return (
        "GET %s HTTP/1.1\r\n"
        "Host: 127.0.0.1:%d\r\n"
        "Connection: close\r\n"
        "\r\n" % (target, port)
    )


def status_line(text):
    return text.split("\r\n", 1)[0]


def main(argv=None):
    global PASS, FAIL
    ap = argparse.ArgumentParser(description="PULSE live stream-auth smoke (Unix)")
    ap.add_argument("--exe", default="")
    ap.add_argument("--port", type=int, default=18303)
    ap.add_argument("--secret", default="s3cret")
    ap.add_argument("--timeout", type=float, default=2.5)
    args = ap.parse_args(argv)

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    exe = args.exe
    if not exe:
        exe = os.path.join(repo_root, "out", "pulse_app")
        if os.name == "nt":
            exe += ".exe"
    if not os.path.isabs(exe):
        exe = os.path.join(os.getcwd(), exe)
    if not os.path.exists(exe):
        print("ws-auth-smoke: ERROR missing server binary: %s" % exe)
        return 2

    token = mint_jwt(args.secret)
    workdir = tempfile.mkdtemp(prefix="pulse-wsauth-")
    env = os.environ.copy()
    env["PULSE_PORT"] = str(args.port)
    env["PULSE_BIND"] = "127.0.0.1"
    env["PULSE_LOG"] = "1"
    env["PULSE_WS_AUTH"] = "jwt"
    env["PULSE_JWT_SECRET"] = args.secret
    env["PULSE_STORE_PATH"] = os.path.join(workdir, "events.jsonl")
    env["PULSE_AUDIT_PATH"] = os.path.join(workdir, "audit.log")
    env["PULSE_IDLE_TIMEOUT"] = "2000"
    env["PULSE_RATE_LIMIT"] = "0"
    env["PULSE_RATE_BURST"] = "0"
    env["PULSE_RATE_ROUTES"] = ""
    env.pop("PULSE_STORE_BACKEND", None)

    proc = subprocess.Popen(
        [exe],
        cwd=repo_root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    try:
        if not wait_ready(proc, args.port):
            out = _drain(proc)
            print("ws-auth-smoke: ERROR server did not start on 127.0.0.1:%d"
                  % args.port)
            if out:
                print(out[-4000:])
            return 2

        r1 = raw_request(
            args.port, ws_request(args.port, "/api/ws"), args.timeout
        )
        check("ws no token 401", r1.startswith("HTTP/1.1 401"), status_line(r1))
        check(
            "ws no token challenge",
            "www-authenticate: bearer" in r1.lower(),
            "missing WWW-Authenticate",
        )

        r2 = raw_request(
            args.port,
            ws_request(args.port, "/api/ws?token=not-a-jwt"),
            args.timeout,
        )
        check("ws bad token 401", r2.startswith("HTTP/1.1 401"), status_line(r2))

        r3 = raw_request(
            args.port,
            ws_request(args.port, "/api/ws?token=" + token),
            args.timeout,
        )
        check("ws valid token 101", r3.startswith("HTTP/1.1 101"), status_line(r3))
        check(
            "ws accept header",
            ("Sec-WebSocket-Accept: " + WS_ACCEPT).lower() in r3.lower(),
            "missing accept",
        )

        r4 = raw_request(
            args.port,
            sse_request(args.port, "/api/sse?events=1&interval_ms=0"),
            args.timeout,
        )
        check("sse no token 401", r4.startswith("HTTP/1.1 401"), status_line(r4))

        r5 = raw_request(
            args.port,
            sse_request(
                args.port,
                "/api/sse?events=1&interval_ms=0&token=" + token,
            ),
            args.timeout,
            marker=b"event: tick",
        )
        check("sse valid token 200", r5.startswith("HTTP/1.1 200"), status_line(r5))
        check(
            "sse content type",
            "content-type: text/event-stream" in r5.lower(),
            "missing content type",
        )
        check("sse tick", "event: tick" in r5, "missing tick")
    finally:
        try:
            raw_request(
                args.port,
                "GET / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n"
                "X-Pulse-Quit: 1\r\nConnection: close\r\n\r\n" % args.port,
                2.0,
                marker=b"",
            )
        except OSError:
            pass
        out = _drain(proc)
        if proc.poll() is None:
            proc.terminate()
            try:
                out += _drain(proc)
            except Exception:  # noqa: BLE001 -- best-effort cleanup
                pass

    log = out or ""
    check("log redacts token", "token=REDACTED" in log, "no token=REDACTED line")
    check("log lacks raw token", token not in log, "raw token appears in the log")

    if FAIL == 0:
        print("ws-auth-smoke: GREEN (11/11)")
        return 0
    print("ws-auth-smoke: FAILED=%d" % FAIL)
    return 1


def _drain(proc):
    try:
        out, _ = proc.communicate(timeout=10.0)
        return out or ""
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=5.0)
            return out or ""
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
            return out or ""


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 -- surface unexpected setup failures
        import traceback

        traceback.print_exc()
        sys.exit(2)
