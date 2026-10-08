// probe_adopt_smoke -- combined adoption smoke with crash-durable steps.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Steps go to /tmp/pulse-adopt-steps.txt (io.println output is block-buffered
// and lost when a program crashes before exit).
module pulse_probe_adopt_smoke

use xiom.io;
use xiom.string;
use xiom.convert;
use xiom.pulse.metrics;
use xiom.pulse.session;
use xiom.pulse.cors;
use xiom.pulse.app;

const STEPS: Str = "/tmp/pulse-adopt-steps.txt";

fn step(n: Int) {
  let _a = io.append_line(STEPS, convert_int(n));
}

fn convert_int(n: Int) -> Str {
  return convert.int_to_string(n);
}

pub fn main() -> Int {
  step(1);
  metrics.metrics_reset();
  step(2);
  metrics.metrics_record(200, 10);
  step(3);
  let mr = metrics.metrics_render();
  step(4);
  if mr.len() == 0 {
    io.println("[FAIL] metrics render empty");
    return 1;
  }
  session.session_reset();
  step(5);
  let c0 = session.session_count();
  step(11);
  if c0 != 0 {
    io.println("[FAIL] count after reset=" + c0.to_str());
    return 1;
  }
  let sid = session.session_create("probe", 60);
  step(6);
  if sid.len() != 32 {
    io.println("[FAIL] session id len=" + sid.len().to_str());
    return 1;
  }
  let u = session.session_get(sid);
  step(7);
  if u != "probe" {
    io.println("[FAIL] session user=[" + u + "]");
    return 1;
  }
  let t = session.csrf_new_token();
  step(8);
  if t.len() != 32 {
    io.println("[FAIL] csrf len=" + t.len().to_str());
    return 1;
  }
  let ok = session.csrf_matches("sid=x; csrf=" + t + "; a=1", t);
  step(9);
  if !ok {
    io.println("[FAIL] csrf match");
    return 1;
  }
  session.session_reset();
  step(10);
  io.println("[PASS] adopt-smoke");
  return 0;
}
