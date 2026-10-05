// probe_const_to_str -- C-PULSE-05 discriminator: const-receiver `.to_str()`
// on v0.64.0. Expect "41"; any W005 warning or empty render = still broken.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_const_to_str

use xiom.io;

const V: Int = 41;

fn main() -> Int {
  io.println("const-to-str=[" + V.to_str() + "]");
  if V.to_str() == "41" {
    io.println("[PASS] const-to-str");
    return 0;
  }
  io.println("[FAIL] const-to-str");
  return 1;
}
