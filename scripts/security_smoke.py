#!/usr/bin/env python3
# XIOM PULSE -- raw HTTP security smoke engine (framing / traversal / uploads).
# Copyright (c) 2026 Eleftheros Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Deterministic raw-socket corpus used by scripts/framing_smoke.*,
# scripts/static_traversal_smoke.* and scripts/upload_security_smoke.*.
# The wrappers build a uniquely named server binary and pass --server-exe.
#
# Exit codes: 0 = every enforced check passed (gaps allowed only with
# --allow-known-gaps); 1 = a hard check failed; 2 = harness/server startup
# error. Findings are printed with [FAIL]/[GAP]/[KNOWN]/[SKIP] and never
# weakened to make the run green.

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_BODY = 1048576
REJECT_STATUSES = set([400, 408, 411, 413, 414, 431, 501, 505])
REL_NUL = "REL-20261106-1716-pulse"


class Result(object):
    def __init__(self):
        self.pass_n = 0
        self.fail_n = 0
        self.gap_n = 0
        self.known_n = 0
        self.skip_n = 0
        self.info_n = 0
        self.findings = []

    def _emit(self, tag, name, detail):
        line = "[%s] %s" % (tag, name)
        if detail:
            line += " -- " + detail
        print(line)
        sys.stdout.flush()

    def check(self, name, ok, detail=""):
        if ok:
            self.pass_n += 1
            self._emit("PASS", name, detail)
            return True
        self.fail_n += 1
        self._emit("FAIL", name, detail)
        return False

    def gap(self, name, detail="", severity="MEDIUM", finding=""):
        self.gap_n += 1
        self.findings.append((severity, name, detail))
        self._emit("GAP:%s" % severity, name, detail)
        if finding:
            print("       finding: " + finding)
            sys.stdout.flush()
        return False

    def known(self, name, detail=""):
        self.known_n += 1
        self._emit("KNOWN", name, detail)
        return True

    def skip(self, name, detail=""):
        self.skip_n += 1
        self._emit("SKIP", name, detail)
        return True

    def info(self, name, detail=""):
        self.info_n += 1
        self._emit("INFO", name, detail)
        return True

    def summary(self, label):
        print("%s: pass=%d fail=%d gap=%d known=%d skip=%d info=%d" % (
            label, self.pass_n, self.fail_n, self.gap_n, self.known_n, self.skip_n, self.info_n))
        if self.findings:
            print("%s: reported gaps (not fixed by this test):" % label)
            for severity, name, detail in self.findings:
                print("  - %s %s: %s" % (severity, name, detail))
        sys.stdout.flush()


# ---------------------------------------------------------------------------
# HTTP/1.1 raw client
# ---------------------------------------------------------------------------

def parse_response(data):
    status = 0
    reason = ""
    headers = []
    body = b""
    if not data:
        return status, reason, headers, body
    head, sep, body = data.partition(b"\r\n\r\n")
    if not sep:
        body = b""
    lines = head.split(b"\r\n")
    if lines:
        m = re.match(br"HTTP/\d\.\d\s+(\d{3})\s*(.*)", lines[0])
        if m:
            status = int(m.group(1))
            reason = m.group(2).decode("latin1", "replace")
    for line in lines[1:]:
        if b":" in line:
            n, v = line.split(b":", 1)
            headers.append((n.strip().lower(), v.strip()))
    return status, reason, headers, body


def header_get(headers, name):
    name = name.lower().encode("latin1")
    for n, v in headers:
        if n == name:
            return v.decode("latin1", "replace")
    return ""


def raw_request(port, payload, timeout=3.0, shutdown=True, read_limit=8 * 1024 * 1024):
    out = {
        "status": 0, "reason": "", "headers": [], "body": b"", "raw": b"",
        "closed": False, "error": "", "sent": False,
    }
    s = None
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout)
        s.settimeout(timeout)
        try:
            s.sendall(payload)
            out["sent"] = True
        except (BrokenPipeError, ConnectionResetError, OSError) as e:
            out["error"] = "send: " + repr(e)
        if shutdown:
            try:
                s.shutdown(socket.SHUT_WR)
            except OSError:
                pass
        data = b""
        try:
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    out["closed"] = True
                    break
                data += chunk
                if len(data) > read_limit:
                    break
        except socket.timeout:
            pass
        except (ConnectionResetError, OSError) as e:
            out["error"] = (out["error"] + " recv: " + repr(e)).strip()
        out["raw"] = data
        out["status"], out["reason"], out["headers"], out["body"] = parse_response(data)
    except Exception as e:
        out["error"] = "connect: " + repr(e)
    finally:
        if s is not None:
            try:
                s.close()
            except Exception:
                pass
    return out


def http_get(port, path, timeout=3.0):
    if isinstance(path, str):
        path = path.encode("latin1")
    req = b"GET " + path + b" HTTP/1.1\r\nHost: smoke\r\nConnection: close\r\n\r\n"
    return raw_request(port, req, timeout)


