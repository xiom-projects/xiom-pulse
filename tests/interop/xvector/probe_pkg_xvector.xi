// probe_pkg_xvector -- PULSE consumer conformance for the XVECTOR lane.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Source-level composition (see xiom.toml here): consumes
// xiom-xvector/src @ local checkout (integration doc pin de1db14 +
// handshake commit; docs/PULSE-INTEGRATION.md).
//
// Scenarios implemented (from xiom-xvector/docs/PULSE-INTEGRATION.md §5):
//   1. upsert/search round-trip, exact Flat baseline (k=1/k=5/k=10000)
//   3. reopen integrity (wal_persist -> wal_load -> engine_recover)
//   4. top-k edges (k=0 rejected, k > live size, empty index)
//   5. dimension limits (dim=1, dim=0 rejected, query mismatch rejected)
//   6. delete/re-add
//   7. duplicate ids never duplicate hits
//   8. wal prefix/torn-tail tolerance (cut the last line)
//
// Run (sibling tree present): .\scripts\run.ps1 tests\interop\xvector\probe_pkg_xvector.xi
// Exit code = failure count (0 = green).
module pulse_probe_pkg_xvector

use xiom.io;
use xiom.convert;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.durability.wal_file;
use xiom.vector.query.search_service;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;

var g_fails: Int = 0;

fn expect(name: Str, ok: Bool) {
  if ok {
    io.println("[PASS] " + name);
  } else {
    io.println("[FAIL] " + name);
    g_fails = g_fails + 1;
  }
}

fn mk2(x: Float32, y: Float32) -> Vector {
  var v = Vector.new(2);
  v.set(0, x);
  v.set(1, y);
  return v;
}

// str_cut returns s[0..end): local byte slice so the probe keeps imports
// minimal (Str is byte-transparent).
fn str_cut(s: Str, end: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < end && i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return Str::from_utf8(out);
}

