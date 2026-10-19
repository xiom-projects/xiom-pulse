// XIOM PULSE -- SQL migrations runner (knex discipline, PULSE corrections).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// MVP slice: `migrate status` and `migrate up` over xiom.sqlite 0.4.1.
// Tracking/lock tables, lexicographic discovery, one batch per up, stale
// lock takeover, per-migration transaction unless the file declares
// `-- pulse: no-transaction`. `down`/`create` and the backup fence are the
// next slice (docs/DESIGN-SQL-MIGRATIONS.md).
//
// Cross-module returns are Int/Str/Bool only: v0.64.7 imported-struct
// field access is broken (REL-20261019-1309).
module xiom.pulse.station.migrations

use xiom.io;
use xiom.string;
use xiom.sqlite.driver;
use xiom.sqlite.types;
use xiom.convert.time as ctime;
use xiom.pulse.station.config;

const TABLE_MIGRATIONS: Str = "CREATE TABLE IF NOT EXISTS _pulse_migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, batch INTEGER NOT NULL, applied_at TEXT NOT NULL);";
const TABLE_LOCK: Str = "CREATE TABLE IF NOT EXISTS _pulse_migrations_lock (id INTEGER PRIMARY KEY CHECK (id = 1), owner TEXT NOT NULL DEFAULT '', locked_at INTEGER NOT NULL DEFAULT 0, heartbeat_at INTEGER NOT NULL DEFAULT 0);";
const SEED_LOCK: Str = "INSERT INTO _pulse_migrations_lock(id, owner, locked_at, heartbeat_at) VALUES (1, '', 0, 0) ON CONFLICT(id) DO NOTHING;";

fn quote_sql(s: Str) -> Str {
  return "'" + string.str_replace_all(s, "'", "''") + "'";
}

fn exec_ok(drv: &driver.SqlDriver, sql: Str) -> Bool {
  let r = driver.SqlDriver.execute(drv, sql);
  return r.is_ok;
}

fn ensure_tables(drv: &driver.SqlDriver) -> Bool {
  if !exec_ok(drv, TABLE_MIGRATIONS) { return false; }
  if !exec_ok(drv, TABLE_LOCK) { return false; }
  return exec_ok(drv, SEED_LOCK);
}

fn is_applied(rows: &Vec[(Str, Int)], name: Str) -> Bool {
  var i: Int = 0;
  while i < rows.len() {
    if rows[i].0 == name { return true; }
    i = i + 1;
  }
  return false;
}

fn applied_rows(drv: &driver.SqlDriver) -> Vec[(Str, Int)] {
  var out: Vec[(Str, Int)] = Vec[(Str, Int)].new();
  let q = driver.SqlDriver.query(drv, "SELECT name, batch FROM _pulse_migrations ORDER BY id ASC;");
  if !q.is_ok { return out; }
  let res = q.value;
  var i: Int = 0;
  let n = types.SqliteResult.row_count(&res);
  while i < n {
    let rowopt = types.SqliteResult.get_row(&res, i);
    if rowopt.is_some {
      let row = rowopt.value;
      let nm = types.SqliteRow.get(&row, 0);
      let bt = types.SqliteRow.get(&row, 1);
      if nm.is_some && bt.is_some {
        let s = types.SqliteValue.as_text(&nm.value);
        let b = types.SqliteValue.as_int(&bt.value);
        if s.is_some && b.is_some {
          out.push((s.value, b.value));
        }
      }
    }
    i = i + 1;
  }
  return out;
}

/// discover returns `*.sql` entry names sorted lexicographically (the
/// migration chronology contract). Complexity: O(n^2) insertion sort.
fn discover(dir: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  if !io.is_dir(dir) { return out; }
  let r = io.list_dir(dir);
  if !r.is_ok { return out; }
  let entries = r.value;
  var names: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < entries.len() {
    if string.str_ends_with(entries[i], ".sql") { names.push(entries[i]); }
    i = i + 1;
  }
  // Selection sort into a fresh Vec (no in-place index assignment).
  while names.len() > 0 {
    var best: Int = 0;
    i = 1;
    while i < names.len() {
      if string.str_compare(names[i], names[best]) < 0 { best = i; }
      i = i + 1;
    }
    out.push(names[best]);
    var rest: Vec[Str] = Vec[Str].new();
    i = 0;
    while i < names.len() {
      if i != best { rest.push(names[i]); }
      i = i + 1;
    }
    names = rest;
  }
  return out;
}

pub type LockState = { owner: Str; heartbeat: Int; }
pub type LockOutcome = { ok: Bool; stale: Bool; reason: Str; }

