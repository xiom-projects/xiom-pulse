// XIOM PULSE -- fuzz finding repro: a NUL in the request head yields an
// ok=true parse with an empty method/target (the stdlib parser truncates at
// the NUL). Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
// SPDX-License-Identifier: MIT OR Apache-2.0
module probe_fuzz_repro

use xiom.io;
use xiom.pulse.http;

fn show(label: Str, raw: &Vec[UInt8]) -> Int {
  let r = http.parse_request(raw);
  io.println(label + " ok=" + r.ok.to_str() + " m=[" + r.method + "] t=[" + r.target + "] v=[" + r.version + "] e=[" + r.error + "]");
  return 0;
}

fn with_nul(prefix: Str, suffix: Str) -> Vec[UInt8] {
  var out = http.str_to_bytes(prefix);
  out.push(0u8);
  let tail = http.str_to_bytes(suffix);
  var i: Int = 0;
  while i < tail.len() {
    out.push(tail[i]);
    i = i + 1;
  }
  return out;
}

pub fn main() -> Int {
  let valid = http.str_to_bytes("GET / HTTP/1.1\r\nHost: t\r\n\r\n");
  let nul_method = with_nul("PO", "ST /x HTTP/1.1\r\nHost: t\r\n\r\n");
  let nul_before_method = with_nul("", "OST /x HTTP/1.1\r\nHost: t\r\n\r\n");
  let nul_target = with_nul("GET /x", " HTTP/1.1\r\nHost: t\r\n\r\n");
  let nul_hval = with_nul("GET / HTTP/1.1\r\nHost: t\r\nX: a", "b\r\n\r\n");
  let nul_hname = with_nul("GET / HTTP/1.1\r\nHo", "st: t\r\n\r\n");
  show("valid", &valid);
  show("nul in method", &nul_method);
  show("nul before method", &nul_before_method);
  show("nul in target", &nul_target);
  show("nul in header value", &nul_hval);
  show("nul in header name", &nul_hname);
  return 0;
}
