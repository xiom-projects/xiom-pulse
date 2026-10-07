// probe.xi -- m212 dependency-root resolution probe (dotted canonical key).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run from this directory: xiom --check probe.xi
// Expected (bug): T001 -- `xiom.rate` never matches the installed
// xiom-rate-0.2.0/ directory because dep.name keeps its dots.
module m212probe

use xiom.rate;

fn main() -> Int {
  var b = rate.rate_keyed_new(2, 1);
  if rate.rate_keyed_allow(&mut b, "k", 0) {
    return 0;
  }
  return 1;
}
