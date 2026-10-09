// XIOM PULSE -- project smoke suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: .\scripts\run.ps1 tests\test_smoke.xi
// Exit code = number of failures (0 = green).

module pulse_smoke_tests

use xiom.pulse;
use xiom.io;

fn expect_eq(name: Str, got: Str, want: Str) -> Int {
  if got == want {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name + " got=" + got + " want=" + want);
  return 1;
}

fn check(name: Str, ok: Bool) -> Int {
  return expect_eq(name, if ok { "ok" } else { "not-ok" }, "ok");
}

pub fn main() -> Int {
  var failures: Int = 0;

  failures = failures + expect_eq("pulse_version", pulse_version(), "0.1.2");
  failures = failures + check("str_concat", "a" + "b" == "ab");
  failures = failures + check("int_arith", 2 + 3 * 4 == 14);
  failures = failures + check("str_len", "hello".len() == 5);

  if failures == 0 {
    io.println("pulse-smoke: GREEN");
  } else {
    io.println("pulse-smoke: RED failures=" + failures.to_str());
  }
  return failures;
}
