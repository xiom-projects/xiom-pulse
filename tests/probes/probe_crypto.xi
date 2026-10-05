// probe_crypto -- Step 0d: stdlib crypto linkability A/B.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A/B under XIOM_RUNTIME_DIR:
//   WITH    -> expect link ok + KAT match, exit 0
//   WITHOUT -> expect lld-link: undefined symbol: xiom_sha256_hash (upstream
//              crypto-link finding; the runtime-dir override links sha256_sw.c)
// Run:
//   .\scripts\run.ps1 tests\probes\probe_crypto.xi
//   .\scripts\run.ps1 tests\probes\probe_crypto.xi -NoRuntimeDir
module pulse_probe_crypto

use xiom.crypto;
use xiom.io;

fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn main() -> Int {
  let bytes: Vec[UInt8] = str_to_bytes("abc");
  let hex = crypto.sha256_hex(&bytes);
  io.println("sha256(abc)=" + hex);
  if hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
    io.println("[PASS] crypto-sha256");
    return 0;
  }
  io.println("[FAIL] crypto-sha256");
  return 1;
}
