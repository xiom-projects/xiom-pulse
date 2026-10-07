// probe_session_inline -- isolate registry xiom.session calls with durable
// step logging (no PULSE wrappers involved).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_session_inline

use xiom.io;
use xiom.convert;
use xiom.session;
use xiom.pulse.metrics;

const STEPS: Str = "/tmp/pulse-session-inline-steps.txt";

var g_vs: Vec[SessionStore] = Vec[SessionStore].new();

fn step(n: Int) {
  let _a = io.append_line(STEPS, convert.int_to_string(n));
}

pub fn main() -> Int {
  step(1);
  g_vs.push(session_store_new(60000));
  step(2);
  let c1 = session_count(&g_vs[0]);
  step(3);
  if c1 != 0 {
    io.println("[FAIL] count=" + c1.to_str());
    return 1;
  }
  let r1 = session_create(&mut g_vs[0], 1000);
  step(4);
  if r1.is_err {
    io.println("[FAIL] create");
    return 1;
  }
  let sid = r1.value;
  let _s = session_set(&mut g_vs[0], sid, "user", "inline", 1000);
  step(5);
  let v0 = session_value(&g_vs[0], sid, "user", 1000);
  step(6);
  if v0.is_none || v0.value != "inline" {
    io.println("[FAIL] value");
    return 1;
  }
  step(7);
  // Isolation B: reassign the module-level Vec, then push a fresh store.
  g_vs = Vec[SessionStore].new();
  step(8);
  g_vs.push(session_store_new(60000));
  step(9);
  let c2 = session_count(&g_vs[0]);
  step(10);
  if c2 != 0 {
    io.println("[FAIL] count2=" + c2.to_str());
    return 1;
  }
  // Isolation C: a second module holding its own module-level Vec of a
  // DIFFERENT package struct (xiom.pulse.metrics owns Vec[Registry]).
  metrics.metrics_reset();
  step(11);
  metrics.metrics_record(200, 1);
  step(12);
  let mr = metrics.metrics_render();
  step(13);
  if mr.len() == 0 {
    io.println("[FAIL] metrics render");
    return 1;
  }
  g_vs.push(session_store_new(1000));
  step(14);
  let c3 = session_count(&g_vs[1]);
  step(15);
  if c3 != 0 {
    io.println("[FAIL] count3=" + c3.to_str());
    return 1;
  }
  io.println("[PASS] session-inline");
  return 0;
}
