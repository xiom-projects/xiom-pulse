#!/usr/bin/env python3
# XIOM PULSE -- WebSocket negative-frame corpus over raw TCP (W-09).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# The existing stream smoke covers the happy path and one orphan
# continuation. This corpus exercises the RFC 6455 failure modes the audit
# lists as untested:
#
#   * control frame with payload > 125          -> close 1002
#   * fragmented control frame                  -> close 1002
#   * reserved bits (RSV1)                      -> close 1002
#   * unmasked client frame                     -> close 1002
#   * invalid UTF-8 text                        -> close 1007
#   * bad close code (1005, 999, 1-byte body)   -> close 1002
#   * malformed/non-minimal length encodings    -> close 1002
#   * 64-bit length with the MSB set            -> close/error, never crash
#
# The last case currently reaches a negative consumed count in the stdlib
# frame parser and crashes the Windows server with 0xC0000005. The probe
# reports that as FAIL and restarts the private server so every case is
# independently observed.
#
# Usage:
#   python scripts/ws_negative_corpus.py --exe out/pulse_gap_18700.exe \
#       --port 18720 [--strict]
#
# Exit: 0 = no FAIL (GAPs allowed unless --strict), 1 = FAIL/strict GAP,
#       2 = setup error.

import argparse
import base64
import hashlib
import socket
import sys
import time

import gap_probe_lib as lib

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_KEY = "dGhlIHNhbXBsZSBub25jZQ=="


class Case:
    def __init__(self, name, frame, expected_codes=None, expect_closed=False,
                 read_timeout=2.0, note=""):
        self.name = name
        self.frame = frame
        self.expected_codes = expected_codes or []
        self.expect_closed = expect_closed
        self.read_timeout = read_timeout
        self.note = note


def ws_accept(key):
    digest = hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def build_frame(opcode, payload=b"", fin=True, rsv=0, masked=True,
                length_form=None, declared_len=None,
                mask=b"\x11\x22\x33\x44"):
    """Build a client frame, including deliberately malformed lengths."""
    b0 = ((0x80 if fin else 0x00) | ((rsv & 0x07) << 4) |
          (opcode & 0x0F)) & 0xFF
    declared = len(payload) if declared_len is None else declared_len
    form = length_form
    if form is None:
        if declared < 126:
            form = 7
        elif declared < 65536:
            form = 16
        else:
            form = 64
    if form == 7:
        header = bytes([b0, (0x80 if masked else 0x00) | declared])
    elif form == 16:
        header = (bytes([b0, (0x80 if masked else 0x00) | 126]) +
                  declared.to_bytes(2, "big"))
    else:
        header = (bytes([b0, (0x80 if masked else 0x00) | 127]) +
                  declared.to_bytes(8, "big"))
    if masked:
        header += mask + bytes(
            payload[i] ^ mask[i % 4] for i in range(len(payload)))
    else:
        header += payload
    return header


def do_handshake(server, timeout):
    sock = socket.create_connection(("127.0.0.1", server.port), timeout)
    sock.settimeout(timeout)
    request = (
        "GET /api/ws HTTP/1.1\r\n"
        "Host: 127.0.0.1:%d\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Key: %s\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n" % (server.port, WS_KEY)
    )
    sock.sendall(request.encode("ascii"))
    head = lib.recv_until(sock, b"\r\n\r\n", 8192)
    text = head.decode("utf-8", "replace")
    if "HTTP/1.1 101" not in text:
        sock.close()
        raise RuntimeError("handshake failed: %s" % text.split("\r\n", 1)[0])
    expected = "Sec-WebSocket-Accept: " + ws_accept(WS_KEY)
    if expected not in text:
        sock.close()
        raise RuntimeError("handshake accept mismatch")
    return sock


def read_frame(sock, timeout):
    sock.settimeout(timeout)
    try:
        first = lib.recv_exact(sock, 1)[0]
        second = lib.recv_exact(sock, 1)[0]
    except EOFError:
        return ("eof", None, b"")
    except socket.timeout:
        return ("timeout", None, b"")
    except OSError:
        return ("eof", None, b"")

    opcode = first & 0x0F
    masked = (second & 0x80) != 0
    length = second & 0x7F
    try:
        if length == 126:
            length = int.from_bytes(lib.recv_exact(sock, 2), "big")
        elif length == 127:
            length = int.from_bytes(lib.recv_exact(sock, 8), "big")
        mask = lib.recv_exact(sock, 4) if masked else b""
        if length > 1048576:
            return ("frame_header", opcode, b"<oversize>")
        payload = lib.recv_exact(sock, length) if length else b""
    except EOFError:
        return ("eof", None, b"")
    except socket.timeout:
        return ("timeout", None, b"")
    except OSError:
        return ("eof", None, b"")
    if masked:
        payload = bytes(payload[i] ^ mask[i % 4] for i in range(len(payload)))
    return ("frame", opcode, payload)


def read_outcome(sock, timeout):
    kind, opcode, payload = read_frame(sock, timeout)
    if kind != "frame":
        return (kind, None, payload)
    if opcode == 8:
        code = None
        if len(payload) >= 2:
            code = (payload[0] << 8) | payload[1]
        return ("close", code, payload[2:])
    return ("frame", opcode, payload)


