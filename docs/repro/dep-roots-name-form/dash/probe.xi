// probe.xi -- m212 dependency-root resolution probe (dash-form key).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run from this directory: xiom --check probe.xi
// Exit 0 = [dependencies] xiom-rate = "0.2.0" resolved to the installed
// package without any source-roots entry.
module m212probe

use xiom.rate;

fn main() -> Int {
  var b = rate.rate_keyed_new(2, 1);
  if rate.rate_keyed_allow(&mut b, "k", 0) {
    return 0;
  }
  return 1;
}
