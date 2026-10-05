// probe_missing_field -- struct literal with a missing field.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// v0.64.0: compiling this silently succeeds; reading the omitted Vec field
// crashes with 0xC0000005 (uninitialized value). A complete initializer
// returns 0. Expected on a safe compiler: T001 missing field 'b'.
module pulse_probe_missing_field

use xiom.io;

pub type Pair = { a: Int; b: Vec[UInt8]; }

fn main() -> Int {
  let p = Pair{ a: 1; };
  io.println("missing-field a=" + p.a.to_str());
  io.println("missing-field b.len=" + p.b.len().to_str());
  return 0;
}
