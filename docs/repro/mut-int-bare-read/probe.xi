// probe_mut_int_ref -- &mut Int read-side semantics on v0.63.1.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Matrix: bare `p = p + 1` read on the RHS vs explicit `*p = *p + 1`;
// bare `return p` vs `return *p`.
// Exit code = bitmask of wrong shapes: bit0 bare_add, bit1 deref_add,
// bit2 bare_read, bit3 deref_read. Expected 0 on a correct compiler.
module pulse_probe_mut_int_ref

use xiom.io;

fn bare_add(p: &mut Int) -> Int {
  p = p + 1;
  return p;
}

fn deref_add(p: &mut Int) -> Int {
  *p = *p + 1;
  return *p;
}

fn bare_read(p: &mut Int) -> Int {
  return p;
}

fn deref_read(p: &mut Int) -> Int {
  return *p;
}

pub fn main() -> Int {
  var a: Int = 10;
  let r1 = bare_add(&mut a);
  io.println("bare_add a=" + a.to_str() + " r=" + r1.to_str());

  var b: Int = 10;
  let r2 = deref_add(&mut b);
  io.println("deref_add b=" + b.to_str() + " r=" + r2.to_str());

  var c: Int = 10;
  let r3 = bare_read(&mut c);
  io.println("bare_read c=" + c.to_str() + " r=" + r3.to_str());

  var d: Int = 10;
  let r4 = deref_read(&mut d);
  io.println("deref_read d=" + d.to_str() + " r=" + r4.to_str());

  var bad: Int = 0;
  if a != 11 || r1 != 11 { bad = bad + 1; }
  if b != 11 || r2 != 11 { bad = bad + 2; }
  if r3 != 10 { bad = bad + 4; }
  if r4 != 10 { bad = bad + 8; }
  io.println("mut-int-ref bad=" + bad.to_str());
  return bad;
}
