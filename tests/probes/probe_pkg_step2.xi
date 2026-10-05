// probe_pkg_step2 -- registry-package consumption for the Step 2 skeleton:
// xiom.cookie v0.1.1 + xiom.jwt v0.1.1 (structural decode, no signature).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: .\scripts\run.ps1 tests\probes\probe_pkg_step2.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_step2

use xiom.cookie;
use xiom.jwt;
use xiom.io;
use xiom.string;

pub fn main() -> Int {
  var fails: Int = 0;

  // --- xiom.cookie ---------------------------------------------------------
  let jar = cookie_parse_request("session=abc123; theme=dark");
  if cookie_count(&jar) != 2 {
    io.println("[FAIL] cookie count=" + cookie_count(&jar).to_str());
    fails = fails + 1;
  } else {
    io.println("[PASS] cookie count=2");
  }
  let sess = cookie_get(&jar, "session");
  if sess.is_none {
    io.println("[FAIL] cookie session missing");
    fails = fails + 1;
  } else if sess.value != "abc123" {
    io.println("[FAIL] cookie session=" + sess.value);
    fails = fails + 1;
  } else {
    io.println("[PASS] cookie session=abc123");
  }

  let sc = cookie_parse_set("sid=z9; Path=/; HttpOnly");
  if sc.is_err {
    io.println("[FAIL] parse_set");
    fails = fails + 1;
  } else {
    let scs = cookie_serialize_set(&sc.value);
    if !string.str_contains(scs, "sid=z9") {
      io.println("[FAIL] serialize_set=" + scs);
      fails = fails + 1;
    } else {
      io.println("[PASS] set-cookie serialize");
    }
  }

  // --- xiom.jwt (structural) ----------------------------------------------
  let tok: Str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwdWxzZSIsImV4cCI6NDEwMjQ0NDgwMH0.c2ln";
  if !jwt_is_shaped(tok) {
    io.println("[FAIL] jwt shape");
    fails = fails + 1;
  } else {
    io.println("[PASS] jwt shape");
  }
  let alg = jwt_alg(tok);
  if alg.is_err || alg.value != "HS256" {
    io.println("[FAIL] jwt alg");
    fails = fails + 1;
  } else {
    io.println("[PASS] jwt alg=HS256");
  }
  let sub = jwt_claim_str(tok, "sub");
  if sub.is_err || sub.value != "pulse" {
    io.println("[FAIL] jwt claim sub");
    fails = fails + 1;
  } else {
    io.println("[PASS] jwt sub=pulse");
  }
  let exp = jwt_expired(tok, 1700000000);
  if exp.is_err || exp.value {
    io.println("[FAIL] jwt exp (expected not expired)");
    fails = fails + 1;
  } else {
    io.println("[PASS] jwt exp not expired");
  }
  let expq = jwt_expired(tok, 4200000000);
  if expq.is_err || !expq.value {
    io.println("[FAIL] jwt exp (expected expired)");
    fails = fails + 1;
  } else {
    io.println("[PASS] jwt exp expired");
  }

  if fails == 0 {
    io.println("[PASS] pkg-step2");
    return 0;
  }
  io.println("[FAIL] pkg-step2 fails=" + fails.to_str());
  return fails;
}
