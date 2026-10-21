// XIOM PULSE -- function-value codegen probe (blocks user stream handlers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A module-level function value and a Vec[fn] are the registration shape
// PULSE needs for user stream handlers. On v0.64.8 the Vec[Handler] path
// generates `store i64 %fnptr, i64* %slot` where the value is a `ptr`
// (invalid IR); a direct call through a module-level function value also
// fails type inference. Run with the pinned compiler; expected to compile
// and return 0 once the compiler supports function values in aggregates.
module probe_fnptr

type Handler = fn(Int) -> Int;

fn inc(x: Int) -> Int { return x + 1; }

var g: Handler = inc;

pub fn main() -> Int {
  let a: Int = inc(41);
  let b: Int = g(41);
  var v: Vec[Handler] = Vec[Handler].new();
  v.push(inc);
  let h = v[0];
  let c: Int = h(41);
  return a + b + c - 126;
}
