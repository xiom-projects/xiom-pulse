// probe_pkg_kv -- xiom.kv 0.1.0 consumer probe (KNOWN-RED defect gate).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// STATUS 2026-10-07 (v0.64.0, WSL Linux): adoption is BLOCKED.
//   Defect 1: kv_get returns an address-like decimal Str for every key.
//   Defect 2: multi-key writes/overwrites corrupt later reads; kv_get_bytes
//             returns truncated/misaligned values (e.g. len 6 for 9 bytes).
//   Single-key bytes round-trips are correct (kv_get_bytes + from_utf8).
// Repro: docs/repro/kv-get-str-corruption/. PULSE keeps the JSONL store as
// the documented fallback until the packages lane resolves this.
//
// This probe intentionally exits non-zero while the defects reproduce: it is
// the acceptance gate for the future kv adoption, not a green-gate suite
// member yet. Prints are length/equality based (no raw corrupted bytes).
//
// Run from the repo root: scripts/run.sh tests\probes\probe_pkg_kv.xi
module pulse_probe_pkg_kv

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

fn kv_text(s: &KvStore, key: Str) -> Str {
  let gb = kv_get_bytes(s, key);
  if gb.is_err {
    return "";
  }
  if gb.value.is_none {
    return "";
  }
  return Str::from_utf8(gb.value.value);
}

fn kv_probe_cleanup() {
  let _c1 = io.remove_file("kvprobe-seg-0000000001.kv");
  let _c2 = io.remove_file("kvprobe-seg-0000000002.kv");
  let _c3 = io.remove_file("kvprobe-seg-0000000003.kv");
}

pub fn main() -> Int {
  var fails: Int = 0;
  kv_probe_cleanup();

  let or1 = kv_open(".", "kvprobe-", 4096);
  if or1.is_err {
    io.println("[FAIL] kv_open: " + or1.error);
    return 1;
  }
  g_stores.push(or1.value);

  // 1. Single-key bytes round-trip: expected GREEN.
  let p1 = kv_put(&mut g_stores[0], "solo", "abcdefghij");
  let t1 = kv_text(&g_stores[0], "solo");
  if p1.is_err || t1 != "abcdefghij" {
    io.println("[FAIL] single-key bytes roundtrip len=" + t1.len().to_str());
    fails = fails + 1;
  } else {
    io.println("[PASS] single-key bytes roundtrip");
  }

  // 2. kv_get Str path: expected RED (address-like decimal, wrong length).
  let gs = kv_get(&g_stores[0], "solo");
  if gs.is_err || gs.value.is_none {
    io.println("[FAIL] kv_get errored");
    fails = fails + 1;
  } else {
    let got = gs.value.value;
    let ok = got == "abcdefghij";
    var flag: Str = "no";
    if ok { flag = "yes"; }
    io.println("kv_get defect: len=" + got.len().to_str() + " matches_expected=" + flag);
    if ok {
      io.println("[PASS] kv_get Str path (defect not reproduced on this build)");
    } else {
      io.println("[FAIL] kv_get Str path corruption reproduced");
      fails = fails + 1;
    }
  }

  // 3. Multi-key + overwrite stability: expected RED on v0.64.0.
  let _p2 = kv_put(&mut g_stores[0], "a", "v1");
  let _p3 = kv_put(&mut g_stores[0], "b", "v2");
  let _p4 = kv_put(&mut g_stores[0], "a", "v1b");
  let t2 = kv_text(&g_stores[0], "b");
  if t2 != "v2" {
    io.println("[FAIL] multi-key bytes read corrupted (len=" + t2.len().to_str() + ")");
    fails = fails + 1;
  } else {
    io.println("[PASS] multi-key bytes read stable");
  }

  kv_close(&mut g_stores[0]);
  kv_probe_cleanup();

  if fails == 0 {
    io.println("[PASS] pkg-kv (unexpected: defects did not reproduce)");
    return 0;
  }
  io.println("[FAIL] pkg-kv blocked-by-defects fails=" + fails.to_str());
  return fails;
}
