// probe_method_matrix -- isolate which method shape breaks on v0.63.1.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Bitmask exit code: A=1 read+Result+push; B=2 take2+Result+push;
// C=4 read+Int+push; D=8 take3+Result+no-vec; E=16 read5+Result+vec-no-push.
// 0 = all shapes correct.
module pulse_probe_method_matrix

pub type SockA = { n: Int; }
pub type SockB = { n: Int; }
pub type SockC = { n: Int; }
pub type SockD = { n: Int; }
pub type SockE = { n: Int; }

pub fn SockA.read(self, buf: &mut Vec[UInt8]) -> Result[Int, Int] {
  buf.push(65u8);
  return Ok(7);
}

pub fn SockB.take2(self, buf: &mut Vec[UInt8]) -> Result[Int, Int] {
  buf.push(65u8);
  return Ok(7);
}

pub fn SockC.read(self, buf: &mut Vec[UInt8]) -> Int {
  buf.push(65u8);
  return 7;
}

pub fn SockD.take3(self) -> Result[Int, Int] {
  return Ok(7);
}

pub fn SockE.read5(self, buf: &mut Vec[UInt8]) -> Result[Int, Int] {
  return Ok(7);
}

fn main() -> Int {
  var bad: Int = 0;

  let a = SockA{ n: 1; };
  var va: Vec[UInt8] = Vec[UInt8].new();
  let ra = a.read(&mut va);
  if !(ra.is_ok && ra.value == 7 && va.len() == 1) { bad = bad + 1; }

  let b = SockB{ n: 1; };
  var vb: Vec[UInt8] = Vec[UInt8].new();
  let rb = b.take2(&mut vb);
  if !(rb.is_ok && rb.value == 7 && vb.len() == 1) { bad = bad + 2; }

  let c = SockC{ n: 1; };
  var vc: Vec[UInt8] = Vec[UInt8].new();
  let rc = c.read(&mut vc);
  if !(rc == 7 && vc.len() == 1) { bad = bad + 4; }

  let d = SockD{ n: 1; };
  let rd = d.take3();
  if !(rd.is_ok && rd.value == 7) { bad = bad + 8; }

  let e = SockE{ n: 1; };
  var ve: Vec[UInt8] = Vec[UInt8].new();
  let re = e.read5(&mut ve);
  if !(re.is_ok && re.value == 7) { bad = bad + 16; }

  return bad;
}
