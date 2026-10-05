// probe_pkg_router -- registry-package consumption check: xiom.router 0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: .\scripts\run.ps1 tests\probes\probe_pkg_router.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_router

use xiom.router;
use xiom.io;

pub fn main() -> Int {
  var fails: Int = 0;
  var t = router_new();
  let a = router_add(&mut t, "GET", "/health");
  let b = router_add(&mut t, "GET", "/api/items/:id");
  let c = router_add(&mut t, "POST", "/api/items/:id");
  if a.is_err || b.is_err || c.is_err {
    io.println("[FAIL] router_add");
    return 1;
  }
  if router_count(&t) != 3 {
    io.println("[FAIL] router_count");
    fails = fails + 1;
  } else {
    io.println("[PASS] router_count=3");
  }

  let m1 = router_match(&t, "GET", "/health");
  if m1.code != 200 || m1.index != 0 {
    io.println("[FAIL] match health");
    fails = fails + 1;
  } else {
    io.println("[PASS] match health");
  }

  let m2 = router_match(&t, "GET", "/api/items/42");
  if m2.code != 200 || m2.params.len() != 1 {
    io.println("[FAIL] match param");
    fails = fails + 1;
  } else {
    let p = m2.params[0];
    if p.name != "id" || p.value != "42" {
      io.println("[FAIL] param capture name=" + p.name + " value=" + p.value);
      fails = fails + 1;
    } else {
      io.println("[PASS] param capture id=42");
    }
  }

  let m3 = router_match(&t, "DELETE", "/health");
  if m3.code != 405 {
    io.println("[FAIL] 405 expected");
    fails = fails + 1;
  } else {
    io.println("[PASS] 405");
  }

  let m4 = router_match(&t, "GET", "/nope");
  if m4.code != 404 {
    io.println("[FAIL] 404 expected");
    fails = fails + 1;
  } else {
    io.println("[PASS] 404");
  }

  let allow = router_allowed_methods(&t, "/api/items/9");
  if allow.len() != 2 {
    io.println("[FAIL] allow len=" + allow.len().to_str());
    fails = fails + 1;
  } else {
    io.println("[PASS] allow methods");
  }

  let bad = router_add(&mut t, "GET", "no-slash");
  if bad.is_err {
    io.println("[PASS] invalid pattern rejected");
  } else {
    io.println("[FAIL] invalid pattern accepted");
    fails = fails + 1;
  }

  if fails == 0 {
    io.println("[PASS] pkg-router");
    return 0;
  }
  io.println("[FAIL] pkg-router fails=" + fails.to_str());
  return fails;
}
