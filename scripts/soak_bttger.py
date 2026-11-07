#!/usr/bin/env python3
# ============================================================================
# XIOM PULSE -- bttger-mix soak driver (WP1 gate harness).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives the six-endpoint bttger contract (benchmarks/bttger/main.xi) over
# persistent HTTP/1.1 keep-alive connections at a fixed request rate, samples
# server memory/handles, and gates on errors, rate shortfall and the RSS cap.
#
# Usage:
#   python scripts/soak_bttger.py --seconds 60 --rate 100
#   python scripts/soak_bttger.py --seconds 86400 --rate 100 --max-rss-mb 256
#   python scripts/soak_bttger.py --server-exe out/bench_bttger_soak.exe
#
# Windows wrapper (exact 24 h ops command):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\soak_bttger.ps1 `
#       -Seconds 86400 -Rate 100 -Port 18800 -MaxRssMb 256 -Rebuild
# Unix wrapper (exact 24 h ops command):
#   bash scripts/soak_bttger.sh --seconds 86400 --rate 100 --port 18800 `
#       --max-rss-mb 256 --rebuild
#
# Exit codes: 0 = gate PASS, 1 = gate FAIL, 2 = usage error, 130 = SIGINT.
# ============================================================================

import argparse
import ctypes
import json
import os
import platform
import random
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time

SERVER_NAME = "bench_bttger_soak"
BFILE = os.path.join("benchmarks", "bttger", "main.xi")
MAX_HEADER_BYTES = 64 * 1024
MAX_BODY_BYTES = 64 * 1024 * 1024
RECV_CHUNK = 65536

INSERT_BODY = json.dumps(
    {
        "name": "Sightseeing",
        "addresses": [
            {"street": "Breite Strasse", "number": 89, "city": "Luebeck"},
            {"street": "Breite Strasse", "number": 89, "city": "Luebeck"},
        ],
        "oldTown": True,
    },
    separators=(",", ":"),
).encode("ascii")

MIX = [
    {
        "name": "getSerialized",
        "method": "GET",
        "path": "/serialize",
        "expect": b"Hello, World!",
    },
    {
        "name": "getSerializedBig",
        "method": "GET",
        "path": "/serialize/big",
        "expect": b"Elephantidae",
    },
    {
        "name": "getPlainText",
        "method": "GET",
        "path": "/plain/text",
        "expect": b"Hello, World!",
    },
    {
        "name": "getQueryResult",
        "method": "GET",
        "path": "/query/300/tools/10?model=Dozer&factor=ATX&length=800&width=800&allow=true",
        "headers": {"x-api-key": "zb478fb3", "x-session-id": "jhg723bf"},
        "expect": b'"id":6000',
    },
    {
        "name": "insertObject",
        "method": "POST",
        "path": "/insert",
        "headers": {"content-type": "application/json"},
        "body": INSERT_BODY,
        "expect": b'"id":300',
    },
    {
        "name": "getCalculated",
        "method": "GET",
        "path": "/calculate",
        "expect": b'"fibonacci":317811',
    },
]


class ProtocolError(Exception):
    pass


class ConnectionClosed(Exception):
    pass


