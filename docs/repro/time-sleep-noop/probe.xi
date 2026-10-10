// probe_time_sleep -- C-PULSE-18: does time.sleep_ms actually sleep?
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Observed on v0.64.2 (Windows lane stdlib; PULSE ORBITDB crash-harness
// writer raced to its own timeout): `time.sleep_ms(500)` returns
// immediately (`slept_delta_ms=0`). Any pacing/backoff/harness loop that
// relies on it degenerates into a busy spin.
//
// Run: .\scripts\run.ps1 docs\repro\time-sleep-noop\probe.xi
// Exit 0 = sleep worked (>=450ms), 1 = no-op reproduced.
module probe_time_sleep

use xiom.io;
use xiom.time;

pub fn main() -> Int {
  let t0 = time.monotonic_ms();
  time.sleep_ms(500);
  let t1 = time.monotonic_ms();
  let delta = t1 - t0;
  io.println("slept_delta_ms=" + delta.to_str());
  if delta >= 450 {
    io.println("[PASS] time.sleep_ms works");
    return 0;
  }
  io.println("[BUG] time.sleep_ms is a no-op (C-PULSE-18)");
  return 1;
}
