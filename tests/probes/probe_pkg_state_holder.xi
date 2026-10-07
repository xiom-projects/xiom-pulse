// probe_pkg_state_holder -- C-PULSE-07 workaround pattern: module-scope
// package-aggregate state held inside a plain Vec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// v0.64.0 crashes when a module-level var is initialized by a cross-package
// constructor (docs/repro/module-scope-package-init). Plain `Vec[T].new()` at
// module scope is safe; functions push the package aggregate on first use
// and hand out `&mut holder[0]`. This probe pins that pattern before the
// registry-wave adoption (metrics/session/kv) relies on it.
//
// Run: .\scripts\run.ps1 tests\probes\probe_pkg_state_holder.xi
//      scripts/run.sh   tests/probes/probe_pkg_state_holder.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_state_holder

use xiom.metrics;
use xiom.string;
use xiom.io;

var g_regs: Vec[Registry] = Vec[Registry].new();

fn ensure() {
  if g_regs.len() == 0 {
    g_regs.push(metric_registry_new());
  }
}

pub fn main() -> Int {
  ensure();
  let labels = metric_labels_new();
  metric_counter_inc_labeled(&mut g_regs[0], "holder_total", labels, 1);
  let txt = metric_exposition(&g_regs[0]);
  if !string.str_contains(txt, "holder_total 1") {
    io.println("[FAIL] holder counter missing: " + txt);
    return 1;
  }
  io.println("[PASS] holder pattern (registry in Vec)");
  return 0;
}