class Rpcs:
    """Persistent HTTP/1.1 connection with exact response framing."""

    def __init__(self, host, port, timeout):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock = None
        self.buf = b""
        self.wire_in = 0
        self._open()

    def _open(self):
        self.close()
        self.sock = socket.create_connection((self.host, self.port), self.timeout)
        self.sock.settimeout(self.timeout)
        try:
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        self.buf = b""
        self.wire_in = 0

    def close(self):
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock = None
        self.buf = b""

    def _recv_more(self):
        chunk = self.sock.recv(RECV_CHUNK)
        if not chunk:
            raise ConnectionClosed("peer closed the connection")
        self.buf += chunk
        self.wire_in += len(chunk)

    def _read_line(self):
        while b"\n" not in self.buf:
            if len(self.buf) > MAX_HEADER_BYTES:
                raise ProtocolError("response line exceeds %d bytes" % MAX_HEADER_BYTES)
            self._recv_more()
        line, self.buf = self.buf.split(b"\n", 1)
        return line.rstrip(b"\r")

    def _read_exact(self, n):
        if n > MAX_BODY_BYTES:
            raise ProtocolError("response body exceeds %d bytes" % MAX_BODY_BYTES)
        while len(self.buf) < n:
            self._recv_more()
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _read_chunked(self):
        body = bytearray()
        while True:
            size_line = self._read_line()
            size_txt = size_line.split(b";", 1)[0].strip()
            try:
                size = int(size_txt, 16)
            except ValueError:
                raise ProtocolError("bad chunk size %r" % size_txt)
            if size == 0:
                while True:
                    trailer = self._read_line()
                    if trailer == b"":
                        break
                return bytes(body)
            body.extend(self._read_exact(size))
            crlf = self._read_exact(2)
            if crlf != b"\r\n":
                raise ProtocolError("bad chunk terminator")
            if len(body) > MAX_BODY_BYTES:
                raise ProtocolError("response body exceeds %d bytes" % MAX_BODY_BYTES)

    def request(self, method, path, headers=None, body=None):
        lines = [
            "%s %s HTTP/1.1" % (method, path),
            "Host: %s:%d" % (self.host, self.port),
            "Connection: keep-alive",
            "Accept: */*",
        ]
        hdrs = dict(headers or {})
        if body is not None:
            hdrs.setdefault("content-length", str(len(body)))
        for key, value in hdrs.items():
            lines.append("%s: %s" % (key, value))
        wire = ("\r\n".join(lines) + "\r\n\r\n").encode("latin-1")
        if body is not None:
            wire += body
        before = self.wire_in
        self.sock.sendall(wire)
        status_line = self._read_line()
        parts = status_line.split(b" ", 2)
        if len(parts) < 2 or not parts[0].startswith(b"HTTP/"):
            raise ProtocolError("bad status line %r" % status_line[:120])
        try:
            status = int(parts[1])
        except ValueError:
            raise ProtocolError("bad status code %r" % parts[1])
        resp_headers = {}
        while True:
            line = self._read_line()
            if line == b"":
                break
            if b":" not in line:
                raise ProtocolError("bad header line %r" % line[:120])
            key, value = line.split(b":", 1)
            resp_headers[key.strip().lower()] = value.strip()
        if b"transfer-encoding" in resp_headers and b"chunked" in resp_headers[b"transfer-encoding"].lower():
            resp_body = self._read_chunked()
        elif b"content-length" in resp_headers:
            try:
                length = int(resp_headers[b"content-length"])
            except ValueError:
                raise ProtocolError("bad content-length")
            resp_body = self._read_exact(length)
        elif status in (204, 304):
            resp_body = b""
        else:
            raise ProtocolError("response has no content-length")
        return status, resp_headers, resp_body, self.wire_in - before


class Reservoir:
    """Bounded deterministic reservoir for latency percentiles."""

    def __init__(self, cap=200000):
        self.cap = cap
        self.items = []
        self.count = 0
        self.rnd = random.Random(1731)
        self.lock = threading.Lock()

    def add(self, value):
        with self.lock:
            self.count += 1
            if len(self.items) < self.cap:
                self.items.append(value)
            else:
                idx = self.rnd.randrange(self.count)
                if idx < self.cap:
                    self.items[idx] = value

    def percentiles(self):
        with self.lock:
            values = sorted(self.items)
        if not values:
            return {"p50_ms": None, "p95_ms": None, "p99_ms": None, "max_ms": None}
        def pick(p):
            idx = int(round((len(values) - 1) * p))
            return values[idx]
        return {
            "p50_ms": round(pick(0.50), 3),
            "p95_ms": round(pick(0.95), 3),
            "p99_ms": round(pick(0.99), 3),
            "max_ms": round(values[-1], 3),
        }


