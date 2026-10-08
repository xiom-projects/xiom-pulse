// probe_audit_rotate -- audit-trail rotation helper (src/audit.xi).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run from the repo root (creates/removes pulse-audit-rotate-test.log*):
//   scripts/run.sh tests\probes\probe_audit_rotate.xi
// Exit code = failures (0 = green).
module pulse_probe_audit_rotate

use xiom.io;
use xiom.pulse.audit;

const P: Str = "pulse-audit-rotate-test.log";
const B1: Str = "pulse-audit-rotate-test.log.1";

fn mk_long(n: Int) -> Str {
  var s: Str = "";
  var i: Int = 0;
  while i < n {
    s = s + "x";
    i = i + 1;
  }
  return s;
}

pub fn main() -> Int {
  var fails: Int = 0;
  let _c1 = io.remove_file(P);
  let _c2 = io.remove_file(B1);

  // 1. disabled threshold (<= 0): never rotates.
  let w1 = io.write_file(P, mk_long(50) + "\n");
  if w1.is_err {
    io.println("[FAIL] setup write");
    return 1;
  }
  let r1 = audit.audit_rotate_if_needed(P, 0);
  if !r1 || !io.file_exists(P) || io.file_exists(B1) {
    io.println("[FAIL] disabled threshold");
    fails = fails + 1;
  } else {
    io.println("[PASS] disabled threshold");
  }

  // 2. under limit: no rotation.
  let r2 = audit.audit_rotate_if_needed(P, 1000);
  if !r2 || !io.file_exists(P) || io.file_exists(B1) {
    io.println("[FAIL] under limit");
    fails = fails + 1;
  } else {
    io.println("[PASS] under limit");
  }

  // 3. over limit: rotates to .1 and preserves the content.
  let w2 = io.write_file(P, mk_long(200) + "\n");
  if w2.is_err {
    io.println("[FAIL] over-limit write");
    return 1;
  }
  let r3 = audit.audit_rotate_if_needed(P, 100);
  if !r3 || io.file_exists(P) || !io.file_exists(B1) {
    io.println("[FAIL] over limit rotate");
    fails = fails + 1;
  } else {
    let rr = io.read_file(B1);
    if rr.is_err || rr.value.len() != 201 {
      io.println("[FAIL] rotated content");
      fails = fails + 1;
    } else {
      io.println("[PASS] over limit rotate + content");
    }
  }

  // 4. missing active file: no-op true.
  let r4 = audit.audit_rotate_if_needed(P, 100);
  if !r4 {
    io.println("[FAIL] missing file no-op");
    fails = fails + 1;
  } else {
    io.println("[PASS] missing file no-op");
  }

  // 5. an existing .1 is replaced by the next rotation.
  let w3 = io.write_file(P, mk_long(200));
  let w4 = io.write_file(B1, "old");
  if w3.is_err || w4.is_err {
    io.println("[FAIL] second setup");
    return 1;
  }
  let r5 = audit.audit_rotate_if_needed(P, 100);
  if !r5 || io.file_exists(P) {
    io.println("[FAIL] second rotate");
    fails = fails + 1;
  } else {
    let rr2 = io.read_file(B1);
    if rr2.is_err || rr2.value.len() != 200 {
      io.println("[FAIL] second rotate replaces .1");
      fails = fails + 1;
    } else {
      io.println("[PASS] second rotate replaces .1");
    }
  }

  let _c3 = io.remove_file(P);
  let _c4 = io.remove_file(B1);

  if fails == 0 {
    io.println("[PASS] audit-rotate");
    return 0;
  }
  io.println("[FAIL] audit-rotate fails=" + fails.to_str());
  return fails;
}
