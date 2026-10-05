// probe_net_roundtrip2 -- distinguish TcpStream method path vs raw fd.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Same self-contained roundtrip, but reads twice:
//   1) direct socket.socket_recv(server_stream.fd, ...) -- raw fd path
//   2) server_stream.read(&mut ...) -- TcpStream method path
// If (1) gets bytes and (2) fails, the fd is valid and the method is at fault.
module pulse_probe_net_roundtrip2

use xiom.net;
use xiom.net.socket;
use xiom.io;

fn main() -> Int {
  let lr = net.tcp_listen("127.0.0.1", 19083);
  if lr.is_err {
    io.println("[FAIL] listen");
    return 1;
  }
  let listener = lr.value;

  let cr = net.tcp_connect("127.0.0.1", 19083);
  if cr.is_err {
    io.println("[FAIL] connect");
    return 1;
  }
  let stream = cr.value;
  io.println("client-stream.fd=" + stream.fd.to_str());

  let ar = listener.accept();
  if ar.is_err {
    io.println("[FAIL] accept");
    return 1;
  }
  let pair = ar.value;
  let server_stream = pair.0;
  io.println("server-stream.fd=" + server_stream.fd.to_str());

  var msg: Vec[UInt8] = Vec[UInt8].new();
  msg.push(112u8);
  msg.push(105u8);
  msg.push(110u8);
  msg.push(103u8);
  let wr = stream.write(&msg);
  if wr.is_err {
    io.println("[FAIL] write1");
    return 1;
  }
  io.println("write1 n=" + wr.value.to_str());

  let dr = socket.socket_recv(server_stream.fd, 4096);
  io.println("direct-recv ok=" + (if dr.is_ok { "true" } else { "false" }));
  if dr.is_ok {
    io.println("direct-recv bytes=" + dr.value.len().to_str());
  }

  var msg2: Vec[UInt8] = Vec[UInt8].new();
  msg2.push(112u8);
  msg2.push(111u8);
  msg2.push(110u8);
  msg2.push(103u8);
  let wr2 = stream.write(&msg2);
  io.println("write2 ok=" + (if wr2.is_ok { "true" } else { "false" }));

  var got2: Vec[UInt8] = Vec[UInt8].new();
  let rr2 = server_stream.read(&mut got2);
  io.println("method-read ok=" + (if rr2.is_ok { "true" } else { "false" }));
  io.println("method-read bytes=" + got2.len().to_str());

  let c1 = stream.close();
  if c1.is_err { io.println("[WARN] client close"); }
  let c2 = server_stream.close();
  if c2.is_err { io.println("[WARN] server close"); }

  if dr.is_ok && dr.value.len() == 4 && rr2.is_ok && got2.len() == 4 {
    io.println("[PASS] net-roundtrip2");
    return 0;
  }
  io.println("[FAIL] net-roundtrip2");
  return 1;
}