fn lock_state(drv: &driver.SqlDriver) -> LockState {
  let q = driver.SqlDriver.query_one(drv, "SELECT owner, heartbeat_at FROM _pulse_migrations_lock WHERE id = 1;");
  if q.is_ok && q.value.has_row {
    let row = q.value.row;
    let ow = types.SqliteRow.get(&row, 0);
    let hb = types.SqliteRow.get(&row, 1);
    if ow.is_some && hb.is_some {
      let s = types.SqliteValue.as_text(&ow.value);
      let h = types.SqliteValue.as_int(&hb.value);
      if s.is_some && h.is_some { return LockState{ owner: s.value; heartbeat: h.value }; }
    }
  }
  return LockState{ owner: ""; heartbeat: 0 };
}

/// lock_acquire takes the single-row lock. A live lock fails unless
/// `force`; a stale one (heartbeat older than stale_secs) is broken with a
/// notice. Returns (ok, stale_broken, reason).
fn lock_acquire(drv: &driver.SqlDriver, owner: Str, stale_secs: Int, force: Bool) -> LockOutcome {
  let state = lock_state(drv);
  let now = ctime.time_now();
  if state.owner.len() == 0 || state.heartbeat <= 0 {
    let r = driver.SqlDriver.execute(drv, "UPDATE _pulse_migrations_lock SET owner = " + quote_sql(owner) + ", locked_at = " + now.to_str() + ", heartbeat_at = " + now.to_str() + " WHERE id = 1 AND (owner = '' OR heartbeat_at = 0);");
    if r.is_ok && r.value.rows_affected == 1 { return LockOutcome{ ok: true; stale: false; reason: "" }; }
    return LockOutcome{ ok: false; stale: false; reason: "lock acquisition raced; retry" };
  }
  let age = now - state.heartbeat;
  let stale = age > stale_secs;
  if stale {
    let r = driver.SqlDriver.execute(drv, "UPDATE _pulse_migrations_lock SET owner = " + quote_sql(owner) + ", locked_at = " + now.to_str() + ", heartbeat_at = " + now.to_str() + " WHERE id = 1 AND heartbeat_at = " + state.heartbeat.to_str() + ";");
    if r.is_ok && r.value.rows_affected == 1 { return LockOutcome{ ok: true; stale: true; reason: "" }; }
    return LockOutcome{ ok: false; stale: false; reason: "stale lock raced; retry" };
  }
  if force {
    let r = driver.SqlDriver.execute(drv, "UPDATE _pulse_migrations_lock SET owner = " + quote_sql(owner) + ", locked_at = " + now.to_str() + ", heartbeat_at = " + now.to_str() + " WHERE id = 1;");
    if r.is_ok { return LockOutcome{ ok: true; stale: false; reason: "" }; }
    return LockOutcome{ ok: false; stale: false; reason: "forced lock update failed" };
  }
  return LockOutcome{ ok: false; stale: false; reason: "locked by " + state.owner + " (heartbeat age " + age.to_str() + "s)" };
}

fn lock_release(drv: &driver.SqlDriver, owner: Str) -> Bool {
  let r = driver.SqlDriver.execute(drv, "UPDATE _pulse_migrations_lock SET owner = '', locked_at = 0, heartbeat_at = 0 WHERE id = 1 AND owner = " + quote_sql(owner) + ";");
  return r.is_ok;
}

/// status_text renders applied/pending/current + lock state (the CLI
/// contract). Returns "" when the directory is unreadable.
pub fn status_text(drv: &driver.SqlDriver, dir: Str) -> Str {
  if !ensure_tables(drv) { return "migrations: cannot create tracking tables"; }
  let rows = applied_rows(drv);
  let files = discover(dir);
  var pending: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < files.len() {
    if !is_applied(&rows, files[i]) { pending.push(files[i]); }
    i = i + 1;
  }
  var current: Str = "";
  var maxb: Int = 0;
  var ri: Int = 0;
  while ri < rows.len() {
    current = rows[ri].0;
    if rows[ri].1 > maxb { maxb = rows[ri].1; }
    ri = ri + 1;
  }
  var cur: Str = current;
  if cur.len() == 0 { cur = "-"; }
  var out: Str = "migrations: applied=" + rows.len().to_str() + " pending=" + pending.len().to_str() + " current=" + cur + " batch=" + maxb.to_str();
  let st = lock_state(drv);
  if st.owner.len() > 0 && st.heartbeat > 0 {
    out = out + " lock=" + st.owner + "@" + st.heartbeat.to_str();
  } else {
    out = out + " lock=free";
  }
  i = 0;
  while i < rows.len() {
    out = out + "\n  applied batch=" + rows[i].1.to_str() + " " + rows[i].0;
    i = i + 1;
  }
  i = 0;
  while i < pending.len() {
    out = out + "\n  pending " + pending[i];
    i = i + 1;
  }
  return out;
}

