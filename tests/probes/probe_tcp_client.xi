// probe_tcp_client -- Step 0c raw TCP baseline (client side).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Connects to 127.0.0.1:19080, sends an HTTP/1.1 request, reads until EOF,
// verifies "200 OK" is present. Expects probe_tcp_server running.
// Run: .\scripts\run.ps1 tests\probes\probe_tcp_client.xi
module pulse_probe_tcp_client

use xiom.net;
use xiom.io;
use xiom.string;

fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn main() -> Int {
  let cr = net.tcp_connect("127.0.0.1", 19080);
  if cr.is_err {
    io.println("[FAIL] tcp-connect 127.0.0.1:19080");
    return 1;
  }
  let stream = cr.value;

  let req: Str = "GET /ping HTTP/1.1\r\nHost: 127.0.0.1:19080\r\nConnection: close\r\n\r\n";
  let rb: Vec[UInt8] = str_to_bytes(req);
  let wr = stream.write(&rb);
  if wr.is_err {
    io.println("[FAIL] tcp-write");
    return 1;
  }

  var resp: Vec[UInt8] = Vec[UInt8].new();
  var done: Bool = false;
  while !done {
    let rr = stream.read(&mut resp);
    if rr.is_err {
      done = true;
    } else {
      let n = rr.value;
      if n <= 0 { done = true; }
    }
  }

  let cl = stream.close();
  if cl.is_err { io.println("[WARN] close failed"); }

  let text = Str::from_utf8(resp);
  if text.len() == 0 {
    io.println("[FAIL] empty response");
    return 1;
  }
  if !string.str_contains(text, "200 OK") {
    io.println("[FAIL] response missing 200 OK");
    return 1;
  }
  io.println("[PASS] tcp-client bytes=" + resp.len().to_str());
  return 0;
}
