<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: SSE + WebSocket units (W4 realtime)

Status: **IMPLEMENTED (2026-10-20, session 23)** -- `src/stream.xi`
(`xiom.pulse.station.stream`) plus the `/api/sse` and `/api/ws` live
endpoints. The serving loop keeps its accepted fd and hands it to the
stream unit after the frozen gate; the gate order is unchanged. Tests:
`tests/test_stream.xi` (pure) + `scripts/stream_smoke.*` (live, both
platforms).

References: `E:\repos\fastapi` (MIT; `fastapi/sse.py`,
`fastapi/routing.py`), `E:\repos\h11` (MIT; `h11/_connection.py`,
`h11/_state.py`), `E:\repos\fasthttp` (MIT; `doc.go` Upgrade/Hijack and
deadline model), and the delivered stdlib contract
(`E:\xiom-lang\stdlib\xiom\net\proto.xi`,
`E:\xiom-lang\stdlib\xiom\net\websocket.xi`,
`E:\xiom-lang\stdlib\xiom\net\socket.xi`).

## 1. Problem

PULSE has the wire primitives but no server-side realtime surface:

- SSE needs a `text/event-stream` response **without** `Content-Length`,
  written as chunks over the accepted connection while the request is
  still open.
- WebSocket needs a 101 upgrade and then raw frame I/O on the same fd,
  outside the normal request/response cycle.
- The existing Station loop always builds a complete `HandlerOut` and
  closes or reuses the connection; a handler cannot own the fd.
- The gate (parse -> quit -> OPTIONS -> CSRF -> global + per-route rate)
  must still run before either stream is opened.

## 2. Reference matrix (crawled, not recalled)

| Reference | Mechanism | What PULSE needs | XIOM conversion |
|---|---|---|---|
| `fastapi/sse.py:20-33` `EventSourceResponse` | a `StreamingResponse` subclass with `media_type = "text/event-stream"` and an async iterator | one long-lived response whose body arrives event by event | `socket_stream_chunk()` per formatted event + `socket_stream_end()`; no `Content-Length` |
| `fastapi/routing.py:410` | detects an SSE response class and keeps the streaming path | a route-level marker for "this is a stream" | `stream_kind()` checks the startup registry before dispatch; user handler registration is a follow-up |
| `fastapi/sse.py:142-...` (keep-alive pings) | comments/pings keep proxies and clients alive | a documented heartbeat/keep-alive shape | the demo closes after N events; the format leaves `: comment` support to the caller |
| `h11/_connection.py:261-262` | `101 InformationalResponse` switches the client state machine to `SWITCH_UPGRADE` | 101 is a protocol switch, not a 200 with a body | `ws_handshake_response()` sends the 101 + `Upgrade`/`Connection`/`Accept` lines first; no HTTP body follows |
| `h11/_state.py:217` | `SWITCHED_PROTOCOL` is a terminal state for HTTP | the HTTP loop must not parse a body/keep-alive after the upgrade | the Station loop sets `conn_open = false` after the frame loop; raw frames never reach the HTTP parser |
| `h11/_connection.py:412-438` | `ConnectionClosed` is sticky and ends the cycle | EOF/timeout is a clean close, not another request | `socket_recv_timeout` EOF/timeout ends the frame loop and closes the fd |
| `fasthttp/doc.go:11` | `Connection: Upgrade` support via `RequestCtx.Hijack` | the accepted fd is handed to a different protocol loop | `stream.ws_stream(fd, ...)` owns the fd after the 101 |
| `xiom.net.proto.sse_format_event` (132-143) | `event:` + `data:` lines + blank line | canonical SSE framing | used directly; the demo emits `event: tick` and `event: done` |
| `xiom.net.websocket.ws_accept_key` / `ws_handshake_response` (269/331) | RFC 6455 accept hash + 101 response | server handshake without reimplementing SHA-1/base64 | called directly; the client key is parsed by `ws_request_key` |
| `xiom.net.websocket.ws_frame_take` / `ws_frame_encode` (464/387) | incremental frame decode (returns consumed bytes) + encode | frame loop with a pending buffer, masking rules, no allocation of a client connection | server loop keeps `Vec[UInt8]` pending bytes; client frames must be masked; server frames are unmasked |
| `xiom.net.socket.socket_stream_chunk` / `socket_chunked_end` (329/310) | chunked transfer writer + terminator | SSE body framing | used after the head is rewritten from `Content-Length: 0` to `Transfer-Encoding: chunked` |

## 3. Surface decisions

### S1. Streams take over the accepted fd

The Station loop already owns `client` (the accepted fd) and the raw
request. After the gate returns action 0, `stream_kind()` checks the
normalized target:

- `GET /api/sse` -> `sse_stream(client, req)`
- `GET /api/ws` with valid upgrade headers -> `ws_stream(client, raw)`
- `GET /api/ws` without a valid upgrade -> 426 Upgrade Required

The stream unit writes its own head, owns the connection until done, and
returns `(status, payload_bytes)`. The loop then records metrics/access
log and sets `conn_open = false`; the fd is closed once by the loop.

