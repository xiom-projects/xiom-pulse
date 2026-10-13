// XIOM PULSE -- consumer co-verification probe for xiom.sqlite 0.4.0
// (PULSE SQL driver, eco-v0.1.174; contract docs/requirements/pulse-sql-driver.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run from the repo root (absolute --c-source path required):
//   xiom --run docs/repro/sql-coverify/coverify.xi
//     --c-source "<XIOM_HOME>/packages/xiom-sqlite-0.4.0/xiom-sqlite/vendor/sqlite3.c"
// Exit code = failures (0 = green).
module sql_coverify;

use xiom.io;
use xiom.string;
use xiom.sqlite;
use xiom.sqlite.driver;
use xiom.sqlite.rows;
use xiom.sqlite.types;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn main() -> Int {
  var f: Int = 0;
  let _rm = io.remove_file("coverify.db");

  // DSN: valid grammar + fail-closed unknown option.
  let dsn_r = driver.SqlDsn.parse("coverify.db?busy_timeout=1500&journal_mode=wal");
  f = f + check("dsn valid parses", dsn_r.is_ok);
  let dsn_bad = driver.SqlDsn.parse("coverify.db?bogus=1");
  f = f + check("dsn unknown option fail-closed", dsn_bad.is_err);

  let drv_r = driver.SqlDriver.open_from_dsn("coverify.db?busy_timeout=1500&journal_mode=wal");
  f = f + check("open from dsn", drv_r.is_ok);
  if drv_r.is_err {
    io.println("open error: " + drv_r.error.message);
    return f + 1;
  }
  let drv = drv_r.value;
  f = f + check("journal mode readback wal", driver.SqlDriver.journal_mode(&drv) == "wal");
  f = f + check("busy timeout readback 1500", driver.SqlDriver.busy_timeout_ms(&drv) == 1500);
  f = f + check("transactional ddl true", driver.SqlDriver.transactional_ddl(&drv));

  let dd = driver.SqlDriver.execute(&drv, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL);");
  f = f + check("ddl execute", dd.is_ok);
  let ins = driver.SqlDriver.execute(&drv, "INSERT INTO t (name, score) VALUES ('a', 1.5); INSERT INTO t (name, score) VALUES ('b', 2.5);");
  f = f + check("multi-statement execute ok", ins.is_ok);
  if ins.is_ok {
    f = f + check("rows_affected 1 (sqlite3_changes = last statement)", ins.value.rows_affected == 1);
    f = f + check("last_insert_rowid 2", ins.value.last_insert_rowid == 2);
  }

  let q = driver.SqlDriver.query(&drv, "SELECT id, name, score FROM t ORDER BY id;");
  f = f + check("query ok", q.is_ok);
  if q.is_ok {
    let res = q.value;
    f = f + check("row count 2", res.rows.len() == 2);
    f = f + check("column count 3", res.column_names.len() == 3);
    let ci = rows.SqliteResult.column_index(&res, "name");
    f = f + check("column_index name == 1", ci.is_some && ci.value == 1);
    let vn = rows.SqliteResult.value_by_name(&res, 1, "name");
    var byname_ok: Bool = false;
    if vn.is_some {
      let tv = types.SqliteValue.as_text(&vn.value);
      byname_ok = tv.is_some && tv.value == "b";
    }
    f = f + check("by-name text row1 == b", byname_ok);
    let vi = types.SqliteValue.as_int(&res.rows[0].columns[0]);
    f = f + check("by-index id row0 == 1", vi.is_some && vi.value == 1);
    let vr = types.SqliteValue.as_real(&res.rows[1].columns[2]);
    f = f + check("by-index real row1 == 2.5", vr.is_some && vr.value == 2.5);
  }

  let qo_e = driver.SqlDriver.query_one(&drv, "SELECT id FROM t WHERE id = 999;");
  f = f + check("query_one empty has_row false", qo_e.is_ok && !qo_e.value.has_row);
  let qo = driver.SqlDriver.query_one(&drv, "SELECT name FROM t WHERE id = 1;");
  var qo_ok: Bool = false;
  if qo.is_ok && qo.value.has_row {
    let tv = types.SqliteValue.as_text(&qo.value.row.columns[0]);
    qo_ok = tv.is_some && tv.value == "a";
  }
  f = f + check("query_one hit reads a", qo_ok);

  // Transactions: rollback drops, commit keeps; in_transaction tracks.
  f = f + check("autocommit before", !driver.SqlDriver.in_transaction(&drv));
  let tb1 = driver.SqlDriver.transaction_begin(&drv);
  f = f + check("begin ok + in txn", tb1.is_ok && driver.SqlDriver.in_transaction(&drv));
  let _i2 = driver.SqlDriver.execute(&drv, "INSERT INTO t (name, score) VALUES ('c', 3.5);");
  let tr = driver.SqlDriver.transaction_rollback(&drv);
  f = f + check("rollback ok + out of txn", tr.is_ok && !driver.SqlDriver.in_transaction(&drv));
  let qc1 = driver.SqlDriver.query(&drv, "SELECT COUNT(*) AS n FROM t;");
  var rollback_ok: Bool = false;
  if qc1.is_ok {
    let vn2 = rows.SqliteResult.value_by_name(&qc1.value, 0, "n");
    if vn2.is_some {
      let ni = types.SqliteValue.as_int(&vn2.value);
      rollback_ok = ni.is_some && ni.value == 2;
    }
  }
  f = f + check("rollback dropped the row (count 2)", rollback_ok);
  let tb2 = driver.SqlDriver.transaction_begin(&drv);
  let _i3 = driver.SqlDriver.execute(&drv, "INSERT INTO t (name, score) VALUES ('c', 3.5);");
  let tc = driver.SqlDriver.transaction_commit(&drv);
  f = f + check("commit ok", tc.is_ok);
  let qc2 = driver.SqlDriver.query(&drv, "SELECT COUNT(*) AS n FROM t;");
  var commit_ok: Bool = false;
  if qc2.is_ok {
    let vn3 = rows.SqliteResult.value_by_name(&qc2.value, 0, "n");
    if vn3.is_some {
      let ni2 = types.SqliteValue.as_int(&vn3.value);
      commit_ok = ni2.is_some && ni2.value == 3;
    }
  }
  f = f + check("commit kept the row (count 3)", commit_ok);

  // Error path: failing statement -> Err + last_error pair.
  let bad = driver.SqlDriver.execute(&drv, "INSERT INTO nope (x) VALUES (1);");
  f = f + check("bad sql yields Err", bad.is_err);
  let le = driver.SqlDriver.last_error(&drv);
  f = f + check("last_error code nonzero", le.code != 0);
  f = f + check("last_error message present", le.message.len() > 0);

  let cl = driver.SqlDriver.close(&drv);
  f = f + check("close ok", cl.is_ok);

  if f == 0 {
    io.println("sql-coverify: GREEN");
  } else {
    io.println("sql-coverify: RED failures=" + f.to_str());
  }
  return f;
}