pub fn main() -> Int {
  let dir = "tests/interop/xvector/.tmp";
  if !io.is_dir(dir) {
    let _mk = io.create_dir(dir);
  }
  let walpath = dir + "/vectors.wal";
  let _rw = io.remove_file(walpath);

  // --- 1. round-trip against the exact Flat baseline ------------------------
  var eng = engine_new();
  let cc = create_collection(&mut eng, 2, DistanceMetric.Cosine);
  expect("create_collection", !cc.is_err);
  var i: Int = 0;
  var ups_ok: Bool = true;
  while i < 100 {
    // deterministic parabola cloud; id 42 sits at (1.0, 0.42)
    let y: Float32 = (i as Float32) / 100.0;
    let u = upsert(&mut eng, i, mk2(1.0, y));
    if u.is_err { ups_ok = false; }
    i = i + 1;
  }
  expect("upsert 100", ups_ok);
  let q42 = mk2(1.0, 0.42);
  let s1 = search(&eng, &q42, 1);
  expect("search k=1 ok", !s1.is_err);
  if !s1.is_err {
    expect("search k=1 identity", s1.value.items.len() == 1 && s1.value.items[0].id == 42);
  }
  let s5 = search(&eng, &q42, 5);
  expect("search k=5 len", !s5.is_err && s5.value.items.len() == 5);
  if !s5.is_err {
    expect("search k=5 nearest", s5.value.items[0].id == 42);
  }
  let sbig = search(&eng, &q42, 10000);
  expect("search k=10000 caps at live size", !sbig.is_err && sbig.value.items.len() == 100);

  // --- 4. top-k edges -------------------------------------------------------
  // NOTE: raw `search(k=0)` is a CONTRACT TRAP (`requires: k > 0` in
  // engine_search, core.xi:706) -- not an Err. Asserting traps needs a
  // runner-level negative probe; PULSE keeps k >= 1 at the driver seam.
  let sk = search(&eng, &q42, 500);
  expect("search k>live", !sk.is_err && sk.value.items.len() == 100);
  var empty_eng = engine_new();
  let ec = create_collection(&mut empty_eng, 2, DistanceMetric.Cosine);
  expect("empty collection", !ec.is_err);
  let se = search(&empty_eng, &q42, 5);
  expect("empty search ok", !se.is_err && se.value.items.len() == 0);

  // --- 5. dimension limits --------------------------------------------------
  // dim=0 is likewise a CONTRACT TRAP (`requires: dim >= 1`); the
  // assertable out-of-range edge is dim > 65536 -> Err.
  var v3 = Vector.new(3);
  v3.set(0, 1.0);
  v3.set(1, 0.0);
  v3.set(2, 0.0);
  let mism = search(&eng, &v3, 1);
  expect("query dim mismatch rejected", mism.is_err);
  var eng1 = engine_new();
  let c1 = create_collection(&mut eng1, 1, DistanceMetric.Euclidean);
  expect("dim=1 accepted", !c1.is_err);
  var eng0 = engine_new();
  let c0 = create_collection(&mut eng0, 70000, DistanceMetric.Euclidean);
  expect("dim>65536 rejected", c0.is_err);
  var engmax = engine_new();
  let cmax = create_collection(&mut engmax, 65536, DistanceMetric.Cosine);
  expect("dim=65536 accepted", !cmax.is_err);

  // --- 6/7. delete/re-add + duplicate ids -----------------------------------
  let dp = delete_point(&mut eng, 7);
  expect("delete_point", !dp.is_err);
  expect("deleted gone", get_point(&eng, 7).is_none);
  let ra = upsert(&mut eng, 7, mk2(1.0, 0.07));
  expect("re-add", !ra.is_err);
  expect("re-added present", !get_point(&eng, 7).is_none);
  let dup = upsert(&mut eng, 9, mk2(0.0, 1.0));
  expect("duplicate upsert overwrites", !dup.is_err);
  let sdup = search(&eng, &mk2(0.0, 1.0), 3);
  var nine_count: Int = 0;
  if !sdup.is_err {
    var di: Int = 0;
    while di < sdup.value.items.len() {
      if sdup.value.items[di].id == 9 { nine_count = nine_count + 1; }
      di = di + 1;
    }
  }
  expect("duplicate id once", nine_count == 1);
  let sall = search(&eng, &q42, 10000);
  expect("live size unchanged", !sall.is_err && sall.value.items.len() == 100);

  // --- 3. reopen: checkpoint + recover --------------------------------------
  let wp = wal_persist(&eng.wal, walpath);
  expect("wal_persist", wp);
  var wr = wal_load(walpath);
  var eng2 = engine_recover(&wr, 2, DistanceMetric.Cosine);
  let r1 = search(&eng2, &q42, 1);
  expect("recovered search ok", !r1.is_err);
  if !r1.is_err {
    expect("recovered identity", r1.value.items.len() == 1 && r1.value.items[0].id == 42);
  }
  expect("recovered payload point", !get_point(&eng2, 42).is_none);

  // --- 8. torn tail: cut the last line, recover the prefix ------------------
  let rf = io.read_file(walpath);
  var cut_ok: Bool = false;
  if rf.is_ok {
    var text: Str = rf.value;
    var last_nl: Int = -1;
    var ci: Int = text.len() - 2; // leave the final newline's line out
    while ci >= 0 {
      if text.byte_at(ci) == 10u8 {
        last_nl = ci;
        break;
      }
      ci = ci - 1;
    }
    if last_nl > 0 {
      let cut = io.write_file(walpath, str_cut(text, last_nl + 1));
      cut_ok = cut.is_ok;
    }
  }
  expect("wal cut written", cut_ok);
  var wr2 = wal_load(walpath);
  var eng3 = engine_recover(&wr2, 2, DistanceMetric.Cosine);
  let t1 = search(&eng3, &q42, 1);
  expect("prefix search ok", !t1.is_err);
  if !t1.is_err {
    expect("prefix keeps identity", t1.value.items.len() == 1 && t1.value.items[0].id == 42);
  }
  let tbig = search(&eng3, &q42, 10000);
  expect("prefix tolerant size", !tbig.is_err && tbig.value.items.len() >= 99);

  if g_fails == 0 {
    io.println("[PASS] probe_pkg_xvector");
    return 0;
  }
  io.println("[FAIL] probe_pkg_xvector fails=" + convert.to_string(g_fails));
  return g_fails;
}