Routes live in a startup registry (`stream.init()` / `stream.register()`):
only GET and the built-in SSE/WS kinds are accepted, duplicates and
invalid paths fail closed, and the `routes` CLI prints the registered
stream paths alongside the router table. Per-route rate policy applies to
the registered literal path after the global bucket
(`PULSE_RATE_ROUTES="GET /api/sse=1/1"`). OpenAPI stays unchanged; user
handler registration is the remaining follow-up (the registry is the
seam).

### S2. SSE response

- `Content-Type: text/event-stream; charset=utf-8`
- `Cache-Control: no-cache`, `X-Accel-Buffering: no`
- `Transfer-Encoding: chunked` (the head is built through the package's
  response builder so the standard security headers and Date are kept,
  then `Content-Length: 0` is replaced by the chunked header)
- each `proto.sse_format_event("tick", {"seq":N})` is one chunk; a final
  `event: done` ends the demo; `socket_stream_end()` writes `0\r\n\r\n`
- query knobs: `events` (default 5, clamped 1..100) and `interval_ms`
  (default 50, clamped 0..5000)

### S3. WebSocket handshake and frame rules

- require `GET`, HTTP/1.1, `Upgrade: websocket` (token),
  `Connection: Upgrade` (token), `Sec-WebSocket-Version: 13`, and a
  non-empty `Sec-WebSocket-Key`; otherwise 426 with
  `Sec-WebSocket-Version: 13`
- 101 response from `ws_handshake_response()`; then raw frames
- client frames **must** be masked; unmasked -> close 1002
- text (1) and binary (2) echo; ping (9) -> pong (10); pong ignored;
  close (8) echoed with the same payload
- control frames must be FIN and <= 125 bytes (1002 otherwise)
- fragmented data messages are reassembled: a data frame with
  `fin = false` opens a message, continuation frames append, `fin = true`
  completes it (echoed as one frame with the original opcode); control
  frames may interleave; an unexpected continuation or a new data frame
  during fragmentation closes 1002; a reassembled message over 1 MiB
  closes 1009
- max pending frame 1 MiB -> close 1009
- idle read timeout (`PULSE_READ_TIMEOUT`) -> close 1001
- Origin policy: no `Origin` (non-browser client) is allowed; a browser
  `Origin` must match `Host` (default ports normalized) or be in the
  `PULSE_CORS_ORIGIN` allowlist; otherwise 403. This is a browser
  same-origin guard, not authentication -- user-data routes still need
  their own auth.
- no `wss://` in-process: TLS stays at the front proxy (W2)

### S4. Gate and metrics

The stream branch runs only after `gate_request()` returns action 0, so
CSRF/OPTIONS/global rate (and per-route policy for router and registered
stream routes) run
first. SSE/WS are GETs, so audit stays off. Metrics record 200 (SSE) or
101 (WS) and the payload bytes; the access-log duration is the stream
lifetime. The global bucket is still per request, not per event.

### S5. Timeouts

SSE writes use `PULSE_WRITE_TIMEOUT`; WS reads use
`PULSE_READ_TIMEOUT` via `socket_recv_timeout`. The socket is switched
back to blocking mode for the stream helpers; the loop's own `send_all`
deadline path is not reused.

## 4. Tests

`tests/test_stream.xi` (pure):
- `stream_kind` accepts only registered GET routes (`/api/sse`, `/api/ws`,
  plus a custom test path); other methods/paths return 0
- registry: idempotent init, duplicate/invalid path/method/kind rejected,
  `route_path` for policy keys, `routes_text` includes the built-ins
- SSE query clamps (events 1..100, interval 0..5000) and defaults
- SSE head/event formatting (content type, chunked header, no
  Content-Length, `event:`/`data:` shape)
- WS header validation: valid handshake, missing key, wrong version,
  HTTP/1.0, missing `Connection: Upgrade`
- WS Origin policy: absent, same-origin, default ports, non-default port,
  cross-origin rejection, `null`, allowlist and wildcard

`scripts/stream_smoke.ps1` / `.sh` (live, both platforms):
- start the product server, `GET /api/sse?events=3&interval_ms=10`,
  verify 200 + `text/event-stream` + chunked + 3 `event: tick` + 1
  `event: done`
- open a raw socket to `/api/ws` with a same-origin `Origin`, send the
  RFC 6455 example key, verify 101 +
  `Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`
- send masked text `hello`, expect the unmasked echo; ping -> pong;
  close -> close
- send a fragmented `hel` + `lo` with an interleaved ping and expect one
  echoed text frame; an unexpected continuation gets close 1002
- a cross-origin handshake gets 403, and a plain GET gets 426

## 5. Out of scope (explicit)

- User-supplied stream handlers: the startup registry and built-in kinds
  exist, but storing function values in a `Vec` is blocked by the compiler
  defect `REL-20261021-1703-pulse` (indirect call infers `()`, Vec storage
  emits invalid IR). Re-test on the next pin.
- SSE event bus/subscription sources (a demo tick source is used).
- WebSocket permessage-deflate and subprotocol negotiation.
- `wss://` in-process (TLS remains the front proxy; W2 owns native TLS).
- WebSocket authentication: the v1 endpoint is an echo demo with no data
  access. The Origin policy (same-origin default + CORS allowlist) is
  enforced, but a user-data endpoint MUST add its own auth before it is
  exposed; that is not implied by this unit.
- Per-event rate limiting and backpressure beyond the socket timeout.
