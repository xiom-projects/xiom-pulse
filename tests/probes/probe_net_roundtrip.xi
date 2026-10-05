// probe_net_roundtrip -- isolate the xiom.net TcpListener/TcpStream struct path.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Self-contained: listen, connect from the same process, accept, exchange
// bytes. Prints the listener fd at every hand-off point. No external client.
module pulse_probe_net_roundtrip

use xiom.net;
use xiom.io;

fn fd_of(l: TcpListener) -> Int {
  return l.fd;
}

fn main() -> Int {
  let lr = net.tcp_listen("127.0.0.1", 19082);
  if lr.is_err {
    io.println("[FAIL] listen");
    return 1;
  }
  io.println("lr.value.fd=" + lr.value.fd.to_str());
  let listener = lr.value;
  io.println("listener.fd=" + listener.fd.to_str());
  io.println("byval.fd=" + fd_of(listener).to_str());

  let cr = net.tcp_connect("127.0.0.1", 19082);
  io.println("connect ok=" + (if cr.is_ok { "true" } else { "false" }));
  if cr.is_err { return 1; }
  let stream = cr.value;

  let ar = listener.accept();
  io.println("accept ok=" + (if ar.is_ok { "true" } else { "false" }));
  if ar.is_err { return 1; }
  let pair = ar.value;
  let server_stream = pair.0;
  io.println("server-stream.fd=" + server_stream.fd.to_str());

  var msg: Vec[UInt8] = Vec[UInt8].new();
  msg.push(112u8);
  msg.push(105u8);
  msg.push(110u8);
  msg.push(103u8);
  let wr = stream.write(&msg);
  io.println("client-write ok=" + (if wr.is_ok { "true" } else { "false" }));

  var got: Vec[UInt8] = Vec[UInt8].new();
  let rr = server_stream.read(&mut got);
  io.println("server-read ok=" + (if rr.is_ok { "true" } else { "false" }));
  io.println("server-read bytes=" + got.len().to_str());

  let c1 = stream.close();
  if c1.is_err { io.println("[WARN] client close"); }
  let c2 = server_stream.close();
  if c2.is_err { io.println("[WARN] server close"); }

  if got.len() == 4 && rr.is_ok {
    io.println("[PASS] net-roundtrip");
    return 0;
  }
  io.println("[FAIL] net-roundtrip");
  return 1;
}
