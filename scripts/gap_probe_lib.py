#!/usr/bin/env python3
# XIOM PULSE -- shared harness for the 2026-11-07 SSE/WS/OpenAPI gap probes.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# These probes are additive evidence for docs/FEATURE-TESTS.md W-08/W-09/
# W-12/R-14. They intentionally start a private server build on a unique
# port (18700+) with temp store/audit/upload paths so a probe never mutates
# the repository or another agent's files.
#
# Exit conventions (shared by the probe clients):
#   0 = no FAIL; known GAPs are reported but allowed unless --strict
#   1 = FAIL (crash, health loss, contract break) or --strict with GAPs
#   2 = setup/usage error (missing exe, port in use, server did not start)

import os
import socket
import subprocess
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def repo_root():
    return REPO_ROOT


def resolve_exe(path):
    """Resolve an exe path relative to the repo and add .exe on Windows."""
    if not path:
        return ""
    if not os.path.isabs(path):
        path = os.path.join(REPO_ROOT, path)
    if os.name == "nt" and not path.lower().endswith(".exe"):
        candidate = path + ".exe"
        if os.path.exists(candidate):
            path = candidate
    return path


def exit_code_text(code):
    if code is None:
        return "running"
    if code < 0:
        return "%d (%s)" % (code, hex(code & 0xFFFFFFFF))
    return str(code)


class Reporter:
    """Small PASS/GAP/FAIL counter shared by the standalone probes."""

    def __init__(self, name):
        self.name = name
        self.passed = 0
        self.gaps = 0
        self.failed = 0

    def _line(self, tag, name, detail):
        line = "[%s] %s" % (tag, name)
        if detail:
            line += " (%s)" % detail
        print(line)

    def ok(self, name, detail=""):
        self.passed += 1
        self._line("PASS", name, detail)

    def gap(self, name, detail=""):
        self.gaps += 1
        self._line("GAP", name, detail)

    def fail(self, name, detail=""):
        self.failed += 1
        self._line("FAIL", name, detail)

    def note(self, name, detail=""):
        self._line("INFO", name, detail)

    def summary(self):
        print("%s: pass=%d gap=%d fail=%d" % (
            self.name, self.passed, self.gaps, self.failed))
        if self.failed:
            print("%s: RED" % self.name)
        elif self.gaps:
            print("%s: GREEN-WITH-GAPS" % self.name)
        else:
            print("%s: GREEN" % self.name)

    def rc(self, strict=False):
        if self.failed:
            return 1
        if strict and self.gaps:
            return 1
        return 0


