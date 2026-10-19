// XIOM PULSE -- SQL migrations runner tests (status/up/lock/order).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module test_migrations

use xiom.io;
use xiom.sqlite.driver;
use xiom.sqlite.types;
use xiom.pulse.station.migrations;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn note_count(dsn: Str) -> Int {
  let o = driver.SqlDriver.open_from_dsn(dsn);
  if !o.is_ok { return -1; }
  let drv = o.value;
  var n: Int = -1;
  let q = driver.SqlDriver.query_one(&drv, "SELECT COUNT(*) FROM notes;");
  if q.is_ok && q.value.has_row {
    let v = types.SqliteRow.get(&q.value.row, 0);
    if v.is_some {
      let c = types.SqliteValue.as_int(&v.value);
      if c.is_some { n = c.value; }
    }
  }
  let _ = driver.SqlDriver.close(&drv);
  return n;
}

pub fn main() -> Int {
  let dir = "probe-logs/mig-test";
  let dsn = dir + "/pulse.db";
  let _ = io.create_dir_all(dir);
  let _ = io.remove_file(dsn);
  let _ = io.write_file(dir + "/20260101000001_create.sql", "CREATE TABLE notes(id INTEGER PRIMARY KEY, body TEXT);");
  let _ = io.write_file(dir + "/20260101000002_seed.sql", "INSERT INTO notes(id, body) VALUES (1, 'hello');");

  var f: Int = 0;
  f = f + check("pending status exits 1", migrations.cli_status(dsn, dir) == 1);
  f = f + check("up applies batch", migrations.cli_up(dsn, dir, 900, false) == 0);
  f = f + check("current status exits 0", migrations.cli_status(dsn, dir) == 0);
  f = f + check("re-up is a no-op", migrations.cli_up(dsn, dir, 900, false) == 0);
  f = f + check("rows applied once", note_count(dsn) == 1);

  // Stale lock: mark a dead owner far in the past, add a third file, and
  // prove up breaks the stale lock and applies.
  let _ = io.write_file(dir + "/20260101000003_more.sql", "INSERT INTO notes(id, body) VALUES (2, 'more');");
  let o = driver.SqlDriver.open_from_dsn(dsn);
  if o.is_ok {
    let drv = o.value;
    let _ = driver.SqlDriver.execute(&drv, "UPDATE _pulse_migrations_lock SET owner='dead', locked_at=1, heartbeat_at=1 WHERE id=1;");
    let _ = driver.SqlDriver.close(&drv);
  }
  f = f + check("stale lock auto-broken", migrations.cli_up(dsn, dir, 900, false) == 0);
  f = f + check("third migration applied", note_count(dsn) == 2);

  if f == 0 {
    io.println("pulse-migrations: GREEN");
  } else {
    io.println("pulse-migrations: FAILED=" + f.to_str());
  }
  return f;
}
