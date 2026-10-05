// probe_module_pkg_init -- module-scope initialization from a package ctor.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// v0.64.0: a module-level `var` initialized by a cross-package constructor
// call crashes before main (0xC0000005, no output). Workaround: keep package
// aggregates in function/caller-owned values.
module pulse_probe_module_pkg_init

use xiom.rate;
use xiom.io;

var b = rate_keyed_new(1, 1);

fn main() -> Int {
  io.println("module-pkg-init ok");
  return 0;
}
