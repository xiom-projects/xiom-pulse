// probe_read_collision_b -- same local struct method named `read`, but with
// `use xiom.io;` in scope (as any app that logs has). Exit 0 = method works,
// 1 = broken; prints the observation through io.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_read_collision_b

use xiom.io;

pub type Sock = { n: Int; }

pub fn Sock.read(self, buf: &mut Vec[UInt8]) -> Result[Int, Int] {
  buf.push(65u8);
  return Ok(7);
}

fn main() -> Int {
  let s = Sock{ n: 1; };
  var v: Vec[UInt8] = Vec[UInt8].new();
  let r = s.read(&mut v);
  let ok = r.is_ok && r.value == 7 && v.len() == 1;
  if ok {
    io.println("[PASS] local-read-with-io");
    return 0;
  }
  io.println("[FAIL] local-read-with-io");
  return 1;
}
