// XIOM PULSE -- SSE + WebSocket stream unit (W4 realtime).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Design: docs/DESIGN-SSE-WEBSOCKET.md (fastapi/h11/fasthttp matrix).
// The Station loop owns the accepted fd and calls this unit only after the
// frozen gate (parse/quit/OPTIONS/CSRF/rate) returns action 0. The unit
// takes over the connection, writes its own head, runs the stream, and
// returns (status, payload_bytes); the loop closes the fd exactly once.
//
// Demo endpoints (not in the router/OpenAPI yet):
//   GET  /api/sse?events=5&interval_ms=50   (chunked text/event-stream)
//   GET  /api/ws                            (RFC 6455 echo)
//
// Stdlib contract: xiom.net.proto.sse_format_event, websocket.ws_*,
// socket.socket_stream_chunk/socket_recv_timeout.
module xiom.pulse.station.stream

use xiom.string;
use xiom.convert.parse;
use xiom.time;
use xiom.net.proto;
use xiom.net.socket;
use xiom.net.websocket;
use xiom.pulse.cors;
use xiom.pulse.http;
use xiom.pulse.station.config;
use xiom.pulse.station.router;

const STREAM_NONE: Int = 0;
const STREAM_SSE: Int = 1;
const STREAM_WS: Int = 2;

const MAX_SSE_EVENTS: Int = 100;
const MAX_SSE_INTERVAL_MS: Int = 5000;
const MAX_WS_PENDING: Int = 1048576;

/// stream_kind classifies a normalized target. Only GET is a stream.
/// Complexity: O(1).
pub fn stream_kind(method: Str, target: Str) -> Int {
  if method != "GET" { return STREAM_NONE; }
  let path = router.split_target(target).0;
  if path == "/api/sse" { return STREAM_SSE; }
  if path == "/api/ws" { return STREAM_WS; }
  return STREAM_NONE;
}

fn query_value(target: Str, name: Str) -> Str {
  let query = router.split_target(target).1;
  if query.len() == 0 { return ""; }
  let parts = string.str_split(query, "&");
  var i: Int = 0;
  while i < parts.len() {
    let pair = parts[i];
    let eq = string.str_index_of(pair, "=");
    if eq.is_some {
      let k = string.str_slice(pair, 0, eq.value);
      if k == name {
        return string.str_slice(pair, eq.value + 1, pair.len());
      }
    }
    i = i + 1;
  }
  return "";
}

fn query_int(target: Str, name: Str, fallback: Int, lo: Int, hi: Int) -> Int {
  let q = query_value(target, name);
  if q.len() == 0 { return fallback; }
  let p = parse.parse_int(q);
  if !p.is_ok { return fallback; }
  var v = p.value;
  if v < lo { v = lo; }
  if v > hi { v = hi; }
  return v;
}

/// sse_events returns the clamped `events` query value (default 5).
pub fn sse_events(target: Str) -> Int {
  return query_int(target, "events", 5, 1, MAX_SSE_EVENTS);
}

/// sse_interval returns the clamped `interval_ms` query value (default 50).
pub fn sse_interval(target: Str) -> Int {
  return query_int(target, "interval_ms", 50, 0, MAX_SSE_INTERVAL_MS);
}

/// sse_tick formats one demo event.
pub fn sse_tick(seq: Int) -> Str {
  return proto.sse_format_event("tick", "{\"seq\":" + seq.to_str() + "}");
}

/// sse_done formats the closing event.
pub fn sse_done(events: Int) -> Str {
  return proto.sse_format_event("done", "{\"events\":" + events.to_str() + "}");
}

/// sse_head builds the chunked event-stream response head. It starts from
/// the package builder (Date + the standard security headers) and replaces
/// the zero Content-Length with the chunked framing; CORS is inserted when
/// the request origin is allowed. Complexity: O(headers).
pub fn sse_head(origin: Str) -> Vec[UInt8] {
  var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  hs.push(("Cache-Control", "no-cache"));
  hs.push(("X-Accel-Buffering", "no"));
  let full = http.build_response_full(200, "text/event-stream; charset=utf-8", &hs, "", true);
  let text = http.bytes_to_str(&full, 0, full.len());
  var head = string.str_replace_all(text, "Content-Length: 0\r\n", "Transfer-Encoding: chunked\r\n");
  let block = cors.cors_header_block(origin);
  if block.len() > 0 {
    let he = string.str_index_of(head, "\r\n\r\n");
    if he.is_some {
      head = string.str_slice(head, 0, he.value + 2) + block + "\r\n";
    }
  }
  return http.str_to_bytes(head);
}