class RunState:
    def __init__(self, mix, measure_start, measure_end, fail_fast=True):
        self.mix = mix
        self.measure_start = measure_start
        self.measure_end = measure_end
        self.fail_fast = fail_fast
        self.stop_event = threading.Event()
        self.lock = threading.Lock()
        self.fatal = ""
        self.stop_reason = ""
        self.cap_exceeded = False
        self.mix_index = 0
        self.warmup_requests = 0
        self.measured_requests = 0
        self.ok = 0
        self.non2xx = 0
        self.errors = 0
        self.body_mismatch = 0
        self.wire_bytes = 0
        self.body_bytes = 0
        self.status_counts = {}
        self.error_kinds = {}
        self.error_samples = []
        self.latency = Reservoir()
        self.samples = []

    def next_endpoint(self):
        with self.lock:
            ep = self.mix[self.mix_index % len(self.mix)]
            self.mix_index += 1
            return ep

    def record_sample(self, phase, rss, handles):
        with self.lock:
            self.samples.append(
                {
                    "t": round(time.perf_counter(), 3),
                    "phase": phase,
                    "rss": rss,
                    "handles": handles,
                    "measured_requests": self.measured_requests,
                }
            )

    def record_result(self, phase, endpoint, status, wire, body_len, latency_ms):
        measured = phase == "measured"
        with self.lock:
            if measured:
                self.measured_requests += 1
            else:
                self.warmup_requests += 1
            self.status_counts[status] = self.status_counts.get(status, 0) + 1
            if measured and wire is not None:
                self.wire_bytes += wire
            if measured and body_len is not None:
                self.body_bytes += body_len
            if measured and latency_ms is not None:
                self.latency.add(latency_ms)
            if 200 <= status < 300:
                self.ok += 1
                bad_status = False
            else:
                self.non2xx += 1
                bad_status = True
        if bad_status and self.fail_fast:
            self.set_stop("non2xx")

    def record_error(self, phase, endpoint, kind, message):
        with self.lock:
            self.errors += 1
            self.error_kinds[kind] = self.error_kinds.get(kind, 0) + 1
            if len(self.error_samples) < 20:
                self.error_samples.append("%s %s: %s: %s" % (phase, endpoint, kind, message[:200]))
        if self.fail_fast:
            self.set_stop("errors")

    def record_mismatch(self, phase, endpoint, detail):
        with self.lock:
            self.body_mismatch += 1
            self.error_kinds["body_mismatch"] = self.error_kinds.get("body_mismatch", 0) + 1
            if len(self.error_samples) < 20:
                self.error_samples.append("%s %s: body_mismatch: %s" % (phase, endpoint, detail[:200]))
        if self.fail_fast:
            self.set_stop("body_mismatch")

    def set_fatal(self, reason):
        with self.lock:
            if not self.fatal:
                self.fatal = reason
        self.stop_event.set()

    def set_stop(self, reason):
        with self.lock:
            if not self.stop_reason:
                self.stop_reason = reason
        self.stop_event.set()

    def snapshot_requests(self):
        with self.lock:
            return self.measured_requests, self.warmup_requests


