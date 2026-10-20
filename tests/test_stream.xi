// XIOM PULSE -- SSE + WebSocket unit tests (pure surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The live handshake/frame/chunk path is scripts/stream_smoke.*; this gate
// pins classification, query clamps, SSE formatting/head, and upgrade
// validation without opening a socket.
module test_stream

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.pulse.http;
use xiom.pulse.station.stream;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn bytes_text(b: &Vec[UInt8]) -> Str {
  return http.bytes_to_str(b, 0, b.len());
}

pub fn main() -> Int {
  var f: Int = 0;

  // Classification: only GET /api/sse and GET /api/ws are streams.
  f = f + check("kind sse", stream.stream_kind("GET", "/api/sse") == 1);
  f = f + check("kind sse query", stream.stream_kind("GET", "/api/sse?events=2") == 1);
  f = f + check("kind ws", stream.stream_kind("GET", "/api/ws") == 2);
  f = f + check("kind ws query", stream.stream_kind("GET", "/api/ws?x=1") == 2);
  f = f + check("kind other", stream.stream_kind("GET", "/api/version") == 0);
  f = f + check("kind post", stream.stream_kind("POST", "/api/ws") == 0);
  f = f + check("kind head", stream.stream_kind("HEAD", "/api/sse") == 0);

  // Query clamps and defaults.
  f = f + check("events default", stream.sse_events("/api/sse") == 5);
  f = f + check("events explicit", stream.sse_events("/api/sse?events=3") == 3);
  f = f + check("events low clamp", stream.sse_events("/api/sse?events=0") == 1);
  f = f + check("events high clamp", stream.sse_events("/api/sse?events=999") == 100);
  f = f + check("events bad -> default", stream.sse_events("/api/sse?events=nope") == 5);
  f = f + check("interval default", stream.sse_interval("/api/sse") == 50);
  f = f + check("interval zero", stream.sse_interval("/api/sse?interval_ms=0") == 0);
  f = f + check("interval high clamp", stream.sse_interval("/api/sse?interval_ms=99999") == 5000);

  // SSE framing.
  let tick = stream.sse_tick(2);
  f = f + check("tick event line", string.str_contains(tick, "event: tick\n"));
  f = f + check("tick data line", string.str_contains(tick, "data: {\"seq\":2}\n"));
  f = f + check("tick terminates", string.str_ends_with(tick, "\n\n"));
  let done = stream.sse_done(3);
  f = f + check("done event line", string.str_contains(done, "event: done\n"));
  f = f + check("done data line", string.str_contains(done, "data: {\"events\":3}\n"));

  // SSE head: chunked, no Content-Length, cache/stream headers.
  let h0 = stream.sse_head("");
  let head = bytes_text(&h0);
  f = f + check("head status", string.str_starts_with(head, "HTTP/1.1 200 "));
  f = f + check("head content type", string.str_contains(head, "Content-Type: text/event-stream; charset=utf-8\r\n"));
  f = f + check("head chunked", string.str_contains(head, "Transfer-Encoding: chunked\r\n"));
  f = f + check("head no content length", !string.str_contains(head, "Content-Length:"));
  f = f + check("head no-cache", string.str_contains(head, "Cache-Control: no-cache\r\n"));
  f = f + check("head proxy buffering off", string.str_contains(head, "X-Accel-Buffering: no\r\n"));

  // CORS insertion uses the same policy as normal responses.
  env.set_var("PULSE_CORS_ORIGIN", "https://example.com");
  let h1 = stream.sse_head("https://example.com");
  let cors_head = bytes_text(&h1);
  f = f + check("head cors", string.str_contains(cors_head, "Access-Control-Allow-Origin: https://example.com\r\n"));
  env.remove_var("PULSE_CORS_ORIGIN");

  // WebSocket upgrade validation.
  let key = "dGhlIHNhbXBsZSBub25jZQ==";
  f = f + check("ws valid", stream.ws_check("GET", "HTTP/1.1", "websocket", "Upgrade", "13", key) == "");
  f = f + check("ws token lists", stream.ws_check("GET", "HTTP/1.1", "WebSocket", "keep-alive, Upgrade", " 13 ", key) == "");
  f = f + check("ws post rejected", stream.ws_check("POST", "HTTP/1.1", "websocket", "Upgrade", "13", key).len() > 0);
  f = f + check("ws http10 rejected", stream.ws_check("GET", "HTTP/1.0", "websocket", "Upgrade", "13", key).len() > 0);
  f = f + check("ws no upgrade rejected", stream.ws_check("GET", "HTTP/1.1", "", "Upgrade", "13", key).len() > 0);
  f = f + check("ws no connection rejected", stream.ws_check("GET", "HTTP/1.1", "websocket", "keep-alive", "13", key).len() > 0);
  f = f + check("ws wrong version rejected", stream.ws_check("GET", "HTTP/1.1", "websocket", "Upgrade", "12", key).len() > 0);
  f = f + check("ws empty key rejected", stream.ws_check("GET", "HTTP/1.1", "websocket", "Upgrade", "13", "").len() > 0);

  // Real request parsing path (ws_request_key + header_get).
  let raw = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n");
  let req = http.parse_request(&raw);
  f = f + check("ws_check_req valid", stream.ws_check_req(&raw, &req) == "");
  let raw2 = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n\r\n");
  let req2 = http.parse_request(&raw2);
  f = f + check("ws_check_req no key", stream.ws_check_req(&raw2, &req2).len() > 0);

  if f == 0 {
    io.println("pulse-stream: GREEN");
  } else {
    io.println("pulse-stream: FAILED=" + f.to_str());
  }
  return f;
}
