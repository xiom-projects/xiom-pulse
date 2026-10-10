// probe_pkg_orbitdb -- PULSE consumer conformance for the ORBITDB lane.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Source-level composition (see xiom.toml here): consumes
// xiom-orbitdb/src @ local checkout (integration doc pin ef872b0;
// checked out HEAD 54b3209 at build time, WAL format v1).
//
// Scenarios implemented (from xiom-orbitdb/docs/PULSE-INTEGRATION.md §5):
//   1. roundtrip + reopen (N=1k, checkpoint, fresh handle, x2)
//   2. hard-kill recovery + txn classification (writer/uncommitted/
//      verify modes, driven by scripts/interop_orbitdb_crash.{ps1,sh})
//   4. query edges (range, value filter offset/limit, empty results)
//   5. error paths (bad path, order < 3, stale second-handle writes)
//   plus transaction commit/abort classification (in-process form).
//
// Run (sibling tree present): .\scripts\run.ps1 tests\interop\orbitdb\probe_pkg_orbitdb.xi
// Exit code = failure count (0 = green).
module pulse_probe_pkg_orbitdb

use xiom.io;
use xiom.env;
use xiom.time;
use xiom.convert;
use xiom.db.engine;

var g_fails: Int = 0;

fn expect(name: Str, ok: Bool) {
  if ok {
    io.println("[PASS] " + name);
  } else {
    io.println("[FAIL] " + name);
    g_fails = g_fails + 1;
  }
}

// --- hard-kill modes (docs/PULSE-INTEGRATION.md §5.2/3) ----------------------
// Driven by scripts/interop_orbitdb_crash.{ps1,sh}, which start the writer,
// wait for the marker file, hard-kill the tree, then run verify.

fn crash_writer() -> Int {
  let dir = "tests/interop/orbitdb/.tmp";
  if !io.is_dir(dir) {
    let _mk = io.create_dir(dir);
  }
  let wal = dir + "/crash.wal";
  let _r1 = io.remove_file(wal);
  let _r2 = io.remove_file(wal + ".snap");
  let _rm = io.remove_file(dir + "/crash-ready.marker");
  var db = db_file_open(wal, 4);
  var i: Int = 0;
  while i < 999 {
    let _p = db_file_put(&mut db, i, i);
    i = i + 1;
  }
  let _tb = db_file_txn_begin(&mut db);
  let _tp = db_file_txn_put(&mut db, 2000, 9);
  let wm = io.write_file(dir + "/crash-ready.marker", "ready");
  io.println("writer-ready puts=999 txn-uncommitted=2000 marker=" + wm.is_ok.to_str());
  // C-PULSE-18: time.sleep_ms is a NO-OP on v0.64.2, so wait on a monotonic
  // deadline (busy) -- the runner hard-kills us within a second of the
  // marker; the deadline is only the watchdog backstop.
  let t0 = time.monotonic_ms();
  while (time.monotonic_ms() - t0) < 60000 {
    // spin; nothing to do until the kill arrives
  }
  io.println("writer-timeout (no hard kill arrived)");
  return 3;
}

fn crash_verify() -> Int {
  let dir = "tests/interop/orbitdb/.tmp";
  let wal = dir + "/crash.wal";
  var db = db_file_open(wal, 4);
  var prefix_ok: Bool = true;
  var i: Int = 0;
  while i < 999 {
    let v = db_file_get(&db, i);
    if v.is_none || v.value != i { prefix_ok = false; }
    i = i + 1;
  }
  let uncommitted = db_file_get(&db, 2000);
  let p2 = db_file_put(&mut db, 2001, 9);
  let ck = db_file_checkpoint(&mut db);
  var db2 = db_file_open(wal, 4);
  let n1 = db_file_get(&db2, 2001);
  let reopened: Bool = (!n1.is_none) && n1.value == 9;
  io.println("verify: prefix_ok=" + prefix_ok.to_str() + " uncommitted_absent=" + uncommitted.is_none.to_str() + " append=" + p2.to_str() + " reopen=" + reopened.to_str());
  if prefix_ok && uncommitted.is_none && p2 && ck >= 0 && reopened {
    io.println("[PASS] probe_pkg_orbitdb crash verify");
    return 0;
  }
  io.println("[FAIL] probe_pkg_orbitdb crash verify");
  return 1;
}

pub fn main() -> Int {
  let mode = env.var_or("ORBITDB_PROBE_MODE", "full");
  if mode == "writer" { return crash_writer(); }
  if mode == "verify" { return crash_verify(); }
  return main_full();
}

