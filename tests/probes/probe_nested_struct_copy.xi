// XIOM PULSE -- compiler repro: copy-modify-write of a nested aggregate
// field (Vec[Registry] -> entries[i] -> Histogram). This pattern is what the
// metrics index-cache optimization used; v0.65.6 fails clang with
// "extractvalue %struct.Vec 0, 0" instead of compiling. The package's own
// labeled helper uses the same copy pattern through a &mut parameter and
// compiles, so the trigger appears to be the module-level Vec + nested field
// access. Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
// SPDX-License-Identifier: MIT OR Apache-2.0
module probe_nested_struct_copy

use xiom.io;
use xiom.metrics;

var g_regs: Vec[Registry] = Vec[Registry].new();

pub fn main() -> Int {
  g_regs.push(metric_registry_new());
  let hb = metric_latency_bounds_ms();
  let l = metric_labels_new();
  let idx = metric_histogram_observe_labeled(&mut g_regs[0], "probe_hist", l, &hb, 1);
  var h = g_regs[0].entries[idx].h;
  metric_histogram_reset(&mut h);
  g_regs[0].entries[idx].h = h;
  var check = g_regs[0].entries[idx].h;
  io.println("nested-struct-copy ok count=" + metric_histogram_count(&check).to_str());
  return 0;
}