/// sse_stream writes the head, N tick events and the done event, then the
/// zero chunk. Returns (status, payload bytes). Status is 500 only when the
/// head could not be sent; after the head, 200 is already on the wire.
/// Complexity: O(events).
pub fn sse_stream(fd: Int, req: &PulseRequest) -> (Int, Int) {
  let _ = socket.socket_set_nonblocking(fd, false);
  let _ = socket.socket_set_timeout(fd, config.cfg_write_timeout());
  let head = sse_head(http.header_get(req, "origin"));
  let wr = socket.socket_send_all(fd, &head);
  if !wr.is_ok { return (500, 0); }
  let events = sse_events(req.target);
  let interval = sse_interval(req.target);
  var sent: Int = 0;
  var n: Int = 1;
  while n <= events {
    let payload = sse_tick(n);
    let pb = http.str_to_bytes(payload);
    let r = socket.socket_stream_chunk(fd, &pb);
    if !r.is_ok { return (200, sent); }
    sent = sent + pb.len();
    if interval > 0 { time.sleep_ms(interval); }
    n = n + 1;
  }
  let done = sse_done(events);
  let db = http.str_to_bytes(done);
  let dr = socket.socket_stream_chunk(fd, &db);
  if dr.is_ok { sent = sent + db.len(); }
  let _ = socket.socket_stream_end(fd);
  return (200, sent);
}

/// ws_check validates the RFC 6455 upgrade request fields.
/// Returns "" when valid; otherwise a human-readable reason.
/// Complexity: O(headers).
pub fn ws_check(method: Str, http_version: Str, upgrade: Str, connection: Str, ws_version: Str, key: Str) -> Str {
  if method != "GET" { return "WebSocket requires GET"; }
  if http_version != "HTTP/1.1" { return "WebSocket requires HTTP/1.1"; }
  if !string.str_contains(string.str_lower(upgrade), "websocket") {
    return "missing Upgrade: websocket";
  }
  if !string.str_contains(string.str_lower(connection), "upgrade") {
    return "missing Connection: Upgrade";
  }
  if string.str_trim(ws_version) != "13" { return "unsupported Sec-WebSocket-Version"; }
  if key.len() == 0 { return "missing Sec-WebSocket-Key"; }
  return "";
}

/// ws_check_req extracts the header fields and validates them. It returns
/// "" when valid, otherwise the reason. Complexity: O(request).
pub fn ws_check_req(raw: &Vec[UInt8], req: &PulseRequest) -> Str {
  let raw_str = http.bytes_to_str(raw, 0, raw.len());
  let key = websocket.ws_request_key(raw_str);
  if !key.is_ok { return key.error; }
  return ws_check(req.method, req.version, http.header_get(req, "upgrade"), http.header_get(req, "connection"), http.header_get(req, "sec-websocket-version"), key.value);
}

fn origin_scheme(origin: Str) -> Str {
  let idx = string.str_index_of(origin, "://");
  if idx.is_none { return ""; }
  return string.str_lower(string.str_slice(origin, 0, idx.value));
}

fn origin_host(origin: Str) -> Str {
  let idx = string.str_index_of(origin, "://");
  if idx.is_none { return ""; }
  let rest = string.str_slice(origin, idx.value + 3, origin.len());
  let slash = string.str_index_of(rest, "/");
  if slash.is_some { return string.str_slice(rest, 0, slash.value); }
  return rest;
}

fn strip_default_port(hostport: Str, scheme: Str) -> Str {
  let lower = string.str_lower(hostport);
  if scheme == "https" && string.str_ends_with(lower, ":443") {
    return string.str_slice(lower, 0, lower.len() - 4);
  }
  if scheme == "http" && string.str_ends_with(lower, ":80") {
    return string.str_slice(lower, 0, lower.len() - 3);
  }
  return lower;
}

/// ws_origin_check enforces a browser same-origin default:
///   * no Origin (non-browser client) -> allow;
///   * Origin host:port equals Host (default ports normalized) -> allow;
///   * Origin is in PULSE_CORS_ORIGIN (including `*`) -> allow;
///   * anything else -> reject (403). Auth remains the application's job.
/// Complexity: O(headers).
pub fn ws_origin_check(origin: Str, host: Str) -> Str {
  if origin.len() == 0 { return ""; }
  let scheme = origin_scheme(origin);
  let oh = origin_host(origin);
  if scheme.len() == 0 || oh.len() == 0 { return "invalid Origin header"; }
  if host.len() > 0 {
    let hh = strip_default_port(host, scheme);
    let ohh = strip_default_port(oh, scheme);
    if ohh == hh { return ""; }
  }
  let allowed = cors.cors_allow_origin(origin);
  if allowed.len() > 0 { return ""; }
  return "WebSocket origin not allowed";
}

