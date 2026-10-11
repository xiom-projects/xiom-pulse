// XIOM PULSE -- witness for REL-20261011-0317-pulse-7 (module-scope
// fn-pointer reassignment; compiler m265/fde5548e). Pre-fix expectation:
// codegen error "unresolved function symbol handler". Post-fix (m265+):
// exits 0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_fnptr;

use xiom.io;

fn f0(x: Int) -> Int {
  return x + 1;
}

fn f1(x: Int) -> Int {
  return x * 100;
}

var handler: fn(Int) -> Int = f0;

fn main() -> Int {
  var rc: Int = 0;
  if handler(1) != 2 {
    io.println("FAIL call-through initial");
    rc = rc + 1;
  }
  handler = f1;
  if handler(2) != 200 {
    io.println("FAIL call-through reassigned");
    rc = rc + 1;
  }
  handler = f0;
  if handler(3) != 4 {
    io.println("FAIL call-through reassigned-back");
    rc = rc + 1;
  }
  if rc == 0 {
    io.println("OK module-scope fn-ptr call + reassign + reassign-back");
  }
  return rc;
}
