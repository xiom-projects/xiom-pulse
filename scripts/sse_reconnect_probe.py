#!/usr/bin/env python3
# XIOM PULSE -- SSE reconnect / event-id probe (W-08, W-12).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# The existing smoke proves the chunked stream, tick count, and done event.
# This probe covers the audit's remaining reconnect gaps:
#
#   * `id:` on emitted SSE events
#   * `retry:` reconnect directive
#   * `Last-Event-ID` resume (does the server continue after the id?)
#   * client disconnect mid-stream: server stays up, releases the socket,
#     records the connection exactly once, and accepts a reconnect
#
# Fixed 2026-11-07: every event carries a monotonic `id:` equal to its seq,
# the first tick carries `retry: 3000`, and Last-Event-ID: N resumes at N+1
# (a store-less generator, so a reconnect emits the next `events` ticks).
#
# Usage:
#   python scripts/sse_reconnect_probe.py --exe out/pulse_gap_18700.exe \
#       --port 18721 [--strict] [--disconnects 8]
#
# Exit: 0 = no FAIL (GAPs allowed unless --strict), 1 = FAIL/strict GAP,
#       2 = setup error.

import argparse
import json
import socket
import sys
import time

import gap_probe_lib as lib


def open_sse(server, query, headers=None, timeout=6.0):
    target = "/api/sse?" + query
    sock = socket.create_connection(("127.0.0.1", server.port), timeout)
    sock.settimeout(timeout)
    request = (
        "GET %s HTTP/1.1\r\n"
        "Host: 127.0.0.1:%d\r\n"
        "Connection: close\r\n" % (target, server.port)
    )
    for name, value in (headers or []):
        request += "%s: %s\r\n" % (name, value)
    request += "\r\n"
    sock.sendall(request.encode("ascii"))
    head = lib.recv_until(sock, b"\r\n\r\n", 16384)
    return sock, head, target


def collect_stream(server, query, headers=None, timeout=6.0):
    sock, head, target = open_sse(server, query, headers, timeout)
    head_bytes, body = lib.split_http_response(head)
    body += lib.read_until_eof(sock, timeout)
    try:
        sock.close()
    except OSError:
        pass
    decoded, saw_zero = lib.dechunk(body)
    return {
        "target": target,
        "head": head_bytes.decode("utf-8", "replace"),
        "body": decoded.decode("utf-8", "replace"),
        "saw_zero": saw_zero,
        "events": lib.parse_sse(decoded.decode("utf-8", "replace")),
    }


def read_until_marker(server, query, marker, timeout=6.0):
    sock, head, target = open_sse(server, query, timeout=timeout)
    data = head
    deadline = time.monotonic() + timeout
    while marker not in data and time.monotonic() < deadline:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    try:
        sock.close()
    except OSError:
        pass
    return target, data


def status_ok(head):
    return head.split("\r\n", 1)[0].startswith("HTTP/1.1 200")


def ticks(result):
    return [e for e in result["events"] if e["event"] == "tick"]


def done_events(result):
    return [e for e in result["events"] if e["event"] == "done"]


def seq_values(events):
    values = []
    for ev in events:
        try:
            obj = json.loads(ev["data"])
        except (TypeError, ValueError):
            continue
        if isinstance(obj, dict) and "seq" in obj:
            values.append(obj["seq"])
    return values


def event_ids(events):
    return [ev["id"] for ev in events]


