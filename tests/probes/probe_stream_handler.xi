// XIOM PULSE -- exact StreamHandler shape for the user stream registry.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// This is the fn value PULSE stores per stream route:
//   fn(Int, &Vec[UInt8], &PulseRequest) -> (Int, Int)
// On v0.64.8 the Vec path lost the signature (call i64, tuple fields both
// read the low word). Compiler main c9b1f1009 fixes the alias/env path;
// this probe is the PULSE acceptance test for restoring the registry.
module probe_stream_handler

use xiom.io;
use xiom.pulse.http;

type StreamHandler = fn(Int, &Vec[UInt8], &PulseRequest) -> (Int, Int);

fn handler(_fd: Int, _raw: &Vec[UInt8], _req: &PulseRequest) -> (Int, Int) {
  return (4, 7);
}

var g: StreamHandler = handler;

pub fn main() -> Int {
  let raw = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: x\r\n\r\n");
  let req = http.parse_request(&raw);
  let a = g(0, &raw, &req);
  var v: Vec[StreamHandler] = Vec[StreamHandler].new();
  v.push(handler);
  let h = v[0];
  let b = h(0, &raw, &req);
  io.println("var=" + a.0.to_str() + "," + a.1.to_str());
  io.println("vec=" + b.0.to_str() + "," + b.1.to_str());
  if a.0 == 4 && a.1 == 7 && b.0 == 4 && b.1 == 7 { return 0; }
  return 1;
}