class Server:
    """Private PULSE server instance on a probe-only port.

    The environment is scrubbed of PULSE_* overrides first so a caller's
    shell (or an earlier smoke step) cannot change auth, CORS, store paths,
    or timeouts. Store/audit/upload paths point at a fresh temp directory.
    """

    def __init__(self, exe, port, tag, read_timeout_ms=1500):
        self.exe = exe
        self.port = port
        self.tag = tag
        self.read_timeout_ms = read_timeout_ms
        self.tmp = tempfile.mkdtemp(prefix="pulse-%s-" % tag)
        self.log_path = os.path.join(self.tmp, "server.log")
        self._log = None
        self.proc = None

    def _env(self):
        env = os.environ.copy()
        for key in list(env):
            if key.startswith("PULSE_"):
                env.pop(key, None)
        env.update({
            "PULSE_PORT": str(self.port),
            "PULSE_BIND": "127.0.0.1",
            "PULSE_RATE_LIMIT": "0",
            "PULSE_RATE_ROUTES": "",
            "PULSE_CORS_ORIGIN": "",
            "PULSE_CSRF": "0",
            "PULSE_READ_TIMEOUT": str(self.read_timeout_ms),
            "PULSE_WRITE_TIMEOUT": str(self.read_timeout_ms),
            "PULSE_IDLE_TIMEOUT": str(self.read_timeout_ms),
            "PULSE_LOG": "1",
            "PULSE_STORE_PATH": os.path.join(self.tmp, "events.jsonl"),
            "PULSE_AUDIT_PATH": os.path.join(self.tmp, "audit.log"),
            "PULSE_UPLOAD_DIR": os.path.join(self.tmp, "uploads"),
        })
        return env

    def start(self):
        self._log = open(self.log_path, "ab")
        self.proc = subprocess.Popen(
            [self.exe],
            cwd=REPO_ROOT,
            env=self._env(),
            stdout=self._log,
            stderr=subprocess.STDOUT,
        )
        if not self.wait_ready():
            tail = self.log_text()[-2000:]
            self.stop()
            raise RuntimeError(
                "server did not become ready on 127.0.0.1:%d\n%s"
                % (self.port, tail))

    def wait_ready(self, timeout=20.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.proc is not None and self.proc.poll() is not None:
                return False
            if self.health(0.5):
                return True
            time.sleep(0.1)
        return False

    def health(self, timeout=1.0):
        try:
            sock = socket.create_connection(("127.0.0.1", self.port), timeout)
            sock.settimeout(timeout)
            sock.sendall(
                b"GET /health HTTP/1.1\r\nHost: probe\r\n"
                b"Connection: close\r\n\r\n")
            data = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                data += chunk
            sock.close()
            return data.split(b"\r\n", 1)[0].startswith(b"HTTP/1.1 200")
        except (OSError, socket.timeout):
            return False

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def poll(self):
        return None if self.proc is None else self.proc.poll()

    def log_text(self):
        if self._log is not None:
            try:
                self._log.flush()
            except (OSError, ValueError):
                pass
        try:
            with open(self.log_path, "r", encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            return ""

    def log_lines(self):
        return self.log_text().splitlines()

    def handle_count(self):
        """Return the server process handle/fd count, or None if unavailable."""
        if not self.alive():
            return None
        if os.name == "nt":
            try:
                out = subprocess.check_output(
                    ["powershell", "-NoProfile", "-Command",
                     "(Get-Process -Id %d).HandleCount" % self.proc.pid],
                    text=True, stderr=subprocess.DEVNULL)
                return int(out.strip())
            except (OSError, ValueError, subprocess.CalledProcessError):
                return None
        fd_dir = "/proc/%d/fd" % self.proc.pid
        try:
            return len(os.listdir(fd_dir))
        except OSError:
            return None

    def stop(self):
        proc = self.proc
        if proc is not None and proc.poll() is None:
            try:
                sock = socket.create_connection(("127.0.0.1", self.port), 1.0)
                sock.sendall(
                    b"GET /health HTTP/1.1\r\nHost: probe\r\n"
                    b"X-Pulse-Quit: 1\r\n\r\n")
                sock.close()
            except (OSError, socket.timeout):
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
        if self._log is not None:
            try:
                self._log.close()
            except (OSError, ValueError):
                pass
            self._log = None
        self.proc = None

    def restart(self):
        self.stop()
        self.start()


def recv_exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise EOFError("eof")
        data += chunk
    return data


def recv_until(sock, marker, limit):
    data = b""
    while marker not in data and len(data) < limit:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    return data


def read_until_eof(sock, timeout):
    sock.settimeout(timeout)
    data = b""
    while True:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    return data


def split_http_response(raw):
    """Return (head_bytes, body_bytes) at the first CRLFCRLF."""
    at = raw.find(b"\r\n\r\n")
    if at < 0:
        return raw, b""
    return raw[:at], raw[at + 4:]


def dechunk(body):
    """Decode an HTTP/1.1 chunked body; return (decoded, saw_zero_chunk)."""
    out = bytearray()
    pos = 0
    saw_zero = False
    while True:
        end = body.find(b"\r\n", pos)
        if end < 0:
            break
        line = body[pos:end].split(b";", 1)[0].strip()
        try:
            size = int(line, 16)
        except ValueError:
            break
        pos = end + 2
        if size == 0:
            saw_zero = True
            break
        if pos + size > len(body):
            out.extend(body[pos:])
            break
        out.extend(body[pos:pos + size])
        pos += size + 2
    return bytes(out), saw_zero


def parse_sse(text):
    """Parse an SSE payload into dicts with event/data/id/retry fields."""
    events = []
    normalized = text.replace("\r\n", "\n")
    for block in normalized.split("\n\n"):
        if not block.strip():
            continue
        ev = {"event": "message", "data": "", "id": None, "retry": None}
        data_lines = []
        for line in block.split("\n"):
            if line.startswith(":"):
                continue
            if ":" in line:
                field, value = line.split(":", 1)
                if value.startswith(" "):
                    value = value[1:]
            else:
                field, value = line, ""
            if field == "data":
                data_lines.append(value)
            elif field in ("event", "id", "retry"):
                ev[field] = value
        ev["data"] = "\n".join(data_lines)
        events.append(ev)
    return events


def require_exe(path):
    exe = resolve_exe(path)
    if not exe or not os.path.exists(exe):
        print("[FAIL] server binary not found: %s" % (exe or path))
        return None
    return exe


def run_cli(exe, args, timeout=30, env_overrides=None):
    """Run the server binary's CLI mode and return (rc, stdout+stderr)."""
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("PULSE_"):
            env.pop(key, None)
    if env_overrides:
        env.update(env_overrides)
    try:
        proc = subprocess.run(
            [exe] + list(args),
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            text=True,
            env=env,
        )
        return proc.returncode, proc.stdout or ""
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 2, "cli failed: %s" % exc


def main_guard(fn):
    try:
        return fn()
    except KeyboardInterrupt:
        return 130
    except Exception as exc:  # noqa: BLE001 -- probes report the cause
        print("[FAIL] unhandled probe exception: %r" % (exc,))
        return 1