/// up applies every pending file as one new batch. Returns
/// (ok, message); message is the applied list or the error/marker text.
pub fn up(drv: &driver.SqlDriver, dir: Str, owner: Str, stale_secs: Int, force: Bool) -> Str {
  if !ensure_tables(drv) { return "ERR: cannot create tracking tables"; }
  let lk = lock_acquire(drv, owner, stale_secs, force);
  if !lk.ok { return "ERR: " + lk.reason; }
  var note: Str = "";
  if lk.stale { note = "stale lock broken; "; }
  let rows = applied_rows(drv);
  let files = discover(dir);
  var pending: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < files.len() {
    if !is_applied(&rows, files[i]) { pending.push(files[i]); }
    i = i + 1;
  }
  if pending.len() == 0 {
    let _ = lock_release(drv, owner);
    return "OK: " + note + "nothing pending";
  }
  var maxb: Int = 0;
  var ri: Int = 0;
  while ri < rows.len() {
    if rows[ri].1 > maxb { maxb = rows[ri].1; }
    ri = ri + 1;
  }
  let batch = maxb + 1;
  var applied: Str = "";
  i = 0;
  while i < pending.len() {
    let name = pending[i];
    let path = dir + "/" + name;
    let f = io.read_file(path);
    if !f.is_ok {
      let _ = lock_release(drv, owner);
      return "ERR: " + note + "cannot read " + name;
    }
    let sql = f.value;
    let no_tx = string.str_contains(sql, "-- pulse: no-transaction");
    var ok: Bool = false;
    if no_tx {
      ok = exec_ok(drv, sql);
      if ok {
        ok = exec_ok(drv, "INSERT INTO _pulse_migrations(name, batch, applied_at) VALUES (" + quote_sql(name) + ", " + batch.to_str() + ", " + quote_sql(ctime.time_now().to_str()) + ");");
      }
    } else {
      let b = driver.SqlDriver.transaction_begin(drv);
      if b.is_ok {
        ok = exec_ok(drv, sql);
        if ok {
          ok = exec_ok(drv, "INSERT INTO _pulse_migrations(name, batch, applied_at) VALUES (" + quote_sql(name) + ", " + batch.to_str() + ", " + quote_sql(ctime.time_now().to_str()) + ");");
        }
        if ok {
          let cm = driver.SqlDriver.transaction_commit(drv);
          ok = cm.is_ok;
        } else {
          let _ = driver.SqlDriver.transaction_rollback(drv);
        }
      }
    }
    if !ok {
      let _ = lock_release(drv, owner);
      return "ERR: " + note + "migration failed: " + name + " (batch " + batch.to_str() + ")";
    }
    if applied.len() > 0 { applied = applied + ","; }
    applied = applied + name;
    i = i + 1;
  }
  let _ = lock_release(drv, owner);
  return "OK: " + note + "applied batch=" + batch.to_str() + " " + applied;
}

fn cli_owner() -> Str {
  return "pulse:" + ctime.time_now().to_str();
}

/// cli_status is the `migrate status` entry: prints the report, returns 0
/// when current and 1 when pending/error (CI-gate friendly).
pub fn cli_status(dsn: Str, dir: Str) -> Int {
  if dsn.len() == 0 {
    io.println("migrations: PULSE_SQL_DSN is not set");
    return 1;
  }
  let o = driver.SqlDriver.open_from_dsn(dsn);
  if !o.is_ok {
    io.println("migrations: cannot open " + dsn);
    return 1;
  }
  let drv = o.value;
  let text = status_text(&drv, dir);
  io.println(text);
  let _ = driver.SqlDriver.close(&drv);
  if string.str_contains(text, " pending=") && !string.str_contains(text, "pending=0 ") {
    return 1;
  }
  return 0;
}

/// cli_up is the `migrate up` entry: prints the outcome, returns 0/1.
pub fn cli_up(dsn: Str, dir: Str, stale_secs: Int, force: Bool) -> Int {
  if dsn.len() == 0 {
    io.println("migrations: PULSE_SQL_DSN is not set");
    return 1;
  }
  let o = driver.SqlDriver.open_from_dsn(dsn);
  if !o.is_ok {
    io.println("migrations: cannot open " + dsn);
    return 1;
  }
  let drv = o.value;
  let r = up(&drv, dir, cli_owner(), stale_secs, force);
  io.println("migrations: " + r);
  let _ = driver.SqlDriver.close(&drv);
  if string.str_starts_with(r, "OK:") { return 0; }
  return 1;
}

/// cli dispatches `migrate status|up`; unknown subcommands print usage.
pub fn cli(sub: Str, force: Bool) -> Int {
  let dsn = config.cfg_sql_dsn();
  let dir = config.cfg_migrations_dir();
  if sub == "status" { return cli_status(dsn, dir); }
  if sub == "up" { return cli_up(dsn, dir, config.cfg_migration_stale_secs(), force); }
  io.println("usage: pulse_app migrate status|up [--force]");
  return 1;
}