def wait_for_target_count(server, target, expected, timeout=4.0):
    deadline = time.monotonic() + timeout
    count = 0
    while time.monotonic() < deadline:
        count = 0
        for line in server.log_lines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("method") == "GET" and obj.get("target") == target:
                count += 1
        if count >= expected:
            break
        time.sleep(0.1)
    return count


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="PULSE SSE reconnect / event-id probe (W-08/W-12)")
    parser.add_argument("--exe", default="out/pulse_gap_18700.exe",
                        help="server binary (default: %(default)s)")
    parser.add_argument("--port", type=int, default=18721,
                        help="private port 18700+ (default: %(default)s)")
    parser.add_argument("--disconnects", type=int, default=8,
                        help="mid-stream disconnect cycles (default: 8)")
    parser.add_argument("--strict", action="store_true",
                        help="exit 1 when any known GAP is observed")
    args = parser.parse_args(argv)

    exe = lib.require_exe(args.exe)
    if not exe:
        return 2

    reporter = lib.Reporter("sse-reconnect-probe")
    server = lib.Server(exe, args.port, "sse-gap", read_timeout_ms=2000)
    try:
        server.start()
    except RuntimeError as exc:
        print("[FAIL] %s" % exc)
        return 2

    print("sse-reconnect-probe: %s port=%d" % (exe, args.port))
    try:
        # 1. Baseline: chunked stream, tick count, done, zero chunk.
        base = collect_stream(server, "events=3&interval_ms=5&probe=base")
        head = base["head"]
        base_ticks = ticks(base)
        if (status_ok(head) and "Content-Type: text/event-stream" in head and
                "Transfer-Encoding: chunked" in head and
                "Content-Length:" not in head and
                len(base_ticks) == 3 and len(done_events(base)) == 1 and
                base["saw_zero"]):
            reporter.ok("baseline stream",
                        "3 ticks + done + zero chunk")
        else:
            reporter.fail("baseline stream",
                          "ticks=%d done=%d zero=%s head=%r"
                          % (len(base_ticks), len(done_events(base)),
                             base["saw_zero"], head[:80]))

        # 2. Event ids.
        all_ids = event_ids(base["events"])
        tick_ids = event_ids(base_ticks)
        if tick_ids and all(i not in (None, "") for i in tick_ids):
            reporter.ok("id field", "ids=%r" % (tick_ids,))
            if all(i not in (None, "") for i in all_ids):
                reporter.ok("id field on every event", "ids=%r" % (all_ids,))
            else:
                reporter.gap("id field on every event",
                             "done/other events missing id; ids=%r"
                             % (all_ids,))
            try:
                tick_id_ints = [int(i) for i in tick_ids]
            except (TypeError, ValueError):
                tick_id_ints = []
            if (len(tick_id_ints) == len(tick_ids) and
                    all(b > a for a, b in zip(tick_id_ints,
                                              tick_id_ints[1:]))):
                reporter.ok("id monotonic", "ids=%r" % (tick_ids,))
            else:
                reporter.gap("id monotonic",
                             "tick ids not strictly increasing: ids=%r"
                             % (tick_ids,))
        else:
            reporter.gap("id field",
                         "no id: line on any tick event (ids=%r)"
                         % (all_ids,))

        # 3. retry directive.
        retries = [e["retry"] for e in base["events"]
                   if e["retry"] is not None]
        if retries:
            reporter.ok("retry directive", "retry=%r" % (retries,))
        else:
            reporter.gap("retry directive", "no retry: line in the stream")

        # 4. Last-Event-ID resume.
        resumed = collect_stream(
            server, "events=3&interval_ms=5&probe=resume",
            [("Last-Event-ID", "2")])
        resumed_ticks = ticks(resumed)
        resumed_seqs = seq_values(resumed_ticks)
        resumed_ids = event_ids(resumed_ticks)
        resumed_after_id = []
        for value in resumed_ids:
            try:
                resumed_after_id.append(int(value))
            except (TypeError, ValueError):
                pass
        expected_ids = [3, 4, 5]
        expected_seqs = [3, 4, 5]
        label = "ids=%r seqs=%r" % (resumed_ids, resumed_seqs)
        if (resumed_after_id == expected_ids and
                resumed_seqs == expected_seqs):
            reporter.ok("Last-Event-ID resume", label)
        else:
            reporter.gap("Last-Event-ID resume",
                         "expected ids/seqs %r after id 2; got %s"
                         % (expected_ids, label))

        # 5. Reconnect after a completed stream.
        again = collect_stream(server, "events=3&interval_ms=5&probe=again")
        if len(ticks(again)) == 3 and len(done_events(again)) == 1:
            reporter.ok("reconnect after completion", "3 ticks + done")
        else:
            reporter.fail("reconnect after completion",
                          "ticks=%d done=%d"
                          % (len(ticks(again)), len(done_events(again))))

        # 6. Mid-stream disconnect: alive, exactly-once log, fd release.
        disc_query = "events=50&interval_ms=60&probe=disc"
        threshold = 4
        baseline_handles = server.handle_count()
        for _ in range(args.disconnects):
            read_until_marker(server, disc_query, b"event: tick")
            time.sleep(0.03)
        time.sleep(0.7)
        alive = server.health(1.0)
        after_handles = server.handle_count()
        log_count = wait_for_target_count(
            server, "/api/sse?" + disc_query, args.disconnects)

        if alive:
            reporter.ok("disconnect: server alive",
                        "%d cycles" % args.disconnects)
        else:
            reporter.fail("disconnect: server alive",
                          "server unhealthy after %d cycles"
                          % args.disconnects)

        if log_count == args.disconnects:
            reporter.ok("disconnect: exactly-once recording",
                        "access log entries=%d" % log_count)
        else:
            reporter.fail("disconnect: exactly-once recording",
                          "expected %d access log entries, got %d"
                          % (args.disconnects, log_count))

        if baseline_handles is None or after_handles is None:
            reporter.gap("disconnect: fd release",
                         "handle count unavailable on this platform")
        else:
            delta = after_handles - baseline_handles
            detail = "handles %d -> %d (delta %d)" % (
                baseline_handles, after_handles, delta)
            if delta <= threshold:
                reporter.ok("disconnect: fd release", detail)
            else:
                reporter.fail("disconnect: fd release",
                              detail + "; threshold %d" % threshold)

        reconnect = collect_stream(
            server, "events=3&interval_ms=5&probe=after-disc")
        if len(ticks(reconnect)) == 3 and len(done_events(reconnect)) == 1:
            reporter.ok("reconnect after disconnects", "3 ticks + done")
        else:
            reporter.fail("reconnect after disconnects",
                          "ticks=%d done=%d"
                          % (len(ticks(reconnect)), len(done_events(reconnect))))
    finally:
        server.stop()

    reporter.summary()
    print("sse-reconnect-probe: server log %s" % server.log_path)
    return reporter.rc(args.strict)


if __name__ == "__main__":
    sys.exit(lib.main_guard(lambda: main()))