def describe(outcome):
    kind, code, payload = outcome
    if kind == "close":
        return "close code=%s reason=%r" % (code, payload[:80])
    if kind == "frame":
        return "frame opcode=%s payload=%r" % (code, payload[:80])
    return kind


def case_passed(case, outcome):
    kind, code, _payload = outcome
    if case.expect_closed:
        return kind in ("close", "eof")
    if kind == "close" and code in case.expected_codes:
        return True
    return False


def case_detail(case):
    if case.expect_closed:
        return "expected close or EOF"
    return "expected close %s" % (",".join(str(c) for c in case.expected_codes))


def build_cases():
    return [
        Case("control_too_long",
             build_frame(9, b"p" * 126), [1002]),
        Case("control_fragmented",
             build_frame(9, b"", fin=False), [1002]),
        Case("reserved_rsv1_text",
             build_frame(1, b"a", rsv=4), [1002]),
        Case("reserved_rsv1_control",
             build_frame(9, b"", rsv=4), [1002]),
        Case("client_unmasked",
             build_frame(1, b"a", masked=False), [1002]),
        Case("invalid_utf8_text",
             build_frame(1, b"\xff\xfe"), [1007]),
        Case("bad_close_code_1005",
             build_frame(8, b"\x03\xed"), [1002]),
        Case("bad_close_code_999",
             build_frame(8, b"\x03\xe7"), [1002]),
        Case("close_payload_len_1",
             build_frame(8, b"\x03"), [1002]),
        Case("length_126_nonminimal",
             build_frame(1, b"a", length_form=16, declared_len=1), [1002]),
        Case("length_127_nonminimal",
             build_frame(1, b"a", length_form=64, declared_len=1), [1002]),
        Case("length_127_zero",
             build_frame(1, b"", length_form=64, declared_len=0), [1002]),
        Case("length_127_huge",
             build_frame(1, b"", length_form=64, declared_len=(1 << 40)),
             [1002, 1009], read_timeout=2.5,
             note="declared oversize but no payload; 1001 idle is a gap"),
        Case("length_127_msb_crash",
             build_frame(1, b"", length_form=64, declared_len=(1 << 63)),
             expect_closed=True, read_timeout=2.0,
             note="64-bit length with the MSB set"),
    ]


def wait_case_state(server, timeout=3.0):
    """Return (state, exit_code): healthy, exited, or hung.

    The MSB-length frame can leave the process alive-but-unresponsive for
    a moment before the access violation terminates it; poll both states so
    the probe reports the real exit code instead of a generic timeout.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not server.alive():
            return ("exited", server.poll())
        if server.health(0.4):
            return ("healthy", None)
        time.sleep(0.1)
    return ("hung", server.poll())


def run_case(server, case, reporter):
    try:
        sock = do_handshake(server, 2.0)
    except (OSError, RuntimeError) as exc:
        reporter.fail(case.name + " handshake", str(exc))
        return False

    try:
        sock.sendall(case.frame)
        outcome = read_outcome(sock, case.read_timeout)
    except (OSError, socket.timeout) as exc:
        outcome = ("transport", None, str(exc))
    finally:
        try:
            sock.close()
        except OSError:
            pass

    state, rc = wait_case_state(server)
    if state != "healthy":
        if state == "exited":
            reporter.fail(case.name + " no-crash",
                          "server exited rc=%s; got %s"
                          % (lib.exit_code_text(rc), describe(outcome)))
            server.restart()
            reporter.note("server restarted after crash",
                          "127.0.0.1:%d" % server.port)
        else:
            reporter.fail(case.name + " no-crash",
                          "server hung/unresponsive (rc=%s); got %s"
                          % (lib.exit_code_text(rc), describe(outcome)))
            server.restart()
            reporter.note("server restarted after hang",
                          "127.0.0.1:%d" % server.port)
        return False

    if case_passed(case, outcome):
        reporter.ok(case.name, describe(outcome))
    else:
        detail = "%s; got %s" % (case_detail(case), describe(outcome))
        if case.note:
            detail += "; " + case.note
        reporter.gap(case.name, detail)
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="PULSE WebSocket negative-frame corpus (W-09)")
    parser.add_argument("--exe", default="out/pulse_gap_18700.exe",
                        help="server binary (default: %(default)s)")
    parser.add_argument("--port", type=int, default=18720,
                        help="private port 18700+ (default: %(default)s)")
    parser.add_argument("--strict", action="store_true",
                        help="exit 1 when any known GAP is observed")
    args = parser.parse_args(argv)

    exe = lib.require_exe(args.exe)
    if not exe:
        return 2

    reporter = lib.Reporter("ws-negative-corpus")
    server = lib.Server(exe, args.port, "wsneg", read_timeout_ms=1500)
    try:
        server.start()
    except RuntimeError as exc:
        print("[FAIL] %s" % exc)
        return 2

    print("ws-negative-corpus: %s port=%d" % (exe, args.port))
    try:
        for case in build_cases():
            if not server.health(0.75):
                if not server.alive():
                    reporter.fail(case.name, "server not running before case")
                    server.restart()
            run_case(server, case, reporter)
    finally:
        server.stop()

    reporter.summary()
    print("ws-negative-corpus: server log %s" % server.log_path)
    return reporter.rc(args.strict)


if __name__ == "__main__":
    sys.exit(lib.main_guard(lambda: main()))
