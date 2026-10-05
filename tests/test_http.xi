// XIOM PULSE -- HTTP parsing + routing conformance suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: .\scripts\run.ps1 tests\test_http.xi
// Exit code = number of failures (0 = green).
module pulse_http_tests

use xiom.io;
use xiom.string;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.server;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn req_bytes(s: Str) -> Vec[UInt8] {
  return http.str_to_bytes(s);
}

/// route_req - full dispatch path: bytes -> parse -> route -> handle.
/// (Step 2 signature; v0.64.0 correctly rejects passing raw strings.)
fn route_req(method: Str, target: Str, body: Str) -> HandlerOut {
  let raw_str = method + " " + target + " HTTP/1.1\r\nHost: t\r\nContent-Length: " + body.len().to_str() + "\r\n\r\n" + body;
  let raw = http.str_to_bytes(raw_str);
  let req = http.parse_request(&raw);
  let m = router.route_match(method, target);
  return server.handle_route(m, &req, body);
}

pub fn main() -> Int {
  var f: Int = 0;

  // --- header terminator --------------------------------------------------
  let r1 = req_bytes("GET /health HTTP/1.1\r\nHost: example\r\nX-Test: yes\r\n\r\n");
  let he1 = http.find_header_end(&r1);
  f = f + check("find_header_end present", he1 >= 0 && he1 + 4 <= r1.len());
  let r0 = req_bytes("GET /health HTTP/1.1\r\nHost: example");
  f = f + check("find_header_end absent", http.find_header_end(&r0) == -1);

  // --- request line + headers ---------------------------------------------
  let req1 = http.parse_request(&r1);
  f = f + check("parse ok", req1.ok);
  f = f + check("method", req1.method == "GET");
  f = f + check("target", req1.target == "/health");
  f = f + check("version", req1.version == "HTTP/1.1");
  f = f + check("header count", req1.header_names.len() == 2);
  f = f + check("header_get host", http.header_get(&req1, "host") == "example");
  f = f + check("header_get case-insensitive", http.header_get(&req1, "X-TEST") == "yes");
  f = f + check("header_get absent", http.header_get(&req1, "content-type") == "");

  // --- body + content length ----------------------------------------------
  let r2 = req_bytes("POST /api/echo HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}");
  let he2 = http.find_header_end(&r2);
  f = f + check("content_length_of", http.content_length_of(&r2, he2) == 7);
  let req2 = http.parse_request(&r2);
  f = f + check("post parse ok", req2.ok);
  f = f + check("post body len", req2.body.len() == 7);
  f = f + check("post body bytes", http.bytes_to_str(&req2.body, 0, req2.body.len()) == "{\"a\":1}");
  f = f + check("no content-length is 0", http.content_length_of(&r1, he1) == 0);

  // --- malformed ----------------------------------------------------------
  let bad1 = http.parse_request(&r0);
  f = f + check("incomplete headers rejected", !bad1.ok && bad1.error.len() > 0);
  let r3 = req_bytes("GET\r\n\r\n");
  let bad2 = http.parse_request(&r3);
  f = f + check("malformed request line rejected", !bad2.ok);
  let r4 = req_bytes("GET /x HTTP/1.1\r\nBrokenHeader\r\n\r\n");
  let bad3 = http.parse_request(&r4);
  f = f + check("malformed header rejected", !bad3.ok);

  // --- response building ---------------------------------------------------
  let resp = http.build_response(200, "{\"status\":\"ok\"}");
  let resp_str = http.bytes_to_str(&resp, 0, resp.len());
  f = f + check("status line", string.str_contains(resp_str, "HTTP/1.1 200 OK\r\n"));
  f = f + check("content-type json", string.str_contains(resp_str, "Content-Type: application/json"));
  f = f + check("content-length 15", string.str_contains(resp_str, "Content-Length: 15\r\n"));
  f = f + check("connection close", string.str_contains(resp_str, "Connection: close\r\n"));
  f = f + check("body at end", string.str_ends_with(resp_str, "{\"status\":\"ok\"}"));

  // --- routing -------------------------------------------------------------
  let h = route_req("GET", "/health", "");
  f = f + check("route /health 200", h.status == 200 && string.str_contains(h.body, "\"status\":\"ok\""));
  let h405 = route_req("POST", "/health", "");
  f = f + check("route /health 405", h405.status == 405);
  let v = route_req("GET", "/api/version", "");
  f = f + check("route /api/version 200", v.status == 200 && string.str_contains(v.body, "\"name\":\"xiom-pulse\""));
  f = f + check("route /api/version version", string.str_contains(v.body, "\"version\":\"0.1.0\""));
  let nf = route_req("GET", "/nope", "");
  f = f + check("route 404", nf.status == 404);
  let e = route_req("POST", "/api/echo", "{\"a\":1}");
  f = f + check("route echo 200", e.status == 200 && string.str_contains(e.body, "\"echo\":{\"a\":1}"));
  let e400 = route_req("POST", "/api/echo", "notjson");
  f = f + check("route echo 400", e400.status == 400);
  let e405 = route_req("GET", "/api/echo", "");
  f = f + check("route echo 405", e405.status == 405);

  // --- query strings, decoding, caps ---------------------------------------
  let st = router.split_target("/api/items/42?x=1&y=2");
  f = f + check("split_target path", st.0 == "/api/items/42");
  f = f + check("split_target query", st.1 == "x=1&y=2");
  let st2 = router.split_target("/health");
  f = f + check("split_target no query", st2.0 == "/health" && st2.1 == "");
  f = f + check("url_decode plus", router.url_decode("a+b") == "a b");
  f = f + check("url_decode hex", router.url_decode("x%21%7E") == "x!~");
  let qp = router.parse_query("a=1&b=hello%20world&c");
  let n2 = qp.0[2];
  let v1 = qp.1[1];
  let v2 = qp.1[2];
  f = f + check("parse_query count", qp.0.len() == 3 && n2 == "c");
  f = f + check("parse_query decoded", v1 == "hello world");
  f = f + check("parse_query flag empty", v2 == "");
  let mq = router.route_match("GET", "/api/items/7?x=1");
  let pv0 = mq.param_values[0];
  let qn0 = mq.query_names[0];
  let qv0 = mq.query_values[0];
  f = f + check("route query keeps param", mq.kind == 1 && pv0 == "7");
  f = f + check("route query parsed", qn0 == "x" && qv0 == "1");
  let mh = router.route_match("GET", "/health?debug=1");
  f = f + check("route health with query", mh.kind == 1 && mh.route_id == 1);
  f = f + check("header_overflow normal false", !http.header_overflow(&r1));
  var big: Vec[UInt8] = Vec[UInt8].new();
  var bi: Int = 0;
  while bi < 20000 {
    big.push(65u8);
    bi = bi + 1;
  }
  f = f + check("header_overflow oversized true", http.header_overflow(&big));
  var many_hdr: Str = "GET /health HTTP/1.1\r\n";
  var hi: Int = 0;
  while hi < 101 {
    many_hdr = many_hdr + "X-H" + hi.to_str() + ": v\r\n";
    hi = hi + 1;
  }
  many_hdr = many_hdr + "\r\n";
  let rmany = http.str_to_bytes(many_hdr);
  let pmany = http.parse_request(&rmany);
  f = f + check("too many headers rejected", !pmany.ok);
  f = f + check("security nosniff", string.str_contains(resp_str, "X-Content-Type-Options: nosniff"));
  f = f + check("security frame deny", string.str_contains(resp_str, "X-Frame-Options: DENY"));

  if f == 0 {
    io.println("pulse-http: GREEN");
  } else {
    io.println("pulse-http: RED failures=" + f.to_str());
  }
  return f;
}
