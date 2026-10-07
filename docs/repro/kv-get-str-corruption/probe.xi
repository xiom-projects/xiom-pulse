// probe.xi -- xiom.kv 0.1.0 kv_get Str corruption (PULSE consumer repro).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// v0.64.0 (WSL Linux, first observed 2026-10-07): after kv_put, kv_get
// returns a decimal stack-address-like Str (e.g. "97116368003104") for
// every key, while kv_get_bytes returns the stored bytes correctly.
//
// Run from the repo root: scripts/run.sh docs\repro\kv-get-str-corruption\probe.xi
// Prints the observed values and exits 0 (repro documents behavior; the
// assertion lines report PASS/FAIL as diagnostics only).
module pulse_repro_kv_get_str

use xiom.kv;
use xiom.string;
use xiom.io;

var g_stores: Vec[KvStore] = Vec[KvStore].new();

fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

pub fn main() -> Int {
  let _c1 = io.remove_file("kvrepro-seg-0000000001.kv");
  let _c2 = io.remove_file("kvrepro-seg-0000000002.kv");

  let or1 = kv_open(".", "kvrepro-", 4096);
  if or1.is_err {
    io.println("[FAIL] open: " + or1.error);
    return 1;
  }
  g_stores.push(or1.value);

  let p1 = kv_put(&mut g_stores[0], "k", "abcdefghij");
  if p1.is_err {
    io.println("[FAIL] put: " + p1.error);
    return 1;
  }

  // Expected: "abcdefghij". Observed on v0.64.0: an address-like decimal.
  let gs = kv_get(&g_stores[0], "k");
  if gs.is_err || gs.value.is_none {
    io.println("[FAIL] get");
    return 1;
  }
  io.println("kv_get      =[" + gs.value.value + "]  (expected [abcdefghij])");

  // Bytes path is correct; the stored text round-trips via from_utf8.
  let gb = kv_get_bytes(&g_stores[0], "k");
  if gb.is_err || gb.value.is_none {
    io.println("[FAIL] get_bytes");
    return 1;
  }
  let stored: Vec[UInt8] = gb.value.value;
  io.println("kv_get_bytes=[" + Str::from_utf8(stored) + "]  len=" + stored.len().to_str());

  // Also verify Str::from_utf8 of a locally built vector works (control).
  let local: Vec[UInt8] = str_to_bytes("abcdefghij");
  io.println("control     =[" + Str::from_utf8(local) + "]");

  kv_close(&mut g_stores[0]);
  let _r1 = io.remove_file("kvrepro-seg-0000000001.kv");
  let _r2 = io.remove_file("kvrepro-seg-0000000002.kv");
  return 0;
}
