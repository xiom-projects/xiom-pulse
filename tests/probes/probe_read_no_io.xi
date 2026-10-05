// probe_read_no_io -- does the io module's foreign `read` declaration
// shadow xiom.net's TcpStream.read? No xiom.io import, exit-code only.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Exit: 0 = read worked; 1 = listen/connect/accept failed; 2 = write failed;
//       3 = read failed; 4 = wrong byte count.
module pulse_probe_read_no_io

use xiom.net;

fn main() -> Int {
  let lr = net.tcp_listen("127.0.0.1", 19084);
  if lr.is_err { return 1; }
  let listener = lr.value;

  let cr = net.tcp_connect("127.0.0.1", 19084);
  if cr.is_err { return 1; }
  let stream = cr.value;

  let ar = listener.accept();
  if ar.is_err { return 1; }
  let pair = ar.value;
  let server_stream = pair.0;

  var msg: Vec[UInt8] = Vec[UInt8].new();
  msg.push(112u8);
  msg.push(105u8);
  msg.push(110u8);
  msg.push(103u8);
  let wr = stream.write(&msg);
  if wr.is_err { return 2; }

  var got: Vec[UInt8] = Vec[UInt8].new();
  let rr = server_stream.read(&mut got);
  if rr.is_err { return 3; }
  if got.len() != 4 { return 4; }

  let c1 = stream.close();
  let c2 = server_stream.close();
  if c1.is_err { return 5; }
  if c2.is_err { return 5; }
  return 0;
}
