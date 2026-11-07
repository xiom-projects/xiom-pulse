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

fn hex_nibble(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 65 && c <= 70 { return c - 55; }
  if c >= 97 && c <= 102 { return c - 87; }
  return 0;
}

fn hex_bytes(h: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i + 1 < h.len() {
    let hi = hex_nibble(h.byte_at(i) as Int);
    let lo = hex_nibble(h.byte_at(i + 1) as Int);
    out.push(((hi * 16 + lo) & 0xFF) as UInt8);
    i = i + 2;
  }
  return out;
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

  // SSE framing: a monotonic id on every event and retry on the first tick.
  let tick = stream.sse_tick(2);
  f = f + check("tick id line", string.str_contains(tick, "id: 2\n"));
  f = f + check("tick event line", string.str_contains(tick, "event: tick\n"));
  f = f + check("tick data line", string.str_contains(tick, "data: {\"seq\":2}\n"));
  f = f + check("tick terminates", string.str_ends_with(tick, "\n\n"));
  f = f + check("tick no retry", !string.str_contains(tick, "retry:"));
  let first = stream.sse_tick_retry(1, 3000);
  f = f + check("first tick id", string.str_contains(first, "id: 1\n"));
  f = f + check("retry directive", string.str_contains(first, "retry: 3000\n"));
  let done = stream.sse_done(4, 3);
  f = f + check("done id line", string.str_contains(done, "id: 4\n"));
  f = f + check("done event line", string.str_contains(done, "event: done\n"));
  f = f + check("done data line", string.str_contains(done, "data: {\"events\":3}\n"));

  // Last-Event-ID resume cursor (W-08/W-12): resume at N+1, fail closed to 1.
  let raw_last = http.str_to_bytes("GET /api/sse HTTP/1.1\r\nHost: bench\r\nLast-Event-ID: 2\r\n\r\n");
  let req_last = http.parse_request(&raw_last);
  f = f + check("last event id parsed", stream.sse_last_id(&req_last) == 2);
  f = f + check("resume starts after id", stream.sse_start_seq(&req_last) == 3);
  let raw_none = http.str_to_bytes("GET /api/sse HTTP/1.1\r\nHost: bench\r\n\r\n");
  let req_none = http.parse_request(&raw_none);
  f = f + check("last event id absent", stream.sse_last_id(&req_none) == 0);
  f = f + check("fresh stream starts at 1", stream.sse_start_seq(&req_none) == 1);
  let raw_bad_last = http.str_to_bytes("GET /api/sse HTTP/1.1\r\nHost: bench\r\nLast-Event-ID: nope\r\n\r\n");
  let req_bad_last = http.parse_request(&raw_bad_last);
  f = f + check("last event id malformed", stream.sse_last_id(&req_bad_last) == 0);
  let raw_neg_last = http.str_to_bytes("GET /api/sse HTTP/1.1\r\nHost: bench\r\nLast-Event-ID: -4\r\n\r\n");
  let req_neg_last = http.parse_request(&raw_neg_last);
  f = f + check("last event id negative", stream.sse_last_id(&req_neg_last) == 0);

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

  // --- WebSocket frame guard (crash regression) ------------------------------
  // The stdlib ws_frame_take returns a negative consumed count for a 64-bit
  // length with the MSB set; the PULSE gate must reject the header before
  // drop_prefix can index the buffer with it.
  let g_msb = hex_bytes("81FF800000000000000011223344");
  f = f + check("ws guard msb length", stream.ws_frame_violation(&g_msb) == 1002);
  let g_rsv = hex_bytes("C1811122334470");
  f = f + check("ws guard rsv1", stream.ws_frame_violation(&g_rsv) == 1002);
  let g_rsvc = hex_bytes("C98011223344");
  f = f + check("ws guard rsv control", stream.ws_frame_violation(&g_rsvc) == 1002);
  let g_unmasked = hex_bytes("810161");
  f = f + check("ws guard unmasked", stream.ws_frame_violation(&g_unmasked) == 1002);
  let g_ctrl = hex_bytes("89FE007E11223344");
  f = f + check("ws guard control long", stream.ws_frame_violation(&g_ctrl) == 1002);
  let g_fragctrl = hex_bytes("098011223344");
  f = f + check("ws guard control fragmented", stream.ws_frame_violation(&g_fragctrl) == 1002);
  let g_len16 = hex_bytes("81FE00011122334470");
  f = f + check("ws guard nonminimal 16", stream.ws_frame_violation(&g_len16) == 1002);
  let g_len64 = hex_bytes("81FF000000000000000111223344");
  f = f + check("ws guard nonminimal 64", stream.ws_frame_violation(&g_len64) == 1002);
  let g_lenzero = hex_bytes("81FF000000000000000011223344");
  f = f + check("ws guard zero 64", stream.ws_frame_violation(&g_lenzero) == 1002);
  let g_huge = hex_bytes("81FF000001000000000011223344");
  f = f + check("ws guard oversize 1009", stream.ws_frame_violation(&g_huge) == 1009);
  let g_ok = hex_bytes("81811122334470");
  f = f + check("ws guard valid masked", stream.ws_frame_violation(&g_ok) == 0);
  let g_bin = hex_bytes("82811122334470");
  f = f + check("ws guard binary allowed", stream.ws_frame_violation(&g_bin) == 0);
  let g_close = hex_bytes("88811122334470");
  f = f + check("ws guard close allowed", stream.ws_frame_violation(&g_close) == 0);
  let g_ping = hex_bytes("89811122334470");
  f = f + check("ws guard ping allowed", stream.ws_frame_violation(&g_ping) == 0);
  let g_pong = hex_bytes("8A811122334470");
  f = f + check("ws guard pong allowed", stream.ws_frame_violation(&g_pong) == 0);
  let g_op3 = hex_bytes("83811122334470");
  f = f + check("ws guard reserved opcode 3", stream.ws_frame_violation(&g_op3) == 1002);
  let g_op7 = hex_bytes("87811122334470");
  f = f + check("ws guard reserved opcode 7", stream.ws_frame_violation(&g_op7) == 1002);
  let g_op11 = hex_bytes("8B811122334470");
  f = f + check("ws guard reserved opcode 11", stream.ws_frame_violation(&g_op11) == 1002);
  let g_op15 = hex_bytes("8F811122334470");
  f = f + check("ws guard reserved opcode 15", stream.ws_frame_violation(&g_op15) == 1002);

  // --- WebSocket UTF-8 and close-payload validation --------------------------
  let u_ascii = hex_bytes("68656c6c6f");
  f = f + check("ws utf8 ascii", stream.ws_text_valid(&u_ascii));
  let u_2 = hex_bytes("C3A9");
  f = f + check("ws utf8 2-byte", stream.ws_text_valid(&u_2));
  let u_3 = hex_bytes("E282AC");
  f = f + check("ws utf8 3-byte", stream.ws_text_valid(&u_3));
  let u_4 = hex_bytes("F09F9880");
  f = f + check("ws utf8 4-byte", stream.ws_text_valid(&u_4));
  let u_bad = hex_bytes("FFFE");
  f = f + check("ws utf8 invalid", !stream.ws_text_valid(&u_bad));
  let u_over = hex_bytes("C0AF");
  f = f + check("ws utf8 overlong", !stream.ws_text_valid(&u_over));
  let u_sur = hex_bytes("EDA080");
  f = f + check("ws utf8 surrogate", !stream.ws_text_valid(&u_sur));
  let u_trunc = hex_bytes("E282");
  f = f + check("ws utf8 truncated", !stream.ws_text_valid(&u_trunc));
  let u_cont = hex_bytes("80");
  f = f + check("ws utf8 stray continuation", !stream.ws_text_valid(&u_cont));

  let c_1005 = hex_bytes("03ED");
  f = f + check("ws close 1005 rejected", !stream.ws_close_payload_valid(&c_1005));
  let c_999 = hex_bytes("03E7");
  f = f + check("ws close 999 rejected", !stream.ws_close_payload_valid(&c_999));
  let c_1 = hex_bytes("03");
  f = f + check("ws close 1-byte rejected", !stream.ws_close_payload_valid(&c_1));
  let c_1000 = hex_bytes("03E8");
  f = f + check("ws close 1000 ok", stream.ws_close_payload_valid(&c_1000));
  let c_3000 = hex_bytes("0BB8");
  f = f + check("ws close 3000 ok", stream.ws_close_payload_valid(&c_3000));
  let c_empty = hex_bytes("");
  f = f + check("ws close empty ok", stream.ws_close_payload_valid(&c_empty));
  let c_reason = hex_bytes("03E868");
  f = f + check("ws close reason ok", stream.ws_close_payload_valid(&c_reason));
  let c_badreason = hex_bytes("03E8FF");
  f = f + check("ws close bad reason", !stream.ws_close_payload_valid(&c_badreason));

  if f == 0 {
    io.println("pulse-stream: GREEN");
  } else {
    io.println("pulse-stream: FAILED=" + f.to_str());
  }
  return f;
}
