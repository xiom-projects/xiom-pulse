#!/usr/bin/env python3
# XIOM PULSE -- live SSE + WebSocket smoke client.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Run against a live PULSE server (the wrappers start/stop it):
#   python scripts/stream_smoke.py --port 18097
#
# Checks: SSE 200 + text/event-stream + chunked + 3 tick + done + zero
# chunk; WS 101 + the RFC 6455 example accept; masked text echo; ping ->
# pong; close echo; and the 426 path for a plain GET /api/ws.

import argparse
import base64
import hashlib
import socket
import sys

PASS = 0
FAIL = 0


def check(name, ok):
    global PASS, FAIL
    if ok:
        PASS += 1
        print("[PASS] " + name)
    else:
        FAIL += 1
        print("[FAIL] " + name)


def recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise EOFError("eof")
        buf += chunk
    return buf


def recv_until(s, marker, limit):
    buf = b""
    while marker not in buf and len(buf) < limit:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf


def read_all(s):
    buf = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    return buf


def sse(host, port, timeout):
    s = socket.create_connection((host, port), timeout)
    s.settimeout(timeout)
    s.sendall(b"GET /api/sse?events=3&interval_ms=10 HTTP/1.1\r\nHost: smoke\r\nConnection: close\r\n\r\n")
    data = read_all(s)
    s.close()
    text = data.decode("utf-8", "replace")
    check("sse status 200", "HTTP/1.1 200" in text)
    check("sse content type", "Content-Type: text/event-stream" in text)
    check("sse chunked", "Transfer-Encoding: chunked" in text)
    check("sse no content-length", "Content-Length:" not in text)
    check("sse tick x3", text.count("event: tick") == 3)
    check("sse done", text.count("event: done") == 1)
    check("sse zero chunk", "\r\n0\r\n\r\n" in text)
    return text


def ws_frame(opcode, payload, fin=True):
    mask = b"\x11\x22\x33\x44"
    n = len(payload)
    head = bytes([(0x80 if fin else 0x00) | opcode])
    if n < 126:
        head += bytes([0x80 | n])
    elif n < 65536:
        head += bytes([0x80 | 126]) + n.to_bytes(2, "big")
    else:
        head += bytes([0x80 | 127]) + n.to_bytes(8, "big")
    masked = bytes(payload[i] ^ mask[i % 4] for i in range(n))
    return head + mask + masked


def read_frame(s):
    b0 = recv_exact(s, 1)[0]
    b1 = recv_exact(s, 1)[0]
    opcode = b0 & 0x0F
    n = b1 & 0x7F
    if n == 126:
        n = int.from_bytes(recv_exact(s, 2), "big")
    elif n == 127:
        n = int.from_bytes(recv_exact(s, 8), "big")
    if b1 & 0x80:
        mask = recv_exact(s, 4)
        payload = bytes(recv_exact(s, n)[i] ^ mask[i % 4] for i in range(n))
    else:
        payload = recv_exact(s, n)
    return opcode, payload


def websocket(host, port, timeout):
    key = "dGhlIHNhbXBsZSBub25jZQ=="
    accept = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
    ).decode()
    s = socket.create_connection((host, port), timeout)
    s.settimeout(timeout)
    origin = "http://{}:{}".format(host, port)
    req = (
        f"GET /api/ws HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Origin: {origin}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    s.sendall(req.encode())
    head = recv_until(s, b"\r\n\r\n", 4096)
    text = head.decode("utf-8", "replace")
    check("ws status 101", "HTTP/1.1 101" in text)
    check("ws upgrade", "Upgrade: websocket" in text)
    check("ws accept key", ("Sec-WebSocket-Accept: " + accept) in text)
    s.sendall(ws_frame(1, b"hello"))
    op, payload = read_frame(s)
    check("ws text echo", op == 1 and payload == b"hello")
    s.sendall(ws_frame(1, b"hel", False))
    s.sendall(ws_frame(9, b"p"))
    op, payload = read_frame(s)
    check("ws ping/pong", op == 10 and payload == b"p")
    s.sendall(ws_frame(0, b"lo", True))
    op, payload = read_frame(s)
    check("ws fragmented echo", op == 1 and payload == b"hello")
    s.sendall(ws_frame(8, b"\x03\xe8bye"))
    op, payload = read_frame(s)
    check("ws close echo", op == 8)
    s.close()
    return text


def bad_fragment(host, port, timeout):
    key = "dGhlIHNhbXBsZSBub25jZQ=="
    origin = "http://{}:{}".format(host, port)
    s = socket.create_connection((host, port), timeout)
    s.settimeout(timeout)
    req = (
        f"GET /api/ws HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Origin: {origin}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    s.sendall(req.encode())
    _ = recv_until(s, b"\r\n\r\n", 4096)
    s.sendall(ws_frame(0, b"x", True))
    op, payload = read_frame(s)
    check("ws orphan continuation close", op == 8)
    check("ws orphan continuation 1002", payload[:2] == b"\x03\xea")
    s.close()


def bad_origin(host, port, timeout):
    key = "dGhlIHNhbXBsZSBub25jZQ=="
    s = socket.create_connection((host, port), timeout)
    s.settimeout(timeout)
    req = (
        f"GET /api/ws HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Origin: https://evil.example\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    s.sendall(req.encode())
    data = read_all(s)
    s.close()
    text = data.decode("utf-8", "replace")
    check("ws bad origin 403", "HTTP/1.1 403" in text)
    check("ws bad origin no 101", "101 Switching Protocols" not in text)


def bad_upgrade(host, port, timeout):
    s = socket.create_connection((host, port), timeout)
    s.settimeout(timeout)
    s.sendall(b"GET /api/ws HTTP/1.1\r\nHost: smoke\r\nConnection: close\r\n\r\n")
    data = read_all(s)
    s.close()
    text = data.decode("utf-8", "replace")
    check("ws plain GET 426", "HTTP/1.1 426" in text)
    check("ws 426 advertises version", "Sec-WebSocket-Version: 13" in text)
    return text


def main():
    global PASS, FAIL
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=18097)
    ap.add_argument("--timeout", type=float, default=5.0)
    args = ap.parse_args()
    try:
        sse(args.host, args.port, args.timeout)
        websocket(args.host, args.port, args.timeout)
        bad_fragment(args.host, args.port, args.timeout)
        bad_origin(args.host, args.port, args.timeout)
        bad_upgrade(args.host, args.port, args.timeout)
    except Exception as exc:  # noqa: BLE001 -- smoke client reports the cause
        FAIL += 1
        print("[FAIL] exception: {}".format(exc))
    print("stream-smoke: pass={} fail={}".format(PASS, FAIL))
    if FAIL == 0:
        print("stream-smoke: GREEN")
        return 0
    print("stream-smoke: RED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