def multipart_body(boundary, parts):
    b = boundary.encode("latin1")
    out = b""
    for p in parts:
        out += b"--" + b + b"\r\n"
        out += b'Content-Disposition: form-data; name="' + p.get("name", "file").encode("latin1") + b'"'
        if p.get("filename") is not None:
            out += b'; filename="' + p["filename"].encode("latin1", "replace") + b'"'
        out += b"\r\n"
        if p.get("content_type") is not None:
            out += b"Content-Type: " + p["content_type"].encode("latin1") + b"\r\n"
        for hn, hv in p.get("headers", []):
            out += hn.encode("latin1") + b": " + hv.encode("latin1") + b"\r\n"
        out += b"\r\n" + p.get("content", b"") + b"\r\n"
    out += b"--" + b + b"--\r\n"
    return out


def multipart_post(port, body, boundary, timeout=8.0):
    req = (b"POST /api/uploads HTTP/1.1\r\nHost: smoke\r\n"
           b"Content-Type: multipart/form-data; boundary=" + boundary.encode("latin1") + b"\r\n"
           b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n"
           b"Connection: close\r\n\r\n" + body)
    return raw_request(port, req, timeout)


# ---------------------------------------------------------------------------
# Server lifecycle
# ---------------------------------------------------------------------------

def server_alive(port, timeout=2.0):
    r = http_get(port, "/health", timeout)
    return r["status"] == 200 and b'"status":"ok"' in r["body"]


