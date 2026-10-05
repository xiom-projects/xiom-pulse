// probe_tcp_client2 -- Step 0c raw TCP client on the raw-fd socket API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Connects to 127.0.0.1:19080, sends an HTTP/1.1 request, reads until EOF,
// verifies "200 OK". Expects probe_tcp_server2 running.
// Run: .\scripts\run.ps1 tests\probes\probe_tcp_client2.xi
module pulse_probe_tcp_client2

use xiom.net.socket;
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
  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("[FAIL] tcp-create");
    return 1;
  }
  let fd = sr.value;

  let cr = socket.socket_connect(fd, "127.0.0.1", 19080);
  if cr.is_err {
    io.println("[FAIL] tcp-connect 127.0.0.1:19080");
    return 1;
  }

  let req: Str = "GET /ping HTTP/1.1\r\nHost: 127.0.0.1:19080\r\nConnection: close\r\n\r\n";
  let rb: Vec[UInt8] = str_to_bytes(req);
  let wr = socket.socket_send(fd, &rb);
  if wr.is_err {
    io.println("[FAIL] tcp-send");
    return 1;
  }

  var resp: Vec[UInt8] = Vec[UInt8].new();
  var done: Bool = false;
  var rounds: Int = 0;
  while !done && rounds < 64 {
    let rr = socket.socket_recv(fd, 4096);
    if rr.is_err {
      done = true;
    } else {
      let chunk = rr.value;
      if chunk.len() == 0 {
        done = true;
      } else {
        var i: Int = 0;
        while i < chunk.len() {
          resp.push(chunk[i]);
          i = i + 1;
        }
      }
    }
    rounds = rounds + 1;
  }

  socket.socket_close(fd);

  let text = Str::from_utf8(resp);
  if text.len() == 0 {
    io.println("[FAIL] empty response");
    return 1;
  }
  if !string.str_contains(text, "200 OK") {
    io.println("[FAIL] response missing 200 OK");
    return 1;
  }
  io.println("[PASS] tcp-client2 bytes=" + resp.len().to_str());
  return 0;
}
