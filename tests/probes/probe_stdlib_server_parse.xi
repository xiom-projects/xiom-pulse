// probe_stdlib_server_parse -- differential check: PULSE's xiom.pulse.http
// parser vs the stdlib xiom.net.server parser (added 2026-10-07 for PULSE).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: scripts/run.sh tests\probes\probe_stdlib_server_parse.xi
// Exit code = failures (0 = parity on the shared corpus).
module pulse_probe_stdlib_server_parse

use xiom.io;
use xiom.string;
use xiom.pulse.http;
use xiom.net.server;

const REQ_GET: Str = "GET /health HTTP/1.1\r\nHost: t\r\n\r\n";
const REQ_POST: Str = "POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\n\r\n{\"a\":1}";
const REQ_NO_CL: Str = "POST /api/echo HTTP/1.1\r\nHost: t\r\n\r\n";
const REQ_DUP: Str = "GET /x HTTP/1.1\r\nHost: t\r\nX-A: v1\r\nX-A: v2\r\n\r\n";
const REQ_UPPER: Str = "GET /y HTTP/1.1\r\nHOST: t\r\nCONTENT-TYPE: text/plain\r\n\r\n";
const REQ_WS: Str = "POST /z HTTP/1.1\r\nHost: t\r\nContent-Length: 3\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nabc";
const REQ_INCOMPLETE: Str = "GET /health HTTP/1.1\r\nHost: t";
const REQ_BADLINE: Str = "GARBAGE\r\n\r\n";
const REQ_BADHEADER: Str = "GET /x HTTP/1.1\r\nHost t\r\n\r\n";
const REQ_NEG_CL: Str = "POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: -5\r\n\r\n";
const REQ_BAD_CL: Str = "POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: abc\r\n\r\n";

fn mk(s: Str) -> Vec[UInt8] {
  return http.str_to_bytes(s);
}