fn main_full() -> Int {
  let dir = "tests/interop/orbitdb/.tmp";
  // io.create_dir REQUIRES the path to not exist (contract); guard it so
  // the probe is rerunnable on the same (shared Windows/Linux) tree.
  if !io.is_dir(dir) {
    let _mk = io.create_dir(dir);
  }
  let wal = dir + "/events.wal";
  let snap = wal + ".snap";
  let _r1 = io.remove_file(wal);
  let _r2 = io.remove_file(snap);

  // --- 5a. error paths: open_checked --------------------------------------
  let e1 = db_file_open_checked("", 4);
  expect("open empty path rejected", e1.is_err);
  let e2 = db_file_open_checked("bad\rpath", 4);
  expect("open CR path rejected", e2.is_err);
  let e3 = db_file_open_checked(wal, 2);
  expect("open order<3 rejected", e3.is_err);

  // --- 1. roundtrip + reopen (x2) -----------------------------------------
  var round: Int = 0;
  while round < 2 {
    var db = db_file_open(wal, 4);
    expect("open ok round" + convert.to_string(round), db_file_size(&db) >= 0);
    var i: Int = 0;
    var puts_ok: Bool = true;
    while i < 1000 {
      if !db_file_put(&mut db, i, i) { puts_ok = false; }
      i = i + 1;
    }
    expect("put 1k round" + convert.to_string(round), puts_ok);
    var gets_ok: Bool = true;
    var j: Int = 0;
    while j < 1000 {
      let v = db_file_get(&db, j);
      if v.is_none || v.value != j { gets_ok = false; }
      j = j + 1;
    }
    expect("get 1k round" + convert.to_string(round), gets_ok);
    let ck = db_file_checkpoint(&mut db);
    expect("checkpoint round" + convert.to_string(round), ck >= 0);
    // fresh handle = reopen path
    var db2 = db_file_open(wal, 4);
    let v2 = db_file_get(&db2, 999);
    expect("reopen value round" + convert.to_string(round), !v2.is_none && v2.value == 999);
    expect("reopen size round" + convert.to_string(round), db_file_size(&db2) == 1000);
    round = round + 1;
  }

  // --- 4. query edges -------------------------------------------------------
  var dbq = db_file_open(wal, 4);
  let rng = db_file_range(&dbq, 100, 199);
  expect("range len", rng.len() == 100);
  expect("range first", rng.len() > 0 && rng[0] == 100);
  expect("range last", rng.len() > 0 && rng[99] == 199);
  let empty_rng = db_file_range(&dbq, 5000, 5999);
  expect("range empty", empty_rng.len() == 0);
  var q = query_new();
  query_where(&mut q, QueryOp.Gte, 100);
  query_offset(&mut q, 10);
  query_limit(&mut q, 5);
  let qr = db_file_query(&dbq, &q);
  expect("query len", qr.len() == 5);
  expect("query first", qr.len() == 5 && qr[0] == 110);
  expect("query last", qr.len() == 5 && qr[4] == 114);
  var qe = query_new();
  query_where(&mut qe, QueryOp.Gte, 5000);
  let qre = db_file_query(&dbq, &qe);
  expect("query empty", qre.len() == 0);

  // --- 3 (in-process). transaction classification ---------------------------
  expect("txn begin", db_file_txn_begin(&mut dbq));
  expect("txn active", db_file_txn_active(&dbq));
  let _tp = db_file_txn_put(&mut dbq, 2000, 9);
  expect("txn abort", db_file_txn_abort(&mut dbq));
  let gone = db_file_get(&dbq, 2000);
  expect("aborted key absent", gone.is_none);
  expect("txn begin 2", db_file_txn_begin(&mut dbq));
  let _tp2 = db_file_txn_put(&mut dbq, 2000, 9);
  expect("txn commit", db_file_txn_commit(&mut dbq));
  let kept = db_file_get(&dbq, 2000);
  expect("committed key present", !kept.is_none && kept.value == 9);

  // --- delete ---------------------------------------------------------------
  expect("delete present", db_file_delete(&mut dbq, 5));
  expect("deleted gone", db_file_get(&dbq, 5).is_none);
  expect("delete absent false", !db_file_delete(&mut dbq, 5));

  // --- 5b. second handle: writes refused after the first writes -------------
  var h2 = db_file_open(wal, 4);
  expect("first handle writes", db_file_put(&mut dbq, 3000, 1));
  expect("second handle write refused", !db_file_put(&mut h2, 3001, 1));

  // --- reopen after the whole block -----------------------------------------
  let _ck2 = db_file_checkpoint(&mut dbq);
  var db3 = db_file_open(wal, 4);
  let v3000 = db_file_get(&db3, 3000);
  expect("reopen keeps new key", !v3000.is_none && v3000.value == 1);
  let v2000 = db_file_get(&db3, 2000);
  expect("reopen keeps txn key", !v2000.is_none && v2000.value == 9);
  expect("reopen deleted stays gone", db_file_get(&db3, 5).is_none);

  if g_fails == 0 {
    io.println("[PASS] probe_pkg_orbitdb");
    return 0;
  }
  io.println("[FAIL] probe_pkg_orbitdb fails=" + convert.to_string(g_fails));
  return g_fails;
}
