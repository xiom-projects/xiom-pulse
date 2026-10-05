// probe_socket_low -- Step 0c diagnosis: low-level socket path with fd tracing.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One-shot server on 127.0.0.1:19081 using xiom.net.socket directly (no
// struct/Result round-trip for the listener fd). Prints fd at each step and
// serves one fixed response. Run the PowerShell client in parallel.
module pulse_probe_socket_low

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
    io.println("[FAIL] socket_tcp (create)");
    return 1;
  }
  let fd = sr.value;
  io.println("create fd=" + fd.to_str());

  let br = socket.socket_bind(fd, "127.0.0.1", 19081);
  io.println("bind ok=" + (if br.is_ok { "true" } else { "false" }));
  if br.is_err { return 1; }

  let lr = socket.socket_listen(fd, 128);
  io.println("listen ok=" + (if lr.is_ok { "true" } else { "false" }));
  if lr.is_err { return 1; }

  io.println("accept waiting");
  let ar = socket.socket_accept(fd);
  if ar.is_err {
    io.println("[FAIL] accept");
    return 1;
  }
  let client = ar.value;
  io.println("accept fd=" + client.to_str());

  var resp: Vec[UInt8] = Vec[UInt8].new();
  let rr = socket.socket_recv(client, 4096);
  if rr.is_err {
    io.println("[FAIL] recv");
    return 1;
  }
  resp = rr.value;
  io.println("recv bytes=" + resp.len().to_str());

  let out: Str = "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\npong";
  let ob: Vec[UInt8] = str_to_bytes(out);
  let wr = socket.socket_send(client, &ob);
  if wr.is_err {
    io.println("[FAIL] send");
    return 1;
  }
  io.println("send ok");

  socket.socket_close(client);
  socket.socket_close(fd);
  io.println("[PASS] socket-low");
  return 0;
}
