// probe_tcp_server -- Step 0c raw TCP baseline (server side).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Binds 127.0.0.1:19080, serves a fixed HTTP/1.1 response per connection,
// exits when a request contains "QUIT".
// Build: .\scripts\build.ps1 tests\probes\probe_tcp_server.xi
module pulse_probe_tcp_server

use xiom.net;
use xiom.io;

fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn has_crlfcrlf(buf: &Vec[UInt8]) -> Bool {
  let n = buf.len();
  if n < 4 { return false; }
  var i: Int = 0;
  while i + 4 <= n {
    if buf[i] == 13u8 && buf[i + 1] == 10u8 && buf[i + 2] == 13u8 && buf[i + 3] == 10u8 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn contains_quit(buf: &Vec[UInt8]) -> Bool {
  let n = buf.len();
  if n < 4 { return false; }
  var i: Int = 0;
  while i + 4 <= n {
    if buf[i] == 81u8 && buf[i + 1] == 85u8 && buf[i + 2] == 73u8 && buf[i + 3] == 84u8 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn main() -> Int {
  let lr = net.tcp_listen("127.0.0.1", 19080);
  if lr.is_err {
    io.println("[FAIL] tcp-listen 127.0.0.1:19080");
    return 1;
  }
  let listener = lr.value;
  io.println("tcp-server: listening on 127.0.0.1:19080");

  var served: Int = 0;
  var running: Bool = true;
  while running {
    let ar = listener.accept();
    if ar.is_err {
      io.println("[FAIL] accept");
      return 1;
    }
    let pair = ar.value;
    let stream = pair.0;

    var req: Vec[UInt8] = Vec[UInt8].new();
    var done: Bool = false;
    while !done {
      var chunk: Vec[UInt8] = Vec[UInt8].new();
      let rr = stream.read(&mut chunk);
      if rr.is_err {
        done = true;
      } else {
        let n = rr.value;
        if n <= 0 {
          done = true;
        } else {
          var i: Int = 0;
          while i < chunk.len() {
            req.push(chunk[i]);
            i = i + 1;
          }
          if has_crlfcrlf(&req) { done = true; }
        }
      }
    }

    if contains_quit(&req) {
      running = false;
    } else {
      let body: Str = "pong";
      let resp: Str = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: " + body.len().to_str() + "\r\nConnection: close\r\n\r\n" + body;
      let rb: Vec[UInt8] = str_to_bytes(resp);
      let wr = stream.write(&rb);
      if wr.is_err {
        io.println("[FAIL] write");
        return 1;
      }
      served = served + 1;
    }

    let cr = stream.close();
    if cr.is_err { io.println("[WARN] close failed"); }
  }

  io.println("[PASS] tcp-server served=" + served.to_str());
  return 0;
}