fn body_of(raw: &Vec[UInt8], sr: ServerRequest) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = sr.body_start;
  while i < sr.body_start + sr.body_len && i < raw.len() {
    out.push(raw[i]);
    i = i + 1;
  }
  return out;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn std_header_count(sr: ServerRequest, name: Str) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < sr.headers.len() {
    if sr.headers[i].0 == name {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

fn pulse_header_count(req: PulseRequest, name: Str) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < req.header_names.len() {
    if string.str_lower(req.header_names[i]) == name {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

pub fn main() -> Int {
  var fails: Int = 0;

  // 1. simple GET: both accept, same method/target/version, empty body.
  let r1 = mk(REQ_GET);
  let p1 = http.parse_request(&r1);
  let s1 = server_parse_request(&r1);
  if !p1.ok || s1.is_none {
    io.println("[FAIL] get accepted");
    fails = fails + 1;
  } else {
    let sr = s1.value;
    if p1.method != sr.method || p1.target != sr.target || p1.version != sr.version || sr.body_len != 0 {
      io.println("[FAIL] get fields");
      fails = fails + 1;
    } else {
      io.println("[PASS] get fields");
    }
  }

  // 2. POST with body: same bytes on both sides.
  let r2 = mk(REQ_POST);
  let p2 = http.parse_request(&r2);
  let s2 = server_parse_request(&r2);
  if !p2.ok || s2.is_none {
    io.println("[FAIL] post accepted");
    fails = fails + 1;
  } else {
    let sr = s2.value;
    let sb = body_of(&r2, sr);
    if p2.body.len() != 7 || sr.body_len != 7 || !bytes_eq(&p2.body, &sb) {
      io.println("[FAIL] post body");
      fails = fails + 1;
    } else {
      io.println("[PASS] post body");
    }
  }

  // 3. POST without Content-Length: both accept with empty body.
  let r3 = mk(REQ_NO_CL);
  let p3 = http.parse_request(&r3);
  let s3 = server_parse_request(&r3);
  if !p3.ok || s3.is_none || p3.body.len() != 0 || s3.value.body_len != 0 {
    io.println("[FAIL] no content-length");
    fails = fails + 1;
  } else {
    io.println("[PASS] no content-length");
  }

  // 4. duplicate headers: same count on both sides.
  let r4 = mk(REQ_DUP);
  let p4 = http.parse_request(&r4);
  let s4 = server_parse_request(&r4);
  if !p4.ok || s4.is_none {
    io.println("[FAIL] dup accepted");
    fails = fails + 1;
  } else {
    let sn = std_header_count(s4.value, "x-a");
    let pn = pulse_header_count(p4, "x-a");
    if sn != 2 || pn != 2 {
      io.println("[FAIL] dup count std=" + sn.to_str() + " pulse=" + pn.to_str());
      fails = fails + 1;
    } else {
      io.println("[PASS] dup count");
    }
  }

  // 5. uppercase header names: stdlib lowercases.
  let r5 = mk(REQ_UPPER);
  let s5 = server_parse_request(&r5);
  if s5.is_none || std_header_count(s5.value, "host") != 1 || std_header_count(s5.value, "content-type") != 1 {
    io.println("[FAIL] uppercase names lowercased");
    fails = fails + 1;
  } else {
    io.println("[PASS] uppercase names lowercased");
  }

  // 6. header value spacing: single leading space stripped, inner kept.
  let r6 = mk(REQ_WS);
  let s6 = server_parse_request(&r6);
  let p6 = http.parse_request(&r6);
  if s6.is_none {
    io.println("[FAIL] ws accepted");
    fails = fails + 1;
  } else {
    let sr = s6.value;
    var ct: Str = "";
    var hi: Int = 0;
    while hi < sr.headers.len() {
      if sr.headers[hi].0 == "content-type" {
        ct = sr.headers[hi].1;
      }
      hi = hi + 1;
    }
    let pct = http.header_get(&p6, "content-type");
    if ct != "text/plain; charset=utf-8" || pct != ct {
      io.println("[FAIL] header value: std=[" + ct + "] pulse=[" + pct + "]");
      fails = fails + 1;
    } else {
      io.println("[PASS] header value spacing");
    }
  }

  // 7-11. rejects: both sides must refuse the malformed corpus.
  let r7 = mk(REQ_INCOMPLETE);
  if http.parse_request(&r7).ok || server_parse_request(&r7).is_some {
    io.println("[FAIL] incomplete rejected");
    fails = fails + 1;
  } else {
    io.println("[PASS] incomplete rejected");
  }
  let r8 = mk(REQ_BADLINE);
  if http.parse_request(&r8).ok || server_parse_request(&r8).is_some {
    io.println("[FAIL] bad line rejected");
    fails = fails + 1;
  } else {
    io.println("[PASS] bad line rejected");
  }
  let r9 = mk(REQ_BADHEADER);
  if http.parse_request(&r9).ok || server_parse_request(&r9).is_some {
    io.println("[FAIL] bad header rejected");
    fails = fails + 1;
  } else {
    io.println("[PASS] bad header rejected");
  }

  // 10-11. invalid Content-Length: both parsers must refuse (PULSE adopted
  // the stdlib semantics on 2026-10-07; previously PULSE accepted these
  // with an empty body).
  let r10 = mk(REQ_NEG_CL);
  if http.parse_request(&r10).ok || server_parse_request(&r10).is_some {
    io.println("[FAIL] negative cl refused");
    fails = fails + 1;
  } else {
    io.println("[PASS] negative cl refused");
  }
  let r11 = mk(REQ_BAD_CL);
  if http.parse_request(&r11).ok || server_parse_request(&r11).is_some {
    io.println("[FAIL] non-numeric cl refused");
    fails = fails + 1;
  } else {
    io.println("[PASS] non-numeric cl refused");
  }

  if fails == 0 {
    io.println("[PASS] stdlib-server-parse (parity + fixed CL hardening)");
    return 0;
  }
  io.println("[FAIL] stdlib-server-parse fails=" + fails.to_str());
  return fails;
}
