// XIOM PULSE -- xiom.sqlite linkage probe (SQL class prerequisite).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the vendored amalgamation is passed to the compiler and the
// driver links/runs before the migrations runner is built on it.
module probe_sqlite

use xiom.io;
use xiom.sqlite.driver;
use xiom.sqlite.types;

pub fn main() -> Int {
  let o = driver.SqlDriver.open_from_dsn(":memory:");
  if !o.is_ok {
    io.println("probe_sqlite: open failed");
    return 1;
  }
  let drv = o.value;
  let c = driver.SqlDriver.execute(&drv, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT);");
  let i = driver.SqlDriver.execute(&drv, "INSERT INTO t(id, name) VALUES (1, 'pulse');");
  let q = driver.SqlDriver.query_one(&drv, "SELECT name FROM t WHERE id = 1;");
  var ok: Bool = false;
  if c.is_ok && i.is_ok && q.is_ok && q.value.has_row {
    let v = q.value.row.get(0);
    if v.is_some {
      let s = types.SqliteValue.as_text(&v.value);
      if s.is_some && s.value == "pulse" { ok = true; }
    }
  }
  let _ = driver.SqlDriver.close(&drv);
  if ok {
    io.println("probe_sqlite: GREEN");
    return 0;
  }
  io.println("probe_sqlite: FAILED");
  return 1;
}