def wait_ready(port, proc, out_path, err_path, timeout=15.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False, "server exited rc=%s" % proc.returncode
        if server_alive(port, 0.5):
            return True, ""
        time.sleep(0.1)
    return False, "server did not become ready on port %d" % port


def read_logs(out_path, err_path, limit=4000):
    text = ""
    for p in (out_path, err_path):
        try:
            with open(p, "rb") as f:
                text += f.read(limit).decode("utf-8", "replace")
        except Exception:
            pass
    return text


def start_server(exe, port, extra_env, tag):
    if not os.path.isabs(exe):
        exe = os.path.join(REPO_ROOT, exe)
    if not os.path.exists(exe):
        raise SystemExit("security-smoke: server binary not found: " + exe)
    base = tempfile.mkdtemp(prefix="pulse-%s-" % tag)
    logs = os.path.join(base, "logs")
    os.makedirs(logs)
    out_path = os.path.join(base, "server.out")
    err_path = os.path.join(base, "server.err")
    out_f = open(out_path, "wb")
    err_f = open(err_path, "wb")
    env = os.environ.copy()
    env.update({
        "PULSE_PORT": str(port),
        "PULSE_BIND": "127.0.0.1",
        "PULSE_LOG": "0",
        "PULSE_STORE_PATH": os.path.join(logs, "events.jsonl"),
        "PULSE_AUDIT_PATH": os.path.join(logs, "audit.log"),
        "PULSE_STORE_SYNC": "0",
        "PULSE_AUDIT_SYNC": "0",
        "PULSE_READ_TIMEOUT": "3000",
        "PULSE_WRITE_TIMEOUT": "3000",
        "PULSE_IDLE_TIMEOUT": "1000",
        "PULSE_RATE_LIMIT": "0",
        "PULSE_CSRF": "0",
        "PULSE_CORS_ORIGIN": "",
        "PULSE_ICON_PATH": os.path.join(REPO_ROOT, "resources", "img", "pulse-ico.ico"),
        "PULSE_STATIC_DIR": os.path.join(REPO_ROOT, "resources", "img"),
        "PULSE_OPENAPI_PATH": os.path.join(REPO_ROOT, "resources", "openapi.json"),
        "PULSE_ASSETS_DIR": os.path.join(REPO_ROOT, "resources", "public"),
        "PULSE_GAME_PATH": os.path.join(logs, "game.jsonl"),
        "PULSE_GAME_CONFIG_PATH": os.path.join(logs, "game-config.json"),
    })
    env.update(extra_env)
    try:
        proc = subprocess.Popen([exe], cwd=REPO_ROOT, env=env, stdout=out_f, stderr=err_f)
    except Exception as e:
        out_f.close()
        err_f.close()
        shutil.rmtree(base, ignore_errors=True)
        raise SystemExit("security-smoke: cannot start server: " + repr(e))
    ok, why = wait_ready(port, proc, out_path, err_path)
    if not ok:
        print("[FAIL] server startup: " + why)
        print("---- server output ----")
        print(read_logs(out_path, err_path))
        print("-----------------------")
        stop_server(proc, port, out_f, err_f, base, keep=False)
        raise SystemExit(2)
    return {
        "proc": proc, "port": port, "base": base, "logs": logs,
        "out": out_path, "err": err_path, "out_f": out_f, "err_f": err_f,
    }


def stop_server(proc, port, out_f, err_f, base, keep=False):
    if proc.poll() is None:
        try:
            req = b"GET /health HTTP/1.1\r\nHost: smoke\r\nX-Pulse-Quit: 1\r\nConnection: close\r\n\r\n"
            raw_request(port, req, 2.0)
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except Exception:
            try:
                proc.terminate()
            except Exception:
                pass
            try:
                proc.wait(timeout=3)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
    try:
        out_f.close()
        err_f.close()
    except Exception:
        pass
    if keep:
        print("security-smoke: kept temp dir " + base)
    else:
        shutil.rmtree(base, ignore_errors=True)


def finish(ctx, result, label, allow_gaps):
    if result.fail_n > 0:
        rc = 1
    elif result.gap_n > 0 and not allow_gaps:
        rc = 1
    else:
        rc = 0
    result.summary(label)
    return rc


# ---------------------------------------------------------------------------
# Framing corpus
# ---------------------------------------------------------------------------

def framing_cases():
    # Each tuple: (name, raw bytes, expectation, note, gap_id, severity)
    # expectation:
    #   reject       -> 400/4xx-reject/501 or a closed connection with no response
    #   accept       -> 200 (a valid framing shape)
    #   known_nul    -> accepted NUL-in-head (REL-20261106-1716-pulse)
    #   alive        -> must not kill/quit the server; status may be 200 or reject
    return [
        ("dup-cl-same", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\nContent-Length: 7\r\nConnection: close\r\n\r\n{"a":1}',
         "reject", "two identical Content-Length fields (CL.CL)", "CL-CL", "HIGH"),
        ("dup-cl-conflict", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\nContent-Length: 8\r\nConnection: close\r\n\r\n{"a":1}',
         "reject", "two conflicting Content-Length fields (CL.CL)", "CL-CL", "HIGH"),
        ("comma-content-length", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7, 7\r\nConnection: close\r\n\r\n{"a":1}',
         "reject", "comma-separated Content-Length", "", ""),
        ("cl-overflow", b'GET /health HTTP/1.1\r\nHost: t\r\nContent-Length: 999999999999999999999\r\nConnection: close\r\n\r\n',
         "reject", "unrepresentable Content-Length", "CL-OVERFLOW", "HIGH"),
        ("cl-signed", b'GET /health HTTP/1.1\r\nHost: t\r\nContent-Length: +0\r\nConnection: close\r\n\r\n',
         "reject", "signed Content-Length", "CL-SYNTAX", "LOW"),
        ("cl-space-colon", b'GET /health HTTP/1.1\r\nHost: t\r\nContent-Length : 7\r\nConnection: close\r\n\r\n{"a":1}',
         "reject", "whitespace before Content-Length colon", "CL-OBFUSCATED", "HIGH"),
        ("te-cl", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nContent-Length: 7\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\n\r\n',
         "reject", "TE and CL together (TE.CL)", "", ""),
        ("te-comma-chunked", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked, chunked\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\n\r\n',
         "reject", "comma-separated chunked codings (501 reject is acceptable)", "", ""),
        ("te-comma-gzip", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: gzip, chunked\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\n\r\n',
         "reject", "unimplemented comma codings (501 reject is acceptable)", "", ""),
        ("te-dup-chunked-identity", b'GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: identity\r\nConnection: close\r\n\r\n1\r\nx\r\n0\r\n\r\n',
         "reject", "duplicate TE where the first is chunked (TE.TE)", "TE-TE", "HIGH"),
        ("te-dup-identity-chunked", b'GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: identity\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n1\r\nx\r\n0\r\n\r\n',
         "reject", "duplicate TE where the second is chunked (TE.TE)", "", ""),
        ("te-space-colon", b'GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding : chunked\r\nConnection: close\r\n\r\n1\r\nx\r\n0\r\n\r\n',
         "reject", "whitespace before Transfer-Encoding colon", "TE-OBFUSCATED", "HIGH"),
        ("te-obs-fold", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n chunked\r\nConnection: close\r\n\r\n0\r\n\r\n',
         "reject", "obs-folded Transfer-Encoding", "", ""),
        ("te-unknown-coding", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: xchunked\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\n\r\n',
         "reject", "unknown transfer-coding", "", ""),
        ("te-case-chunked", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: Chunked\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\n\r\n',
         "accept", "case-insensitive chunked", "", ""),
        ("te-ows-chunked", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding:   chunked \r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\n\r\n',
         "accept", "OWS-padded chunked", "", ""),
        ("obs-fold-generic", b'GET /health HTTP/1.1\r\nHost: t\r\nX-Test: a\r\n b\r\nConnection: close\r\n\r\n',
         "reject", "obs-folded generic header", "", ""),
        ("bare-lf", b'GET /health HTTP/1.1\nHost: t\n\n',
         "reject", "bare-LF request head", "", ""),
        ("bare-lf-mixed", b'GET /health HTTP/1.1\r\nHost: t\n\n',
         "reject", "mixed CRLF/LF head", "", ""),
        ("nul-method", b'GE\x00T /health HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n',
         "known_nul", "NUL truncates method to GE", "", ""),
        ("nul-target", b'GET /hea\x00lth HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n',
         "known_nul", "NUL truncates target to /hea", "", ""),
        ("nul-header-value", b'GET /health HTTP/1.1\r\nHost: t\r\nX-A: a\x00b\r\nConnection: close\r\n\r\n',
         "known_nul", "NUL truncates a header value", "", ""),
        ("nul-header-name", b'GET /health HTTP/1.1\r\nHo\x00st: t\r\nConnection: close\r\n\r\n',
         "known_nul", "NUL truncates a header name", "", ""),
        ("nul-cl-hide", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 0\x00junk\r\nConnection: close\r\n\r\n{"a":1}',
         "known_nul", "NUL hides trailing bytes in Content-Length", "NUL-FRAMING", "HIGH"),
        ("nul-empty-method", b'\x00OST /health HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n',
         "reject", "NUL empties the method (Station guard)", "", ""),
        ("chunk-overflow", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\nFFFFFFFFFFFFFFFF\r\n',
         "reject", "chunk size 2^64-1", "", ""),
        ("chunk-overflow-signed", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n7FFFFFFFFFFFFFFF\r\nAAAAAAAA\r\n',
         "reject", "chunk size 2^63-1", "", ""),
        ("chunk-negative", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n-5\r\n',
         "reject", "negative chunk size", "", ""),
        ("chunk-bad-hex", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\nzz\r\n',
         "reject", "non-hex chunk size", "", ""),
        ("trailer-quit", b'GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n1\r\nx\r\n0\r\nX-Pulse-Quit: 1\r\n\r\n',
         "alive", "trailer X-Pulse-Quit must not be a request header", "", ""),
        ("trailer-content-length", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\nContent-Length: 999\r\n\r\n',
         "alive", "trailer Content-Length must not affect framing", "", ""),
        ("trailer-transfer-encoding", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n7\r\n{"a":1}\r\n0\r\nTransfer-Encoding: chunked\r\n\r\n',
         "alive", "trailer Transfer-Encoding must not affect framing", "", ""),
        ("space-before-colon", b'GET /health HTTP/1.1\r\nHost: t\r\nX-Test : v\r\nConnection: close\r\n\r\n',
         "reject", "whitespace before a generic header colon", "HEADER-SYNTAX", "LOW"),
        ("header-no-colon", b'GET /health HTTP/1.1\r\nHost: t\r\nBrokenHeader\r\nConnection: close\r\n\r\n',
         "reject", "header line without a colon", "", ""),
        ("request-line-extra", b'GET /health HTTP/1.1 extra\r\nHost: t\r\nConnection: close\r\n\r\n',
         "reject", "extra request-line token", "REQ-LINE", "LOW"),
        ("header-leading-space", b'GET /health HTTP/1.1\r\nHost: t\r\n X-Fold: v\r\nConnection: close\r\n\r\n',
         "reject", "leading-space header line (obs-fold)", "HEADER-SYNTAX", "LOW"),
        ("cl-body-short", b'POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 10\r\nConnection: close\r\n\r\nhello',
         "reject", "body shorter than Content-Length", "", ""),
    ]


def nul_accepted(resp):
    if resp["status"] in (200, 201, 204, 301, 302, 404, 405):
        return True
    if resp["status"] == 400 and b'"code":"invalid_json"' in resp["body"]:
        return True
    return False


def run_framing(args, result):
    print("framing-smoke: server=" + os.path.abspath(args.server_exe) + " port=" + str(args.port))
    ctx = start_server(args.server_exe, args.port, {}, "framing")
    try:
        for name, payload, expect, note, gap_id, severity in framing_cases():
            resp = raw_request(args.port, payload, args.timeout)
            status = resp["status"]
            closed = resp["closed"]
            detail = "status=%s closed=%s body=%r" % (status if status else "none", closed, resp["body"][:120])
            if note:
                detail = note + "; " + detail
            if expect == "reject":
                rejected = (status in REJECT_STATUSES) or (status == 0 and closed)
                if rejected:
                    result.check(name + " rejected", True, detail)
                elif gap_id:
                    result.gap(name + " rejected", detail, severity,
                               "ambiguous framing accepted; upstream parser/gate hardening needed")
                else:
                    result.check(name + " rejected", False, detail)
            elif expect == "accept":
                result.check(name + " accepted", status == 200, detail)
            elif expect == "known_nul":
                if nul_accepted(resp):
                    if args.strict_nul:
                        result.check(name + " rejected (strict NUL)", False, detail)
                    else:
                        result.known(name + " accepted (KNOWN)", REL_NUL + ": " + detail)
                else:
                    result.check(name + " rejected/closed (NUL)", True, detail)
            elif expect == "alive":
                alive = server_alive(args.port, args.timeout)
                result.check(name + " did not affect the loop", alive, detail)
                if status == 200:
                    result.info(name + " trailers ignored",
                                "status=200; framing trailer fields are ignored, not rejected (RFC 9112 permits ignoring)")
            if status == 0 and not closed:
                result.check(name + " connection did not hang", False, detail)
            elif not closed:
                result.check(name + " connection closed", False, detail)
            if not server_alive(args.port, args.timeout):
                result.check(name + " server alive after", False, "server stopped responding")
                print("---- server output ----")
                print(read_logs(ctx["out"], ctx["err"]))
                print("-----------------------")
                return finish(ctx, result, "framing-smoke", args.allow_known_gaps)
        return finish(ctx, result, "framing-smoke", args.allow_known_gaps)
    finally:
        stop_server(ctx["proc"], ctx["port"], ctx["out_f"], ctx["err_f"], ctx["base"], args.keep)


# ---------------------------------------------------------------------------
# Static / canonical traversal
# ---------------------------------------------------------------------------

TRAVERSAL_PATHS = [
    b"/../../outside-secret.txt",
    b"/../outside-secret.txt",
    b"/%2e%2e/outside-secret.txt",
    b"/%2E%2E%2Foutside-secret.txt",
    b"/..%2foutside-secret.txt",
    b"/..%5coutside-secret.txt",
    b"/%2e%2e%5coutside-secret.txt",
    b"/sub/../../outside-secret.txt",
    b"/..\\outside-secret.txt",
    b"/%5c..%5coutside-secret.txt",
    b"/%00outside-secret.txt",
    b"/inside.txt%00.txt",
    b"/link-out/../outside-secret.txt",
    b"/link-out/%2e%2e/outside-secret.txt",
    b"//outside-secret.txt",
    b"/assets/../outside-secret.txt",
    b"/assets/%2e%2e/outside-secret.txt",
    b"/assets/%5c..%5coutside-secret.txt",
    b"/assets/..%5coutside-secret.txt",
    b"/%252e%252e/outside-secret.txt",
    b"/./outside-secret.txt",
    b"/sub/..%2f..%2foutside-secret.txt",
    b"/index.html/../../outside-secret.txt",
    b"..%2f..%2foutside-secret.txt",
    b"/C:%5coutside-secret.txt",
    b"/%c0%ae%c0%ae/outside-secret.txt",
    b"/%2e%2e%2f%2e%2e%2foutside-secret.txt",
    b"/sub/%2e%2e/%2e%2e/outside-secret.txt",
    b"/sub/..%5c..%5coutside-secret.txt",
    b"/assets/../../outside-secret.txt",
    b"/assets/%2e%2e%2foutside-secret.txt",
    b"/assets/%2e%2e%5coutside-secret.txt",
    b"/assets/..%2foutside-secret.txt",
    b"/assets/%252e%252e/outside-secret.txt",
    b"/assets/%00x",
    b"/assets/%2e%2e/",
    b"/%2e%2e/",
]

UPLOAD_TRAVERSAL_FILENAMES = [
    ("dotdot", "../../escape-a.txt"),
    ("backslash", "..\\..\\escape-b.txt"),
    ("unix-abs", "/etc/passwd"),
    ("win-abs", "C:\\Windows\\win.ini"),
    ("encoded", "%2e%2e%2fescape-e.txt"),
    ("nul", "evil\x00.txt"),
    ("crlf", "evil\r\nX-Injected: 1\r\n.txt"),
    ("dots", "....//escape-f.txt"),
    ("double-encoded", "..%252f..%252fescape-g.txt"),
    ("nested", "foo/../../escape-h.php"),
    ("unc", "\\\\server\\share\\escape-i.txt"),
]


def mk_site(base):
    site = os.path.join(base, "site")
    outside = os.path.join(base, "outside")
    uploads = os.path.join(base, "uploads")
    os.makedirs(os.path.join(site, "sub"))
    os.makedirs(os.path.join(site, "assets"))
    os.makedirs(outside)
    os.makedirs(uploads)
    canary = "OUTSIDE-CANARY-7f3a9c"
    with open(os.path.join(site, "index.html"), "w") as f:
        f.write("<h1>site home</h1>\n")
    with open(os.path.join(site, "about.html"), "w") as f:
        f.write("<h1>about</h1>\n")
    with open(os.path.join(site, "sub", "index.html"), "w") as f:
        f.write("<h1>sub home</h1>\n")
    with open(os.path.join(site, "assets", "style.css"), "w") as f:
        f.write("body{color:#000}\n")
    with open(os.path.join(site, "inside.txt"), "w") as f:
        f.write("INSIDE-OK\n")
    with open(os.path.join(outside, "outside-secret.txt"), "w") as f:
        f.write(canary + "\n")
    return site, outside, uploads, canary


def try_symlink(target, link, is_dir):
    try:
        os.symlink(target, link, target_is_directory=is_dir)
        return True, ""
    except (OSError, NotImplementedError, AttributeError) as e:
        return False, str(e)


def try_junction(target, link):
    if os.name != "nt":
        return False, "not windows"
    try:
        r = subprocess.run(["cmd", "/c", "mklink", "/J", link, target],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = r.stdout.decode("utf-8", "replace").strip()
        return r.returncode == 0 and os.path.isdir(link), out
    except Exception as e:
        return False, repr(e)


def walk_files(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        for f in filenames:
            out.append(os.path.join(dirpath, f))
    return out


def file_contains(path, needle):
    try:
        with open(path, "rb") as f:
            return needle.encode("latin1") in f.read()
    except Exception:
        return False


def run_static(args, result):
    base = tempfile.mkdtemp(prefix="pulse-static-fixtures-")
    site, outside, uploads, canary = mk_site(base)
    link_mode = ""
    link_reason = ""
    # Native symlinks first (the audit's exact case).
    ok_file, why_file = try_symlink(os.path.join(outside, "outside-secret.txt"), os.path.join(site, "escape.txt"), False)
    ok_dir, why_dir = try_symlink(outside, os.path.join(site, "link-out"), True)
    ok_asset, why_asset = try_symlink(outside, os.path.join(site, "assets", "link-out"), True)
    if ok_file or ok_dir:
        link_mode = "symlink"
    else:
        link_reason = "symlink unavailable: %s / %s" % (why_file, why_dir)
        j_ok, j_why = try_junction(outside, os.path.join(site, "link-j"))
        if j_ok:
            link_mode = "junction"
            link_reason += "; junction fallback created (Windows reparse point)"
        else:
            link_reason += "; junction unavailable: " + j_why

    env = {
        "PULSE_SITE_DIR": site,
        "PULSE_UPLOAD_DIR": uploads,
        "PULSE_UPLOAD_MAX_BYTES": "2048",
        "PULSE_UPLOAD_MAX_PARTS": "8",
    }
    print("static-traversal-smoke: server=" + os.path.abspath(args.server_exe) + " port=" + str(args.port))
    ctx = start_server(args.server_exe, args.port, env, "static")
    try:
        # Baseline: normal site + asset serving still works.
        for path, needle in [(b"/", b"site home"), (b"/about", b"about"),
                             (b"/sub/", b"sub home"), (b"/inside.txt", b"INSIDE-OK"),
                             (b"/assets/style.css", b"color")]:
            r = raw_request(args.port, b"GET " + path + b" HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", args.timeout)
            result.check("baseline " + path.decode("latin1"), r["status"] == 200 and needle in r["body"],
                         "status=%s body=%r" % (r["status"], r["body"][:80]))

        # Lexical traversal table for the site and /assets/ trees.
        for path in TRAVERSAL_PATHS:
            r = raw_request(args.port, b"GET " + path + b" HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", args.timeout)
            escaped = canary.encode("latin1") in r["body"]
            safe_status = r["status"] in (400, 403, 404)
            result.check("site traversal " + path.decode("latin1"),
                         safe_status and not escaped,
                         "status=%s escaped=%s body=%r" % (r["status"], escaped, r["body"][:100]))
            if not server_alive(args.port, args.timeout):
                result.check("site traversal server alive", False, "server stopped after " + path.decode("latin1"))
                return finish(ctx, result, "static-traversal-smoke", args.allow_known_gaps)

        # A native file/dir symlink (or the Windows junction fallback) that
        # points outside the site root must never be served.
        link_cases = []
        if ok_file:
            link_cases.append(("symlink file", b"/escape.txt"))
        if ok_dir:
            link_cases.append(("symlink dir", b"/link-out/outside-secret.txt"))
            link_cases.append(("symlink dir index", b"/link-out/"))
        if ok_asset:
            link_cases.append(("symlink asset dir", b"/assets/link-out/outside-secret.txt"))
        if link_mode == "junction":
            link_cases.append(("junction dir", b"/link-j/outside-secret.txt"))
        if not link_cases:
            result.skip("canonical link escape", link_reason)
        else:
            if link_mode == "junction":
                result.skip("native symlink escape", link_reason)
            for label, path in link_cases:
                r = raw_request(args.port, b"GET " + path + b" HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", args.timeout)
                escaped = canary.encode("latin1") in r["body"]
                detail = "status=%s escaped=%s body=%r" % (r["status"], escaped, r["body"][:120])
                safe = r["status"] in (403, 404) and not escaped
                if safe:
                    result.check(label + " " + path.decode("latin1"), True, detail)
                elif link_mode == "junction" or args.allow_known_gaps:
                    # The exact requested case (native symlink) may be
                    # unavailable on this host; the junction fallback is an
                    # additional canonical-escape probe. Both are reported as
                    # gaps when --allow-known-gaps is set so CI can gate on
                    # them while the canonical-path check is tracked.
                    result.gap(label + " " + path.decode("latin1"), detail, "HIGH",
                               "canonical escape (link points outside the site root); add a canonical-path check")
                else:
                    result.check(label + " " + path.decode("latin1"), False, detail)
                if not server_alive(args.port, args.timeout):
                    result.check("canonical link server alive", False, "server stopped after " + path.decode("latin1"))
                    return finish(ctx, result, "static-traversal-smoke", args.allow_known_gaps)

        # Upload filename traversal: client names never become path
        # components; no file may appear outside the upload directory.
        outside_before = set(walk_files(outside))
        boundary = "----pulseTravBOUND"
        for tag, fname in UPLOAD_TRAVERSAL_FILENAMES:
            marker = ("TRAV-" + tag).encode("ascii")
            body = multipart_body(boundary, [{"name": "file", "filename": fname, "content_type": "text/plain", "content": marker}])
            r = multipart_post(args.port, body, boundary, args.timeout)
            ok_status = r["status"] in (200, 400, 413)
            escaped = False
            for p in walk_files(base):
                if os.path.commonpath([os.path.abspath(p), os.path.abspath(uploads)]) == os.path.abspath(uploads):
                    continue
                if file_contains(p, marker):
                    escaped = True
                    break
            result.check("upload traversal " + tag, ok_status and not escaped,
                         "status=%s escaped=%s body=%r" % (r["status"], escaped, r["body"][:120]))
            if not server_alive(args.port, args.timeout):
                result.check("upload traversal server alive", False, "server stopped after " + tag)
                return finish(ctx, result, "static-traversal-smoke", args.allow_known_gaps)
        outside_after = set(walk_files(outside))
        new_outside = outside_after - outside_before
        result.check("no upload file outside root", len(new_outside) == 0, "new files: " + repr(sorted(new_outside)))
        return finish(ctx, result, "static-traversal-smoke", args.allow_known_gaps)
    finally:
        stop_server(ctx["proc"], ctx["port"], ctx["out_f"], ctx["err_f"], ctx["base"], args.keep)
        if args.keep:
            print("security-smoke: kept fixture dir " + base)
        else:
            shutil.rmtree(base, ignore_errors=True)


# ---------------------------------------------------------------------------
# Upload MIME / extension / cap corpus
# ---------------------------------------------------------------------------

def upload_case(name, parts, expect_reject, severity="", note=""):
    return {"name": name, "parts": parts, "expect_reject": expect_reject,
            "severity": severity, "note": note}


def upload_cases():
    true = b"<?php echo 1; ?>"
    cases = []
    cases.append(upload_case("php-extension", [
        {"name": "file", "filename": "shell.php", "content_type": "text/plain", "content": true}],
        True, "HIGH", "dangerous extension with a benign MIME"))
    cases.append(upload_case("php-mime", [
        {"name": "file", "filename": "shell.php", "content_type": "application/x-php", "content": true}],
        True, "HIGH", "dangerous MIME + extension"))
    cases.append(upload_case("double-extension", [
        {"name": "file", "filename": "evil.txt.php", "content_type": "text/plain", "content": true}],
        True, "HIGH", "double extension; server keeps the last extension"))
    cases.append(upload_case("uppercase-php", [
        {"name": "file", "filename": "shell.PHP", "content_type": "text/plain", "content": true}],
        True, "HIGH", "uppercase .PHP extension is preserved on disk"))
    cases.append(upload_case("svg-mime", [
        {"name": "file", "filename": "x.svg", "content_type": "image/svg+xml", "content": b"<svg onload=alert(1)>"}],
        True, "MEDIUM", "active SVG content"))
    cases.append(upload_case("html-mime", [
        {"name": "file", "filename": "x.html", "content_type": "text/html", "content": b"<script>alert(1)</script>"}],
        True, "MEDIUM", "active HTML content"))
    cases.append(upload_case("duplicate-part-header", [
        {"name": "file", "filename": "dup.txt", "content_type": "text/plain", "content": b"DUP",
         "headers": [("Content-Disposition", 'form-data; name="evil"; filename="evil.php"')]}],
        True, "MEDIUM", "duplicate Content-Disposition: last filename wins"))
    cases.append(upload_case("oversized-part-header", [
        {"name": "file", "filename": "hdr.txt", "content_type": "text/plain", "content": b"HDR",
         "headers": [("X-Pad", "P" * (200 * 1024))]}],
        True, "LOW", "200 KiB part header accepted (no part-header cap)"))
    # Enforced caps.
    cases.append(upload_case("part-too-large", [
        {"name": "file", "filename": "big.txt", "content_type": "text/plain", "content": b"A" * 3000}],
        True, "", "part exceeds PULSE_UPLOAD_MAX_BYTES=2048"))
    four = []
    for i, name in enumerate(["a.txt", "b.txt", "c.txt", "d.txt"]):
        four.append({"name": "file", "filename": name, "content_type": "text/plain", "content": bytes([65 + i])})
    cases.append(upload_case("too-many-parts", four, True, "", "4 parts with PULSE_UPLOAD_MAX_PARTS=3"))
    cases.append(upload_case("oversized-total", [
        {"name": "file", "filename": "huge.txt", "content_type": "text/plain", "content": b"A" * (MAX_BODY + 1000)}],
        True, "", "request body exceeds the 1 MiB HTTP body cap"))
    return cases


def run_upload(args, result):
    base = tempfile.mkdtemp(prefix="pulse-upload-fixtures-")
    uploads = os.path.join(base, "uploads")
    outside = os.path.join(base, "outside")
    os.makedirs(uploads)
    os.makedirs(outside)
    outside_before = set(walk_files(outside))
    env = {
        "PULSE_UPLOAD_DIR": uploads,
        "PULSE_UPLOAD_MAX_BYTES": "2048",
        "PULSE_UPLOAD_MAX_PARTS": "3",
    }
    print("upload-security-smoke: server=" + os.path.abspath(args.server_exe) + " port=" + str(args.port))
    ctx = start_server(args.server_exe, args.port, env, "upload")
    try:
        # Filename traversal / duplicate field behavior first; these are
        # safe-by-design if the server only derives an extension.
        extra = [
            ("traversal-dotdot", [{"name": "file", "filename": "../../escape-a.txt", "content_type": "text/plain", "content": b"TRAV-A"}], False, ""),
            ("traversal-backslash", [{"name": "file", "filename": "..\\..\\escape-b.txt", "content_type": "text/plain", "content": b"TRAV-B"}], False, ""),
            ("traversal-abs", [{"name": "file", "filename": "C:\\Windows\\win.ini", "content_type": "text/plain", "content": b"TRAV-C"}], False, ""),
            ("traversal-unix-abs", [{"name": "file", "filename": "/etc/passwd", "content_type": "text/plain", "content": b"TRAV-D"}], False, ""),
            ("traversal-encoded", [{"name": "file", "filename": "%2e%2e%2fescape-e.txt", "content_type": "text/plain", "content": b"TRAV-E"}], False, ""),
            ("nul-filename", [{"name": "file", "filename": "evil\x00.txt", "content_type": "text/plain", "content": b"TRAV-F"}], False, ""),
            ("crlf-filename", [{"name": "file", "filename": "evil\r\nX-Injected: 1\r\n.txt", "content_type": "text/plain", "content": b"TRAV-G"}], False, ""),
            ("dup-field", [
                {"name": "file", "filename": "a.txt", "content_type": "text/plain", "content": b"TRAV-H1"},
                {"name": "file", "filename": "b.txt", "content_type": "text/plain", "content": b"TRAV-H2"}], False, ""),
            ("dup-filename", [
                {"name": "file", "filename": "same.txt", "content_type": "text/plain", "content": b"TRAV-I1"},
                {"name": "file", "filename": "same.txt", "content_type": "text/plain", "content": b"TRAV-I2"}], False, ""),
            ("no-filename-field", [{"name": "field", "filename": None, "content_type": "text/plain", "content": b"TRAV-J"}], False, ""),
        ]
        for name, parts, expect_reject, sev in extra:
            boundary = "----pulseUpBOUND"
            body = multipart_body(boundary, parts)
            r = multipart_post(args.port, body, boundary, args.timeout)
            escaped = False
            for p in walk_files(base):
                if os.path.commonpath([os.path.abspath(p), os.path.abspath(uploads)]) == os.path.abspath(uploads):
                    continue
                if any(file_contains(p, x["content"]) for x in parts):
                    escaped = True
                    break
            if name.startswith("dup-") or name.startswith("no-"):
                result.info(name, "status=%s body=%r" % (r["status"], r["body"][:160]))
                result.check(name + " no escape", not escaped, "escaped=%s" % escaped)
                try:
                    parsed = json.loads(r["body"].decode("utf-8", "replace"))
                except Exception:
                    parsed = None
                if parsed is None:
                    result.check(name + " json response", False, "body is not JSON")
                elif name == "no-filename-field":
                    result.check(name + " not stored", parsed.get("stored") == 0,
                                 "stored=%r" % parsed.get("stored"))
                else:
                    files = parsed.get("files", [])
                    names = [f.get("name") for f in files]
                    result.check(name + " stores both parts", len(files) == 2,
                                 "files=%r" % names)
                    result.check(name + " distinct generated names", len(set(names)) == 2,
                                 "files=%r" % names)
            else:
                result.check(name + " no escape", r["status"] in (200, 400, 413) and not escaped,
                             "status=%s escaped=%s body=%r" % (r["status"], escaped, r["body"][:120]))
            if not server_alive(args.port, args.timeout):
                result.check(name + " server alive", False, "server stopped")
                return finish(ctx, result, "upload-security-smoke", args.allow_known_gaps)

        for case in upload_cases():
            boundary = "----pulseUpBOUND"
            body = multipart_body(boundary, case["parts"])
            r = multipart_post(args.port, body, boundary, 12.0)
            rejected = r["status"] in REJECT_STATUSES
            accepted = r["status"] == 200
            detail = "status=%s body=%r" % (r["status"], r["body"][:180])
            if case["note"]:
                detail = case["note"] + "; " + detail
            if rejected:
                result.check(case["name"] + " rejected", True, detail)
            elif accepted and case["expect_reject"]:
                if case["severity"]:
                    result.gap(case["name"] + " accepted", detail, case["severity"],
                               "no upload MIME/extension/part-header policy; the file is stored")
                else:
                    result.check(case["name"] + " rejected", False, detail)
            elif accepted and not case["expect_reject"]:
                result.check(case["name"] + " accepted", True, detail)
            else:
                result.check(case["name"] + " no server error", False, detail)
            if not server_alive(args.port, args.timeout):
                result.check(case["name"] + " server alive", False, "server stopped")
                return finish(ctx, result, "upload-security-smoke", args.allow_known_gaps)

        # Disk invariants: generated names only, no escape, no overwrite.
        files = walk_files(uploads)
        bad_names = [p for p in files if not re.match(r"^up-\d+-\d+-\d+(\.[A-Za-z0-9]+)?$", os.path.basename(p))]
        result.check("upload names are generated", len(bad_names) == 0, "bad=" + repr([os.path.basename(x) for x in bad_names[:10]]))
        outside_after = set(walk_files(outside))
        new_outside = outside_after - outside_before
        result.check("no upload file outside root", len(new_outside) == 0, "new=" + repr(sorted(new_outside)))
        # Every successful response file must exist under the upload dir.
        missing = []
        for p in files:
            if not os.path.abspath(p).startswith(os.path.abspath(uploads) + os.sep):
                missing.append(p)
        result.check("all upload files under upload dir", len(missing) == 0, "outside=" + repr(missing))
        return finish(ctx, result, "upload-security-smoke", args.allow_known_gaps)
    finally:
        stop_server(ctx["proc"], ctx["port"], ctx["out_f"], ctx["err_f"], ctx["base"], args.keep)
        if args.keep:
            print("security-smoke: kept fixture dir " + base)
        else:
            shutil.rmtree(base, ignore_errors=True)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description="XIOM PULSE raw HTTP security smoke")
    sub = p.add_subparsers(dest="cmd")

    def common(sp):
        sp.add_argument("--server-exe", required=True)
        sp.add_argument("--port", type=int, required=True)
        sp.add_argument("--timeout", type=float, default=3.0)
        sp.add_argument("--allow-known-gaps", action="store_true")
        sp.add_argument("--strict-nul", action="store_true")
        sp.add_argument("--keep", action="store_true")

    f = sub.add_parser("framing")
    common(f)
    s = sub.add_parser("static")
    common(s)
    u = sub.add_parser("upload")
    common(u)
    args = p.parse_args()
    if not args.cmd:
        p.print_help()
        return 2
    result = Result()
    if args.cmd == "framing":
        return run_framing(args, result)
    if args.cmd == "static":
        return run_static(args, result)
    return run_upload(args, result)


if __name__ == "__main__":
    sys.exit(main())