/// ws_origin_check_req applies ws_origin_check to the request headers.
pub fn ws_origin_check_req(req: &PulseRequest) -> Str {
  return ws_origin_check(http.header_get(req, "origin"), http.header_get(req, "host"));
}

fn ws_send(fd: Int, opcode: Int, payload: &Vec[UInt8]) -> Bool {
  let frame = websocket.ws_frame_encode(opcode, payload, false);
  let r = socket.socket_send_all(fd, &frame);
  return r.is_ok;
}

fn ws_close(fd: Int, code: Int, reason: Str) -> Bool {
  var payload: Vec[UInt8] = Vec[UInt8].new();
  payload.push(((code >> 8) & 0xFF) as UInt8);
  payload.push((code & 0xFF) as UInt8);
  var i: Int = 0;
  while i < reason.len() {
    payload.push(reason.byte_at(i));
    i = i + 1;
  }
  return ws_send(fd, 8, &payload);
}

fn drop_prefix(buf: &Vec[UInt8], consumed: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = consumed;
  while i < buf.len() {
    out.push(buf[i]);
    i = i + 1;
  }
  return out;
}

fn push_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i: Int = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

/// ws_stream performs the 101 handshake and the echo frame loop. Returns
/// (101, echoed payload bytes) after a clean close; (500, 0) only when the
/// handshake could not be sent. Complexity: O(frames * payload).
pub fn ws_stream(fd: Int, raw: &Vec[UInt8], _req: &PulseRequest) -> (Int, Int) {
  let raw_str = http.bytes_to_str(raw, 0, raw.len());
  let key = websocket.ws_request_key(raw_str);
  if !key.is_ok { return (500, 0); }
  let response = websocket.ws_handshake_response(key.value);
  let rb = http.str_to_bytes(response);
  let _ = socket.socket_set_nonblocking(fd, false);
  let _ = socket.socket_set_timeout(fd, config.cfg_write_timeout());
  let wr = socket.socket_send_all(fd, &rb);
  if !wr.is_ok { return (500, 0); }
  let _ = socket.socket_set_timeout(fd, config.cfg_read_timeout());
  var buf: Vec[UInt8] = Vec[UInt8].new();
  var echoed: Int = 0;
  var open: Bool = true;
  while open {
    let parsed = websocket.ws_frame_take(&buf);
    if parsed.is_ok {
      let frame = parsed.value.0;
      let consumed = parsed.value.1;
      buf = drop_prefix(&buf, consumed);
      let op = frame.opcode;
      if op >= 8 {
        if !frame.fin || frame.payload.len() > 125 {
          let _ = ws_close(fd, 1002, "bad control frame");
          open = false;
        } elif op == 8 {
          let _ = ws_send(fd, 8, &frame.payload);
          open = false;
        } elif op == 9 {
          if !ws_send(fd, 10, &frame.payload) { open = false; }
        } elif op == 10 {
          // pong: no response
        } else {
          let _ = ws_close(fd, 1003, "unsupported opcode");
          open = false;
        }
      } elif !frame.masked {
        let _ = ws_close(fd, 1002, "client frames must be masked");
        open = false;
      } elif !frame.fin || op == 0 {
        let _ = ws_close(fd, 1003, "fragmentation unsupported");
        open = false;
      } elif op == 1 || op == 2 {
        if !ws_send(fd, op, &frame.payload) {
          open = false;
        } else {
          echoed = echoed + frame.payload.len();
        }
      } else {
        let _ = ws_close(fd, 1003, "unsupported opcode");
        open = false;
      }
    } else {
      if buf.len() >= MAX_WS_PENDING {
        let _ = ws_close(fd, 1009, "frame too large");
        open = false;
      } else {
        let rr = socket.socket_recv_timeout(fd, 65536, config.cfg_read_timeout());
        if !rr.is_ok {
          let _ = ws_close(fd, 1001, "idle timeout");
          open = false;
        } elif rr.value.len() == 0 {
          open = false;
        } else {
          push_bytes(&mut buf, &rr.value);
        }
      }
    }
  }
  return (101, echoed);
}
