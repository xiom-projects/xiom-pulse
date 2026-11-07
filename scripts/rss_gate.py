#!/usr/bin/env python3
# ============================================================================
# XIOM PULSE PR memory-retention gate.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Starts a uniquely built PULSE server (CI uses out/ci_gate_server), drives
# GET /health for a bounded window, samples the process RSS, and gates on the
# steady-state bytes retained per served request (second sample onward).
#
# Budget: 25.0 KiB/request. The 2026-11 baseline is ~14.5-15.5 KiB/request; 25
# leaves allocator/noise headroom while still catching the 1704-class
# per-request regressions (which this gate would report far above 25). The
# final flat gate is a separate goal; this is a regression tripwire, not a
# zero-growth assertion.
#
# Robustness: samples are taken on a fixed wall-clock cadence and the gate
# uses the steady window only. It fails only when BOTH the OLS slope and the
# Theil-Sen median slope exceed the budget, so one noisy sample cannot turn a
# green run red. A timeout, a server exit, or too few samples exits non-zero
# (never green).
#
# Usage:
#   python scripts/rss_gate.py --exe out/ci_gate_server --port 18310
#   python scripts/rss_gate.py --exe out/ci_gate_server.exe --seconds 75
#
# Exit codes: 0 = green, 1 = budget/server failure, 2 = setup/measurement
# failure (missing binary, server never listened, too few samples).
# ============================================================================

import argparse
import os
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

DEFAULT_BUDGET_KB = 25.0
DEFAULT_SECONDS = 75
# 200 ms matches the known-good rss_probe cadence; at 500 ms the single
# accept loop occasionally let one request hit the client timeout, which
# distorted both the request count and the slope.
DEFAULT_INTERVAL_MS = 200
DEFAULT_SAMPLE_MS = 5000
DEFAULT_PORT = 18310


def rss_kb(pid):
    """Return the resident set size for pid in KiB."""
    if os.name == "nt":
        return _rss_kb_windows(pid)
    if sys.platform == "darwin":
        return _rss_kb_macos(pid)
    return _rss_kb_linux(pid)


def _rss_kb_linux(pid):
    path = "/proc/%d/status" % pid
    with open(path, "r") as handle:
        for line in handle:
            if line.startswith("VmRSS:"):
                return float(line.split()[1])
    raise OSError("VmRSS not present in %s" % path)


def _rss_kb_macos(pid):
    out = subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)])
    return float(out.strip())


def _rss_kb_windows(pid):
    import ctypes
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

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    psapi.GetProcessMemoryInfo.argtypes = [
        wintypes.HANDLE,
        ctypes.POINTER(PROCESS_MEMORY_COUNTERS),
        wintypes.DWORD,
    ]
    psapi.GetProcessMemoryInfo.restype = wintypes.BOOL

    # PROCESS_QUERY_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION
    handle = kernel32.OpenProcess(0x0400 | 0x1000, False, int(pid))
    if not handle:
        raise OSError("OpenProcess(%d) failed: %d" % (pid, ctypes.get_last_error()))
    try:
        counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(counters)
        if not psapi.GetProcessMemoryInfo(
            handle, ctypes.byref(counters), counters.cb
        ):
            raise OSError(
                "GetProcessMemoryInfo(%d) failed: %d"
                % (pid, ctypes.get_last_error())
            )
        return counters.WorkingSetSize / 1024.0
    finally:
        kernel32.CloseHandle(handle)


def health_once(port, timeout=5.0):
    """One GET /health; returns True on 200."""
    url = "http://127.0.0.1:%d/health" % port
    req = urllib.request.Request(url, headers={"Connection": "close"})
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


def send_quit(port):
    url = "http://127.0.0.1:%d/health" % port
    req = urllib.request.Request(
        url, headers={"X-Pulse-Quit": "1", "Connection": "close"}
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            resp.read(64)
    except (urllib.error.URLError, OSError):
        pass


def stop_server(proc, port):
    send_quit(port)
    try:
        proc.wait(timeout=15.0)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5.0)