class MemSampler:
    def __init__(self, pid):
        self.pid = pid
        self.is_windows = os.name == "nt"
        self.handle = None
        self.close_handle = None
        if self.is_windows:
            self._init_windows()

    def _init_windows(self):
        from ctypes import wintypes

        class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        self._pmc = PROCESS_MEMORY_COUNTERS
        kernel32 = ctypes.windll.kernel32
        process_query_information = 0x0400
        process_vm_read = 0x0010
        handle = kernel32.OpenProcess(process_query_information | process_vm_read, False, self.pid)
        if not handle:
            handle = kernel32.OpenProcess(0x1000, False, self.pid)
        if not handle:
            raise RuntimeError("OpenProcess failed for pid %d" % self.pid)
        self.handle = handle
        self.kernel32 = kernel32
        self.psapi = ctypes.windll.psapi
        self.close_handle = kernel32.CloseHandle

    def close(self):
        if self.handle and self.close_handle:
            self.close_handle(self.handle)
            self.handle = None

    def sample(self):
        if self.is_windows:
            counters = self._pmc()
            counters.cb = ctypes.sizeof(counters)
            ok = self.psapi.GetProcessMemoryInfo(
                self.handle, ctypes.byref(counters), counters.cb
            )
            if not ok:
                raise RuntimeError("GetProcessMemoryInfo failed")
            handles = ctypes.c_ulong(0)
            self.kernel32.GetProcessHandleCount(self.handle, ctypes.byref(handles))
            return int(counters.WorkingSetSize), int(handles.value)
        try:
            with open("/proc/%d/status" % self.pid, "r") as fh:
                rss_kb = 0
                for line in fh:
                    if line.startswith("VmRSS:"):
                        rss_kb = int(line.split()[1])
                        break
            fd_count = len(os.listdir("/proc/%d/fd" % self.pid))
            return rss_kb * 1024, fd_count
        except OSError:
            out = subprocess.run(
                ["ps", "-o", "rss=", "-p", str(self.pid)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                universal_newlines=True,
            )
            rss_kb = int(out.stdout.strip() or "0")
            try:
                fd_count = int(
                    subprocess.run(
                        ["sh", "-c", "lsof -p %d 2>/dev/null | wc -l" % self.pid],
                        stdout=subprocess.PIPE,
                        universal_newlines=True,
                    ).stdout.strip()
                    or "0"
                )
            except (ValueError, OSError):
                fd_count = -1
            return rss_kb * 1024, fd_count


class Scheduler:
    def __init__(self, rate, start):
        self.interval = 1.0 / rate
        self.next_slot = start
        self.lock = threading.Lock()

    def wait_for_slot(self, stop_event):
        with self.lock:
            slot = self.next_slot
            self.next_slot += self.interval
        while True:
            remaining = slot - time.perf_counter()
            if remaining <= 0:
                return True
            if stop_event.is_set():
                return False
            if remaining > 0.02:
                time.sleep(min(remaining - 0.001, 0.02))
            else:
                time.sleep(remaining)


def worker_loop(state, sched, host, port, timeout, verify_bodies):
    phase = "warmup"
    conn = None
    while not state.stop_event.is_set():
        if not sched.wait_for_slot(state.stop_event):
            break
        now = time.perf_counter()
        if now >= state.measure_end:
            break
        phase = "measured" if now >= state.measure_start else "warmup"
        endpoint = state.next_endpoint()
        started = time.perf_counter()
        try:
            if conn is None:
                conn = Rpcs(host, port, timeout)
            status, _headers, body, wire = conn.request(
                endpoint["method"],
                endpoint["path"],
                endpoint.get("headers"),
                endpoint.get("body"),
            )
            latency_ms = (time.perf_counter() - started) * 1000.0
            state.record_result(phase, endpoint["name"], status, wire, len(body), latency_ms)
            if verify_bodies and 200 <= status < 300:
                expect = endpoint.get("expect")
                if expect is not None and expect not in body:
                    state.record_mismatch(
                        phase, endpoint["name"], "expected %r" % expect
                    )
        except (OSError, ProtocolError, ConnectionClosed) as exc:
            state.record_error(phase, endpoint["name"], type(exc).__name__, str(exc))
            if conn is not None:
                conn.close()
            conn = None
        except Exception as exc:
            state.record_error(phase, endpoint["name"], "unexpected", repr(exc))
            if conn is not None:
                conn.close()
            conn = None
    if conn is not None:
        conn.close()


def sampler_loop(state, mem, sample_ms, cap_bytes, proc, owned):
    next_t = time.perf_counter()
    last_print = 0.0
    print_every = max(10.0, sample_ms / 1000.0 * 10.0)
    while not state.stop_event.is_set():
        now = time.perf_counter()
        phase = "measured" if now >= state.measure_start else "warmup"
        try:
            rss, handles = mem.sample()
        except Exception as exc:
            state.set_fatal("memory sample failed: %s" % exc)
            break
        state.record_sample(phase, rss, handles)
        if rss > cap_bytes and not state.cap_exceeded:
            state.cap_exceeded = True
            state.set_stop("rss_cap_exceeded")
            break
        if owned and proc is not None and proc.poll() is not None:
            state.set_fatal("server exited early (code %s)" % proc.returncode)
            break
        if now - last_print >= print_every:
            measured, warm = state.snapshot_requests()
            elapsed = max(0.0, min(now, state.measure_end) - state.measure_start)
            rate_now = measured / elapsed if elapsed > 0 else 0.0
            print(
                "soak-bttger: %-8s elapsed=%6.1fs requests=%d (warm=%d) "
                "rate=%.1f/s rss=%.1fMB handles=%d"
                % (phase, max(0.0, now - state.measure_start), measured, warm,
                   rate_now, rss / (1024.0 * 1024.0), handles),
                flush=True,
            )
            last_print = now
        wait = next_t + sample_ms / 1000.0 - time.perf_counter()
        next_t += sample_ms / 1000.0
        if wait > 0:
            state.stop_event.wait(min(wait, 1.0))
        else:
            next_t = time.perf_counter()


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def default_server_exe(root):
    name = SERVER_NAME + (".exe" if os.name == "nt" else "")
    return os.path.join(root, "out", name)


def build_server(root, name):
    if os.name == "nt":
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if not powershell:
            raise RuntimeError("powershell not found; build manually or pass --server-exe")
        cmd = [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            os.path.join(root, "scripts", "build.ps1"),
            BFILE,
            "-Name",
            name,
            "-TimeoutSec",
            "300",
            "-NoIcon",
        ]
    else:
        bash = shutil.which("bash")
        if not bash:
            raise RuntimeError("bash not found; build manually or pass --server-exe")
        cmd = [
            bash,
            os.path.join(root, "scripts", "build.sh"),
            BFILE,
            "--name",
            name,
            "--timeout-sec",
            "300",
            "--no-icon",
        ]
    print("soak-bttger: building %s" % " ".join(cmd), flush=True)
    result = subprocess.run(cmd, cwd=root)
    if result.returncode != 0:
        raise RuntimeError("build failed (exit %d)" % result.returncode)


def port_open(host, port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.25)
    try:
        sock.connect((host, port))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def wait_listen(host, port, timeout_s):
    deadline = time.perf_counter() + timeout_s
    while time.perf_counter() < deadline:
        if port_open(host, port):
            return True
        time.sleep(0.1)
    return False


def start_server(exe, root, host, port, log_path):
    env = os.environ.copy()
    env["PULSE_PORT"] = str(port)
    env["PULSE_BIND"] = host
    env["PULSE_KEEPALIVE"] = "1"
    env["PULSE_IDLE_TIMEOUT"] = "120000"
    env["PULSE_READ_TIMEOUT"] = "30000"
    env["PULSE_WRITE_TIMEOUT"] = "30000"
    env["PULSE_LOG"] = "0"
    kwargs = {
        "cwd": root,
        "env": env,
        "stdin": subprocess.DEVNULL,
        "stdout": log_path,
        "stderr": subprocess.STDOUT,
    }
    if os.name == "nt":
        kwargs["creationflags"] = 0x08000000
    else:
        kwargs["start_new_session"] = True
    print("soak-bttger: starting %s (port %d, log %s)" % (exe, port, log_path), flush=True)
    return subprocess.Popen([exe], **kwargs)


def stop_server(proc, host, port):
    if proc.poll() is not None:
        return proc.returncode, True
    try:
        sock = socket.create_connection((host, port), 2.0)
        sock.sendall(
            b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Pulse-Quit: 1\r\nConnection: close\r\n\r\n"
        )
        sock.close()
    except OSError:
        pass
    try:
        proc.wait(timeout=15)
        return proc.returncode, True
    except subprocess.TimeoutExpired:
        pass
    clean = False
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(proc.pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except OSError:
            pass
    try:
        proc.wait(timeout=5)
        clean = False
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            proc.kill()
        else:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except OSError:
                pass
        proc.wait(timeout=5)
    return proc.returncode, clean


def slope(points):
    if len(points) < 2:
        return None
    n = float(len(points))
    mean_x = sum(p[0] for p in points) / n
    mean_y = sum(p[1] for p in points) / n
    denom = sum((p[0] - mean_x) ** 2 for p in points)
    if denom == 0:
        return None
    numer = sum((p[0] - mean_x) * (p[1] - mean_y) for p in points)
    return numer / denom


def fmt_mb(value):
    if value is None:
        return "n/a"
    return "%.1f MB" % (value / (1024.0 * 1024.0))


def fmt_big_mb(value):
    if value is None:
        return "n/a"
    mb = value / (1024.0 * 1024.0)
    if mb >= 1024 * 1024:
        return "%.2f TB" % (mb / (1024.0 * 1024.0))
    if mb >= 1024:
        return "%.2f GB" % (mb / 1024.0)
    return "%.1f MB" % mb


def begin_high_res_timer():
    if os.name != "nt":
        return False
    try:
        ctypes.windll.winmm.timeBeginPeriod(1)
        return True
    except Exception:
        return False


def end_high_res_timer(active):
    if active:
        try:
            ctypes.windll.winmm.timeEndPeriod(1)
        except Exception:
            pass


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="XIOM PULSE bttger-mix soak driver (WP1 gate harness).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "24 h WP1 gate commands:\n"
            "  Windows: powershell -NoProfile -ExecutionPolicy Bypass -File "
            ".\\scripts\\soak_bttger.ps1 -Seconds 86400 -Rate 100 -Port 18800 "
            "-MaxRssMb 256 -Rebuild\n"
            "  Unix:    bash scripts/soak_bttger.sh --seconds 86400 --rate 100 "
            "--port 18800 --max-rss-mb 256 --rebuild"
        ),
    )
    parser.add_argument("--seconds", type=float, default=60.0)
    parser.add_argument("--rate", type=float, default=100.0)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18800)
    parser.add_argument("--server-exe", default="")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--no-fail-fast", action="store_true")
    parser.add_argument("--fail-on-projection", action="store_true")
    parser.add_argument("--warmup-seconds", type=float, default=5.0)
    parser.add_argument("--connections", type=int, default=1)
    parser.add_argument("--max-rss-mb", type=float, default=256.0)
    parser.add_argument("--rate-tolerance", type=float, default=0.02)
    parser.add_argument("--sample-ms", type=int, default=0)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--only", default="")
    parser.add_argument("--no-verify-bodies", action="store_true")
    parser.add_argument("--json-out", default="")
    parser.add_argument("--log-dir", default="")
    args = parser.parse_args(argv)
    if args.seconds <= 0:
        parser.error("--seconds must be > 0")
    if args.rate <= 0:
        parser.error("--rate must be > 0")
    if args.connections < 1:
        parser.error("--connections must be >= 1")
    if args.max_rss_mb <= 0:
        parser.error("--max-rss-mb must be > 0")
    if args.warmup_seconds < 0:
        parser.error("--warmup-seconds must be >= 0")
    if args.sample_ms < 0:
        parser.error("--sample-ms must be >= 0")
    if args.server_exe and (args.rebuild or args.no_build):
        parser.error("--server-exe cannot be combined with --rebuild/--no-build")
    return args


