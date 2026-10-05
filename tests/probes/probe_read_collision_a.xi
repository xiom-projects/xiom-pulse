// probe_read_collision_a -- control: local struct method named `read`,
// NO xiom.io import. Exit 0 = method works, 1 = broken.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_read_collision_a

pub type Sock = { n: Int; }

pub fn Sock.read(self, buf: &mut Vec[UInt8]) -> Result[Int, Int] {
  buf.push(65u8);
  return Ok(7);
}

fn main() -> Int {
  let s = Sock{ n: 1; };
  var v: Vec[UInt8] = Vec[UInt8].new();
  let r = s.read(&mut v);
  if r.is_ok && r.value == 7 && v.len() == 1 {
    return 0;
  }
  return 1;
}
