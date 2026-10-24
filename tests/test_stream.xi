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
use xiom.string.slice;
use xiom.time;
use xiom.jwt;
use xiom.pulse.http;
use xiom.pulse.sessions;
use xiom.pulse.station.stream;
use xiom.pulse.station.wsauth;

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

fn test_handler(_fd: Int, _raw: &Vec<UInt8>, _req: &PulseRequest) -> (Int, Int) {
  return (9, 3);
}

pub fn main() -> Int {
  var f: Int = 0;

  // Registry: self-init is idempotent and exposes the built-in demo routes.
  let init_added = stream.init();
  f = f + check("init idempotent", stream.init() == 0);
  f = f + check("init builtins", init_added >= 0 && stream.stream_kind("GET", "/api/sse") == 1);

  // Classification: only GET /api/sse and GET /api/ws are streams.
  f = f + check("kind sse", stream.stream_kind("GET", "/api/sse") == 1);
  f = f + check("kind sse query", stream.stream_kind("GET", "/api/sse?events=2") == 1);
  f = f + check("kind ws", stream.stream_kind("GET", "/api/ws") == 2);
  f = f + check("kind ws query", stream.stream_kind("GET", "/api/ws?x=1") == 2);
  f = f + check("kind other", stream.stream_kind("GET", "/api/version") == 0);
  f = f + check("kind post", stream.stream_kind("POST", "/api/ws") == 0);
  f = f + check("kind head", stream.stream_kind("HEAD", "/api/sse") == 0);

  // Runtime registration (startup seam; handlers are the built-in kinds).
  f = f + check("register custom", stream.register("GET", "/api/stream2", 1));
  f = f + check("custom kind", stream.stream_kind("GET", "/api/stream2?x=1") == 1);
  f = f + check("custom route path", stream.route_path("GET", "/api/stream2?x=1") == "/api/stream2");
  f = f + check("duplicate rejected", !stream.register("GET", "/api/stream2", 2));
  f = f + check("bad path rejected", !stream.register("GET", "api/x", 1));
  f = f + check("bad kind rejected", !stream.register("GET", "/api/x", 3));
  f = f + check("bad method rejected", !stream.register("POST", "/api/x", 1));
  let rt = stream.routes_text();
  f = f + check("routes text sse", string.str_contains(rt, "GET /api/sse (sse)\n"));
  f = f + check("routes text custom", string.str_contains(rt, "GET /api/stream2 (sse)\n"));

  // User handler registry (v0.65.0 stored-fn support).
  f = f + check("register handler", stream.register_handler("GET", "/api/custom", 2, test_handler));
  f = f + check("handler duplicate rejected", !stream.register_handler("GET", "/api/custom", 2, test_handler));
  f = f + check("handler bad method rejected", !stream.register_handler("POST", "/api/custom2", 2, test_handler));
  let draw = http.str_to_bytes("GET /api/custom HTTP/1.1\r\nHost: bench\r\n\r\n");
  let dreq = http.parse_request(&draw);
  let dr = stream.dispatch(0, &draw, &dreq, "/api/custom");
  let d0: Int = dr.0;
  let d1: Int = dr.1;
  f = f + check("dispatch handler", d0 == 9 && d1 == 3);
  let miss = stream.dispatch(0, &draw, &dreq, "/api/absent");
  let m0: Int = miss.0;
  f = f + check("dispatch missing", m0 == 0);

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

  // WebSocket Origin policy: same-origin default + PULSE_CORS_ORIGIN allowlist.
  f = f + check("ws origin absent", stream.ws_origin_check("", "example.com") == "");
  f = f + check("ws origin same", stream.ws_origin_check("https://example.com", "example.com") == "");
  f = f + check("ws origin same :443", stream.ws_origin_check("https://example.com:443", "example.com") == "");
  f = f + check("ws origin same :80", stream.ws_origin_check("http://example.com:80", "example.com") == "");
  f = f + check("ws origin same :8080", stream.ws_origin_check("http://example.com:8080", "example.com:8080") == "");
  f = f + check("ws origin cross rejected", stream.ws_origin_check("https://evil.example", "example.com").len() > 0);
  f = f + check("ws origin null rejected", stream.ws_origin_check("null", "example.com").len() > 0);
  env.set_var("PULSE_CORS_ORIGIN", "https://allowed.example");
  f = f + check("ws origin allowlist", stream.ws_origin_check("https://allowed.example", "example.com") == "");
  env.set_var("PULSE_CORS_ORIGIN", "*");
  f = f + check("ws origin wildcard", stream.ws_origin_check("https://any.example", "example.com") == "");
  env.remove_var("PULSE_CORS_ORIGIN");

  // --- stream authentication (PULSE_WS_AUTH) --------------------------------
  let key2 = "dGhlIHNhbXBsZSBub25jZQ==";
  let raw_ws = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key2 + "\r\nSec-WebSocket-Version: 13\r\n\r\n");
  let req_ws = http.parse_request(&raw_ws);

  // Default (off) keeps the same-origin-only behavior.
  env.remove_var("PULSE_WS_AUTH");
  f = f + check("auth default off allows", wsauth.denied_reason(&req_ws) == "");

  // Credential redaction for logs/audit.
  f = f + check("redact token", wsauth.redact_target("/api/ws?token=secret&x=1") == "/api/ws?token=REDACTED&x=1");
  f = f + check("redact access_token", string.str_contains(wsauth.redact_target("/api/sse?access_token=abc"), "access_token=REDACTED"));
  f = f + check("redact clean untouched", wsauth.redact_target("/api/ws?events=2") == "/api/ws?events=2");
  f = f + check("redact no query", wsauth.redact_target("/api/ws") == "/api/ws");

  // JWT mode: missing / valid across the three carriers / invalid.
  env.set_var("PULSE_WS_AUTH", "jwt");
  env.set_var("PULSE_JWT_SECRET", "s3cret");
  f = f + check("auth jwt missing denied", wsauth.denied_reason(&req_ws) == "missing token");
  let now = time.unix_timestamp();
  let payload = "{\"sub\":\"bob\",\"exp\":" + (now + 3600).to_str() + "}";
  let kb = slice.str_bytes("s3cret");
  let tr = jwt.jwt_sign_hs256(payload, &kb);
  var tok: Str = "";
  if tr.is_ok { tok = tr.value; }
  f = f + check("auth jwt sign ok", tok.len() > 0);

  let raw_q = http.str_to_bytes("GET /api/ws?token=" + tok + " HTTP/1.1\r\nHost: bench\r\n\r\n");
  let req_q = http.parse_request(&raw_q);
  f = f + check("auth jwt query allowed", wsauth.denied_reason(&req_q) == "");
  f = f + check("auth jwt query redacted", !string.str_contains(wsauth.redact_target(req_q.target), tok));

  let raw_h = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nAuthorization: Bearer " + tok + "\r\n\r\n");
  let req_h = http.parse_request(&raw_h);
  f = f + check("auth jwt bearer allowed", wsauth.denied_reason(&req_h) == "");

  let raw_p = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nSec-WebSocket-Protocol: chat, pulse.jwt." + tok + "\r\n\r\n");
  let req_p = http.parse_request(&raw_p);
  f = f + check("auth jwt subprotocol allowed", wsauth.denied_reason(&req_p) == "");
  f = f + check("auth challenge bearer", wsauth.challenge_header() == "Bearer");

  let raw_bad = http.str_to_bytes("GET /api/ws?token=not-a-jwt HTTP/1.1\r\nHost: bench\r\n\r\n");
  let req_bad = http.parse_request(&raw_bad);
  f = f + check("auth jwt invalid denied", wsauth.denied_reason(&req_bad) == "invalid token");

  let payload_e = "{\"sub\":\"bob\",\"exp\":" + (now - 10).to_str() + "}";
  let tre = jwt.jwt_sign_hs256(payload_e, &kb);
  var tok_e: Str = "";
  if tre.is_ok { tok_e = tre.value; }
  let raw_e = http.str_to_bytes("GET /api/ws?token=" + tok_e + " HTTP/1.1\r\nHost: bench\r\n\r\n");
  let req_e = http.parse_request(&raw_e);
  f = f + check("auth jwt expired denied", wsauth.denied_reason(&req_e) == "invalid token");

  env.set_var("PULSE_JWT_SECRET", "other");
  f = f + check("auth jwt wrong secret denied", wsauth.denied_reason(&req_q) == "invalid token");
  env.remove_var("PULSE_JWT_SECRET");
  f = f + check("auth jwt no secret fails closed", wsauth.denied_reason(&req_q) == "jwt secret not configured");

  // Session mode: live `sid` cookie.
  env.set_var("PULSE_WS_AUTH", "session");
  sessions.session_reset();
  f = f + check("auth session missing denied", wsauth.denied_reason(&req_ws) == "missing session");
  let sid = sessions.session_create("bob", 60);
  let raw_c = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nCookie: sid=" + sid + "\r\n\r\n");
  let req_c = http.parse_request(&raw_c);
  f = f + check("auth session allowed", wsauth.denied_reason(&req_c) == "");
  f = f + check("auth session challenge empty", wsauth.challenge_header() == "");
  sessions.session_reset();

  // Unknown mode fails closed (never silently disables auth).
  env.set_var("PULSE_WS_AUTH", "jwtt");
  f = f + check("auth unknown mode fails closed", wsauth.denied_reason(&req_c) == "invalid auth mode");
  env.remove_var("PULSE_WS_AUTH");

  if f == 0 {
    io.println("pulse-stream: GREEN");
  } else {
    io.println("pulse-stream: FAILED=" + f.to_str());
  }
  return f;
}