def main(argv):
    args = parse_args(argv)
    root = repo_root()
    log_dir = args.log_dir or os.path.join(root, "probe-logs")
    if not os.path.isdir(log_dir):
        os.makedirs(log_dir)
    sample_ms = args.sample_ms
    if sample_ms <= 0:
        if args.seconds <= 600:
            sample_ms = 1000
        elif args.seconds <= 7200:
            sample_ms = 5000
        else:
            sample_ms = 60000
    mix = [ep for ep in MIX if not args.only or args.only in ep["name"]]
    if not mix:
        print("soak-bttger: --only %r matched no endpoint" % args.only, file=sys.stderr)
        return 2

    cap_bytes = int(args.max_rss_mb * 1024 * 1024)
    exe = ""
    owned = False
    proc = None
    log_fh = None
    mem = None
    timer_active = begin_high_res_timer()
    exit_code = 1
    try:
        exe = args.server_exe or default_server_exe(root)
        if args.server_exe and not os.path.isfile(exe):
            print("soak-bttger: server not found: %s" % exe, file=sys.stderr)
            return 1
        if args.rebuild or (not args.server_exe and not os.path.isfile(exe)):
            if args.no_build:
                print(
                    "soak-bttger: server not built and --no-build was given: %s" % exe,
                    file=sys.stderr,
                )
                return 1
            build_server(root, SERVER_NAME)
        if not os.path.isfile(exe):
            print("soak-bttger: server missing after build: %s" % exe, file=sys.stderr)
            return 1
        if port_open(args.host, args.port):
            print(
                "soak-bttger: port %d already in use; stop that listener first" % args.port,
                file=sys.stderr,
            )
            return 1
        log_path = os.path.join(log_dir, "soak-bttger-server.out")
        log_fh = open(log_path, "wb")
        proc = start_server(exe, root, args.host, args.port, log_fh)
        owned = True
        if not wait_listen(args.host, args.port, 20.0):
            print("soak-bttger: server did not listen on %s:%d" % (args.host, args.port), file=sys.stderr)
            try:
                log_fh.flush()
                with open(log_path, "r", errors="replace") as fh:
                    sys.stderr.write(fh.read()[-4000:])
            except OSError:
                pass
            return 1
        mem = MemSampler(proc.pid)
        print(
            "soak-bttger: server pid=%d exe=%s" % (proc.pid, exe), flush=True
        )

        warmup = float(args.warmup_seconds)
        start = time.perf_counter()
        measure_start = start + warmup
        measure_end = measure_start + float(args.seconds)
        state = RunState(
            mix, measure_start, measure_end,
            fail_fast=not args.no_fail_fast,
        )
        print(
            "soak-bttger: mix=%s"
            % ", ".join(ep["name"] for ep in mix),
            flush=True,
        )
        print(
            "soak-bttger: target=%.1f req/s warmup=%.1fs measured=%.1fs connections=%d "
            "cap=%.1f MB sample=%dms"
            % (args.rate, warmup, args.seconds, args.connections, args.max_rss_mb, sample_ms),
            flush=True,
        )
        if args.connections > 1:
            print(
                "soak-bttger: WARNING connections>1 on the sequential-accept core queues "
                "connections; throughput will not scale",
                flush=True,
            )

        sched = Scheduler(args.rate, start)
        sampler = threading.Thread(
            target=sampler_loop,
            args=(state, mem, sample_ms, cap_bytes, proc, owned),
            name="rss-sampler",
            daemon=True,
        )
        workers = [
            threading.Thread(
                target=worker_loop,
                args=(state, sched, args.host, args.port, args.timeout, not args.no_verify_bodies),
                name="load-%d" % idx,
                daemon=True,
            )
            for idx in range(args.connections)
        ]
        sampler.start()
        for worker in workers:
            worker.start()

        while time.perf_counter() < measure_end and not state.stop_event.is_set():
            if owned and proc.poll() is not None:
                state.set_fatal("server exited early (code %s)" % proc.returncode)
                break
            state.stop_event.wait(0.2)
        if not state.stop_reason and not state.fatal:
            state.set_stop("completed")
        elif state.fatal and not state.stop_reason:
            state.stop_reason = "fatal"
        state.stop_event.set()

        for worker in workers:
            worker.join(timeout=max(5.0, args.timeout + 2.0))
        sampler.join(timeout=max(2.0, sample_ms / 1000.0 + 2.0))

        try:
            rss, handles = mem.sample()
            state.record_sample("end", rss, handles)
        except Exception:
            pass

        server_exit = None
        clean_stop = True
        if owned and proc is not None:
            server_exit, clean_stop = stop_server(proc, args.host, args.port)

        measured, warm = state.snapshot_requests()
        planned = float(args.seconds)
        achieved = measured / planned if planned > 0 else 0.0
        rate_floor = args.rate * (1.0 - args.rate_tolerance)
        measured_samples = [s for s in state.samples if s["phase"] == "measured"]
        all_samples = state.samples
        first_sample = all_samples[0] if all_samples else None
        warm_end = measured_samples[0] if measured_samples else first_sample
        end_sample = all_samples[-1] if all_samples else None
        peak_rss = max((s["rss"] for s in all_samples), default=0)
        peak_handles = max((s["handles"] for s in all_samples), default=0)
        points = [(s["measured_requests"], s["rss"]) for s in measured_samples]
        rss_slope = slope(points)
        if warm_end and end_sample and end_sample["measured_requests"] > warm_end["measured_requests"]:
            delta_bpr = (
                end_sample["rss"] - warm_end["rss"]
            ) / float(end_sample["measured_requests"] - warm_end["measured_requests"])
        else:
            delta_bpr = None
        baseline_rss = warm_end["rss"] if warm_end else (first_sample["rss"] if first_sample else 0)
        if rss_slope is not None and rss_slope > 0:
            projected_24h = baseline_rss + rss_slope * args.rate * 86400.0
        else:
            projected_24h = baseline_rss
        if rss_slope is not None and rss_slope > 0:
            sustainable_s = max(0.0, (cap_bytes - baseline_rss) / (rss_slope * args.rate))
        else:
            sustainable_s = None
        wire_bpr = state.wire_bytes / float(measured) if measured else 0.0
        body_bpr = state.body_bytes / float(measured) if measured else 0.0
        lat = state.latency.percentiles()

        reasons = []
        if state.fatal:
            reasons.append(state.fatal)
        if state.errors > 0:
            reasons.append("errors=%d (%s)" % (state.errors, state.error_kinds))
        if state.non2xx > 0:
            reasons.append("non-2xx responses=%d" % state.non2xx)
        if state.body_mismatch > 0:
            reasons.append("body mismatches=%d" % state.body_mismatch)
        if achieved < rate_floor:
            reasons.append(
                "rate shortfall: %.2f req/s < %.2f req/s (%.1f%% of target)"
                % (achieved, rate_floor, 100.0 * achieved / args.rate)
            )
        if peak_rss > cap_bytes:
            reasons.append(
                "peak RSS %.1f MB > cap %.1f MB"
                % (peak_rss / (1024.0 * 1024.0), args.max_rss_mb)
            )
        if args.fail_on_projection and projected_24h > cap_bytes:
            reasons.append(
                "24h projection %s > %.1f MB cap (slope %.1f B/req)"
                % (fmt_big_mb(projected_24h), args.max_rss_mb,
                   rss_slope if rss_slope is not None else 0.0)
            )
        if owned and server_exit not in (0, None):
            reasons.append("server exited with code %s" % server_exit)
        if owned and not clean_stop:
            reasons.append("server did not shut down cleanly after X-Pulse-Quit")
        if state.stop_reason not in (
            "completed",
            "rss_cap_exceeded",
            "errors",
            "non2xx",
            "body_mismatch",
            "fatal",
        ):
            reasons.append("run stopped early: %s" % state.stop_reason)

        gate_pass = not reasons
        mem_label = "working set" if os.name == "nt" else "RSS"
        print("", flush=True)
        print("soak-bttger summary (%s)" % time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), flush=True)
        print("  server:        %s" % exe, flush=True)
        print(
            "  window:        warmup %.1fs + measured %.1fs @ %.1f req/s, connections=%d"
            % (warmup, args.seconds, args.rate, args.connections),
            flush=True,
        )
        print(
            "  requests:      measured=%d warmup=%d ok=%d non2xx=%d errors=%d mismatches=%d"
            % (measured, warm, state.ok, state.non2xx, state.errors, state.body_mismatch),
            flush=True,
        )
        print(
            "  rate:          achieved %.2f req/s (%.2f%% of target), floor %.2f req/s"
            % (achieved, 100.0 * achieved / args.rate, rate_floor),
            flush=True,
        )
        print(
            "  latency:       p50=%sms p95=%sms p99=%sms max=%sms"
            % (lat["p50_ms"], lat["p95_ms"], lat["p99_ms"], lat["max_ms"]),
            flush=True,
        )
        print(
            "  wire bytes:    total=%d avg=%.2f B/req; body avg=%.2f B/req"
            % (state.wire_bytes, wire_bpr, body_bpr),
            flush=True,
        )
        print(
            "  %-13s start=%s warm_end=%s end=%s peak=%s"
            % (
                mem_label + ":",
                fmt_mb(first_sample["rss"] if first_sample else None),
                fmt_mb(warm_end["rss"] if warm_end else None),
                fmt_mb(end_sample["rss"] if end_sample else None),
                fmt_mb(peak_rss),
            ),
            flush=True,
        )
        print(
            "  rss slope:     %.2f B/req (regression, %d measured samples); "
            "steady delta %.2f B/req"
            % (
                rss_slope if rss_slope is not None else 0.0,
                len(measured_samples),
                delta_bpr if delta_bpr is not None else 0.0,
            ),
            flush=True,
        )
        print(
            "  handles:       start=%s end=%s peak=%s"
            % (
                first_sample["handles"] if first_sample else "n/a",
                end_sample["handles"] if end_sample else "n/a",
                peak_handles,
            ),
            flush=True,
        )
        print(
            "  24h projection: %s at %.1f req/s (%s)"
            % (
                fmt_big_mb(projected_24h),
                args.rate,
                "gate input" if args.fail_on_projection else "slope extrapolation; not a gate result",
            ),
            flush=True,
        )
        if sustainable_s is not None:
            print(
                "  time to cap:   %.0fs at %.1f req/s (%.2f h)"
                % (sustainable_s, args.rate, sustainable_s / 3600.0),
                flush=True,
            )
        if owned:
            print("  server exit:   %s (clean=%s)" % (server_exit, clean_stop), flush=True)
        if state.error_samples:
            print("  error samples:", flush=True)
            for sample in state.error_samples:
                print("    %s" % sample, flush=True)
        print("  gate:          %s" % ("PASS" if gate_pass else "FAIL"), flush=True)
        for reason in reasons:
            print("    - %s" % reason, flush=True)

        summary = {
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "platform": {
                "system": platform.system(),
                "release": platform.release(),
                "machine": platform.machine(),
                "python": sys.version.split()[0],
            },
            "server": {
                "exe": exe or None,
                "pid": proc.pid if proc is not None else None,
                "exit_code": server_exit,
                "clean_stop": clean_stop if owned else None,
            },
            "config": {
                "seconds": args.seconds,
                "rate": args.rate,
                "warmup_seconds": warmup,
                "connections": args.connections,
                "port": args.port,
                "max_rss_mb": args.max_rss_mb,
                "rate_tolerance": args.rate_tolerance,
                "sample_ms": sample_ms,
                "mix": [ep["name"] for ep in mix],
                "verify_bodies": not args.no_verify_bodies,
                "fail_on_projection": args.fail_on_projection,
                "fail_fast": not args.no_fail_fast,
            },
            "result": {
                "measured_requests": measured,
                "warmup_requests": warm,
                "ok": state.ok,
                "non2xx": state.non2xx,
                "errors": state.errors,
                "body_mismatch": state.body_mismatch,
                "error_kinds": state.error_kinds,
                "error_samples": state.error_samples,
                "achieved_rate": round(achieved, 4),
                "rate_floor": round(rate_floor, 4),
                "status_counts": state.status_counts,
                "latency_ms": lat,
                "wire_bytes": state.wire_bytes,
                "wire_bytes_per_request": round(wire_bpr, 3),
                "body_bytes_per_request": round(body_bpr, 3),
                "rss_start": first_sample["rss"] if first_sample else None,
                "rss_warm_end": warm_end["rss"] if warm_end else None,
                "rss_end": end_sample["rss"] if end_sample else None,
                "rss_peak": peak_rss,
                "rss_slope_bytes_per_request": round(rss_slope, 3) if rss_slope is not None else None,
                "rss_steady_delta_bytes_per_request": round(delta_bpr, 3) if delta_bpr is not None else None,
                "rss_samples": len(measured_samples),
                "handles_start": first_sample["handles"] if first_sample else None,
                "handles_end": end_sample["handles"] if end_sample else None,
                "handles_peak": peak_handles,
                "projected_24h_rss": int(projected_24h),
                "projected_24h_pass": projected_24h <= cap_bytes,
                "seconds_to_cap": round(sustainable_s, 1) if sustainable_s is not None else None,
                "stop_reason": state.stop_reason,
                "fatal": state.fatal,
            },
            "gate": {
                "pass": gate_pass,
                "reasons": reasons,
            },
        }
        out_path = args.json_out or os.path.join(log_dir, "soak-bttger.summary.json")
        with open(out_path, "w") as fh:
            json.dump(summary, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print("  json:          %s" % out_path, flush=True)
        exit_code = 0 if gate_pass else 1
    except KeyboardInterrupt:
        print("\nsoak-bttger: interrupted", file=sys.stderr, flush=True)
        exit_code = 130
    finally:
        if mem is not None:
            mem.close()
        if owned and proc is not None and proc.poll() is None:
            stop_server(proc, args.host, args.port)
        if log_fh is not None:
            try:
                log_fh.flush()
                log_fh.close()
            except OSError:
                pass
        end_high_res_timer(timer_active)
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
