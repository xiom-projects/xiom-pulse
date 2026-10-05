// probe_tcp_server2 -- Step 0c raw TCP server on the raw-fd socket API
// (works around C-PULSE-01: one-arg `.read(...)` methods are hijacked).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Binds 127.0.0.1:19080, serves a fixed HTTP/1.1 response per connection,
// exits when a request contains "QUIT".
// Build: .\scripts\build.ps1 tests\probes\probe_tcp_server2.xi
module pulse_probe_tcp_server2

use xiom.net.socket;
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
  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("[FAIL] tcp-create");
    return 1;
  }
  let fd = sr.value;

  let br = socket.socket_bind(fd, "127.0.0.1", 19080);
  if br.is_err {
    io.println("[FAIL] tcp-bind 127.0.0.1:19080");
    return 1;
  }
  let lr = socket.socket_listen(fd, 128);
  if lr.is_err {
    io.println("[FAIL] tcp-listen");
    return 1;
  }
  io.println("tcp-server2: listening on 127.0.0.1:19080");

  var served: Int = 0;
  var running: Bool = true;
  while running {
    let ar = socket.socket_accept(fd);
    if ar.is_err {
      io.println("[FAIL] accept");
      return 1;
    }
    let client = ar.value;

    var req: Vec[UInt8] = Vec[UInt8].new();
    var done: Bool = false;
    var rounds: Int = 0;
    while !done && rounds < 64 {
      let rr = socket.socket_recv(client, 4096);
      if rr.is_err {
        done = true;
      } else {
        let chunk = rr.value;
        if chunk.len() == 0 {
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
      rounds = rounds + 1;
    }

    if contains_quit(&req) {
      running = false;
    } else {
      let body: Str = "pong";
      let resp: Str = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: " + body.len().to_str() + "\r\nConnection: close\r\n\r\n" + body;
      let rb: Vec[UInt8] = str_to_bytes(resp);
      let wr = socket.socket_send(client, &rb);
      if wr.is_err {
        io.println("[FAIL] send");
        return 1;
      }
      served = served + 1;
    }

    socket.socket_close(client);
  }

  socket.socket_close(fd);
  io.println("[PASS] tcp-server2 served=" + served.to_str());
  return 0;
}