def ols_slope(points):
    """Least-squares slope of y (KiB) against x (requests)."""
    n = len(points)
    mean_x = sum(p[0] for p in points) / n
    mean_y = sum(p[1] for p in points) / n
    num = sum((p[0] - mean_x) * (p[1] - mean_y) for p in points)
    den = sum((p[0] - mean_x) ** 2 for p in points)
    if den == 0:
        return 0.0
    return num / den


def theil_sen_slope(points):
    """Median of all pairwise slopes (robust to one noisy sample)."""
    slopes = []
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            dx = points[j][0] - points[i][0]
            if dx > 0:
                slopes.append((points[j][1] - points[i][1]) / dx)
    if not slopes:
        return 0.0
    return statistics.median(slopes)


def drive(proc, port, seconds, interval_s, sample_s, budget_kb, summary_path):
    baseline = rss_kb(proc.pid)
    start = time.monotonic()
    next_request = start
    last_sample = start
    ok = 0
    failed = 0
    samples = [(0.0, 0, baseline)]

    while True:
        now = time.monotonic()
        elapsed = now - start
        if elapsed >= seconds:
            break
        if now < next_request:
            time.sleep(min(next_request - now, 0.05))
            continue
        next_request += interval_s
        if next_request < now:
            next_request = now + interval_s

        if health_once(port):
            ok += 1
        else:
            failed += 1

        now = time.monotonic()
        if now - last_sample >= sample_s:
            samples.append((now - start, ok, rss_kb(proc.pid)))
            last_sample = now

    elapsed = time.monotonic() - start
    if ok > samples[-1][1]:
        samples.append((elapsed, ok, rss_kb(proc.pid)))

    # Steady state starts at the second sample; the first is baseline/warmup.
    steady = [(req, rss) for (_t, req, rss) in samples[1:] if req > 0]
    total = ok + failed
    fail_tolerance = max(1, total // 100)
    if len(samples) < 2:
        _report(
            summary_path,
            "too few samples: %d" % len(samples),
        )
        return 2

    if len(steady) < 3 or (steady[-1][0] - steady[0][0]) < 50:
        _report(
            summary_path,
            "steady window too small: samples=%d requests=%d"
            % (len(steady), (steady[-1][0] - steady[0][0]) if steady else 0),
        )
        return 2

    ols = ols_slope(steady)
    ts = theil_sen_slope(steady)
    first_req, first_rss = steady[0]
    last_req, last_rss = steady[-1]
    span_req = last_req - first_req
    span_s = samples[-1][0] - samples[1][0]
    endpoint = (last_rss - first_rss) / span_req

    lines = [
        "rss-gate: exe=%s pid=%d port=%d duration=%.1fs interval=%dms"
        % (proc.args[0] if isinstance(proc.args, list) else proc.args,
           proc.pid, port, elapsed, int(interval_s * 1000)),
        "rss-gate: samples=%d requests_ok=%d failed=%d (fail_tolerance=%d)"
        % (len(samples), ok, failed, fail_tolerance),
        "rss-gate: steady window = 2nd sample onward: samples=%d requests=%d span=%.1fs"
        % (len(steady), span_req, span_s),
        "rss-gate: rss %.1f -> %.1f KiB (growth %.1f KiB)"
        % (first_rss, last_rss, last_rss - first_rss),
        "rss-gate: steady slope OLS=%.2f KiB/req Theil-Sen=%.2f KiB/req "
        "(endpoint=%.2f) budget=%.2f KiB/req; rss@steady0=%.1f KiB"
        % (ols, ts, endpoint, budget_kb, first_rss),
        "rss-gate: measured = %.2f KiB/request (%.0f bytes/request)"
        % (ts, ts * 1024.0),
    ]

    failed_server = proc.poll()
    budget_exceeded = ols > budget_kb and ts > budget_kb
    if failed_server is not None and failed_server != 0:
        lines.append("rss-gate: RED server exited %d" % failed_server)
    elif failed > fail_tolerance:
        lines.append(
            "rss-gate: RED %d request(s) failed (tolerance %d)"
            % (failed, fail_tolerance)
        )
    elif budget_exceeded:
        lines.append(
            "rss-gate: RED steady slope exceeds %.2f KiB/request" % budget_kb
        )
    else:
        lines.append("rss-gate: GREEN")

    _report(summary_path, "\n".join(lines))
    return 1 if (budget_exceeded or failed > fail_tolerance or
                 (failed_server is not None and failed_server != 0)) else 0


def _report(summary_path, text):
    print(text)
    if summary_path:
        try:
            os.makedirs(os.path.dirname(summary_path), exist_ok=True)
            with open(summary_path, "w") as handle:
                handle.write(text + "\n")
        except OSError as exc:
            print("rss-gate: warning: cannot write summary: %s" % exc)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="PULSE PR memory-retention gate (steady RSS bytes/request)"
    )
    ap.add_argument("--exe", default="", help="PULSE server binary")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--seconds", type=int, default=DEFAULT_SECONDS)
    ap.add_argument("--interval-ms", type=int, default=DEFAULT_INTERVAL_MS)
    ap.add_argument("--sample-ms", type=int, default=DEFAULT_SAMPLE_MS)
    ap.add_argument("--budget-kb", type=float, default=DEFAULT_BUDGET_KB)
    ap.add_argument(
        "--summary",
        default=os.path.join("probe-logs", "ci-rss-gate.summary.txt"),
    )
    args = ap.parse_args(argv)

    if args.seconds < 60 or args.seconds > 90:
        ap.error("--seconds must be 60..90 (PR gate window)")

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    exe = args.exe
    if not exe:
        exe = os.path.join(repo_root, "out", "ci_gate_server")
        if os.name == "nt":
            exe += ".exe"
    if not os.path.isabs(exe):
        exe = os.path.join(os.getcwd(), exe)
    if not os.path.exists(exe):
        print("rss-gate: ERROR missing server binary: %s" % exe)
        return 2

    workdir = tempfile.mkdtemp(prefix="pulse-rss-gate-")
    log_path = os.path.join(workdir, "server.log")
    env = os.environ.copy()
    env["PULSE_PORT"] = str(args.port)
    env["PULSE_BIND"] = "127.0.0.1"
    env["PULSE_LOG"] = "0"
    env["PULSE_RATE_LIMIT"] = "0"
    env["PULSE_RATE_BURST"] = "0"
    env["PULSE_RATE_ROUTES"] = ""
    env["PULSE_STORE_PATH"] = os.path.join(workdir, "events.jsonl")
    env["PULSE_AUDIT_PATH"] = os.path.join(workdir, "audit.log")
    env.pop("PULSE_STORE_BACKEND", None)
    env.pop("PULSE_WS_AUTH", None)
    env.pop("PULSE_JWT_SECRET", None)

    with open(log_path, "w") as log:
        proc = subprocess.Popen(
            [exe],
            cwd=repo_root,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
        )

    try:
        if not wait_ready(proc, args.port):
            print("rss-gate: ERROR server did not become ready on 127.0.0.1:%d"
                  % args.port)
            _print_log(log_path)
            return 2
        time.sleep(0.2)
        rc = drive(
            proc,
            args.port,
            args.seconds,
            args.interval_ms / 1000.0,
            args.sample_ms / 1000.0,
            args.budget_kb,
            args.summary,
        )
        if rc != 0:
            _print_log(log_path)
        return rc
    finally:
        stop_server(proc, args.port)


def _print_log(path):
    try:
        with open(path, "r", errors="replace") as handle:
            tail = handle.read()[-4000:]
        if tail:
            print("---- server log (tail) ----")
            print(tail.rstrip())
            print("---------------------------")
    except OSError:
        pass


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 -- surface unexpected setup failures
        import traceback

        traceback.print_exc()
        sys.exit(2)
