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
use xiom.io.fs;
use xiom.string;
use xiom.sqlite.driver;
use xiom.sqlite.types;
use xiom.convert;
use xiom.convert.parse;
use xiom.convert.time as ctime;
use xiom.pulse.station.config;

const TABLE_MIGRATIONS: Str = "CREATE TABLE IF NOT EXISTS _pulse_migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, batch INTEGER NOT NULL, applied_at TEXT NOT NULL);";
const TABLE_LOCK: Str = "CREATE TABLE IF NOT EXISTS _pulse_migrations_lock (id INTEGER PRIMARY KEY CHECK (id = 1), owner TEXT NOT NULL DEFAULT '', locked_at INTEGER NOT NULL DEFAULT 0, heartbeat_at INTEGER NOT NULL DEFAULT 0);";
const SEED_LOCK: Str = "INSERT INTO _pulse_migrations_lock(id, owner, locked_at, heartbeat_at) VALUES (1, '', 0, 0) ON CONFLICT(id) DO NOTHING;";

const MARK_UP: Str = "-- pulse:up";
const MARK_DOWN: Str = "-- pulse:down";

fn quote_sql(s: Str) -> Str {
  return "'" + string.str_replace_all(s, "'", "''") + "'";
}

/// section extracts the `-- pulse:up` / `-- pulse:down` body. Files with
/// neither marker are whole-file forward migrations with no rollback;
/// files with only one marker are malformed (""). Complexity: O(n).
fn section(sql: Str, which: Str) -> Str {
  let up_m = string.str_index_of(sql, MARK_UP);
  let down_m = string.str_index_of(sql, MARK_DOWN);
  if up_m.is_none && down_m.is_none {
    if which == "up" { return sql; }
    return "";
  }
  if up_m.is_none || down_m.is_none { return ""; }
  if down_m.value <= up_m.value { return ""; }
  if which == "up" {
    return string.str_slice(sql, up_m.value + MARK_UP.len(), down_m.value);
  }
  return string.str_slice(sql, down_m.value + MARK_DOWN.len(), sql.len());
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

fn has_name(files: &Vec[Str], name: Str) -> Bool {
  var i: Int = 0;
  while i < files.len() {
    if files[i] == name { return true; }
    i = i + 1;
  }
  return false;
}

fn missing_applied(rows: &Vec[(Str, Int)], files: &Vec[Str]) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < rows.len() {
    if !has_name(files, rows[i].0) { out.push(rows[i].0); }
    i = i + 1;
  }
  return out;
}

fn joined(names: &Vec[Str]) -> Str {
  var out: Str = "";
  var i: Int = 0;
  while i < names.len() {
    if out.len() > 0 { out = out + ","; }
    out = out + names[i];
    i = i + 1;
  }
  return out;
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
  let now = ctime.timestamp_now();
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
  let missing = missing_applied(&rows, &files);
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
  var out: Str = "migrations: applied=" + rows.len().to_str() + " pending=" + pending.len().to_str() + " missing=" + missing.len().to_str() + " current=" + cur + " batch=" + maxb.to_str();
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
  i = 0;
  while i < missing.len() {
    out = out + "\n  missing " + missing[i];
    i = i + 1;
  }
  return out;
}

/// up applies every pending file as one new batch. Returns
/// (ok, message); message is the applied list or the error/marker text.
pub fn up(drv: &driver.SqlDriver, dir: Str, owner: Str, stale_secs: Int, force: Bool, allow_missing: Bool, backup_manifest: Str, no_backup_check: Bool) -> Str {
  if !ensure_tables(drv) { return "ERR: cannot create tracking tables"; }
  let rows0 = applied_rows(drv);
  let files0 = discover(dir);
  let missing0 = missing_applied(&rows0, &files0);
  if missing0.len() > 0 && !allow_missing {
    return "ERR: applied migration file(s) missing: " + joined(&missing0) + " (rerun with --allow-missing-applied)";
  }
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
  if allow_missing && missing0.len() > 0 {
    note = note + "skipped missing applied: " + joined(&missing0) + "; ";
  }
  if pending.len() > 0 && !no_backup_check {
    if !backup_ok(driver.SqlDriver.dsn(drv), backup_manifest) {
      let _ = lock_release(drv, owner);
      return "ERR: no covering SQL backup for pending migrations (run pulse_migrate backup; set PULSE_SQL_BACKUP_MANIFEST or --no-backup-check)";
    }
    note = note + "backup fence ok; ";
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
    let sql = section(f.value, "up");
    if sql.len() == 0 {
      let _ = lock_release(drv, owner);
      return "ERR: malformed or empty up section in " + name;
    }
    let no_tx = string.str_contains(sql, "-- pulse: no-transaction");
    var ok: Bool = false;
    if no_tx {
      ok = exec_ok(drv, sql);
      if ok {
        ok = exec_ok(drv, "INSERT INTO _pulse_migrations(name, batch, applied_at) VALUES (" + quote_sql(name) + ", " + batch.to_str() + ", " + quote_sql(ctime.timestamp_now().to_str()) + ");");
      }
    } else {
      let b = driver.SqlDriver.transaction_begin(drv);
      if b.is_ok {
        ok = exec_ok(drv, sql);
        if ok {
          ok = exec_ok(drv, "INSERT INTO _pulse_migrations(name, batch, applied_at) VALUES (" + quote_sql(name) + ", " + batch.to_str() + ", " + quote_sql(ctime.timestamp_now().to_str()) + ");");
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
    let _ = exec_ok(drv, "UPDATE _pulse_migrations_lock SET heartbeat_at = " + ctime.timestamp_now().to_str() + " WHERE id = 1 AND owner = " + quote_sql(owner) + ";");
    i = i + 1;
  }
  let _ = lock_release(drv, owner);
  return "OK: " + note + "applied batch=" + batch.to_str() + " " + applied;
}

/// down rolls back the latest batch in reverse applied order. Each file
/// must carry a `-- pulse:down` section. Returns "OK:"/"ERR:".
pub fn down(drv: &driver.SqlDriver, dir: Str, owner: Str, stale_secs: Int, force: Bool) -> Str {
  if !ensure_tables(drv) { return "ERR: cannot create tracking tables"; }
  let lk = lock_acquire(drv, owner, stale_secs, force);
  if !lk.ok { return "ERR: " + lk.reason; }
  var note: Str = "";
  if lk.stale { note = "stale lock broken; "; }
  let rows = applied_rows(drv);
  var maxb: Int = 0;
  var i: Int = 0;
  while i < rows.len() {
    if rows[i].1 > maxb { maxb = rows[i].1; }
    i = i + 1;
  }
  if maxb == 0 {
    let _ = lock_release(drv, owner);
    return "OK: " + note + "no batches to roll back";
  }
  var names: Vec[Str] = Vec[Str].new();
  i = 0;
  while i < rows.len() {
    if rows[i].1 == maxb { names.push(rows[i].0); }
    i = i + 1;
  }
  var back: Vec[Str] = Vec[Str].new();
  var j: Int = names.len() - 1;
  while j >= 0 {
    back.push(names[j]);
    j = j - 1;
  }
  var done: Str = "";
  i = 0;
  while i < back.len() {
    let name = back[i];
    let f = io.read_file(dir + "/" + name);
    if !f.is_ok {
      let _ = lock_release(drv, owner);
      return "ERR: " + note + "cannot read " + name;
    }
    let sql = section(f.value, "down");
    if sql.len() == 0 {
      let _ = lock_release(drv, owner);
      return "ERR: " + note + "no down section in " + name;
    }
    var ok: Bool = false;
    let b = driver.SqlDriver.transaction_begin(drv);
    if b.is_ok {
      ok = exec_ok(drv, sql);
      if ok {
        ok = exec_ok(drv, "DELETE FROM _pulse_migrations WHERE name = " + quote_sql(name) + " AND batch = " + maxb.to_str() + ";");
      }
      if ok {
        let cm = driver.SqlDriver.transaction_commit(drv);
        ok = cm.is_ok;
      } else {
        let _ = driver.SqlDriver.transaction_rollback(drv);
      }
    }
    if !ok {
      let _ = lock_release(drv, owner);
      return "ERR: " + note + "rollback failed: " + name;
    }
    if done.len() > 0 { done = done + ","; }
    done = done + name;
    i = i + 1;
  }
  let _ = lock_release(drv, owner);
  return "OK: " + note + "rolled back batch=" + maxb.to_str() + " " + done;
}

/// create renders a UTC-stamped stub with both direction markers.
/// Returns "OK: <path>" or "ERR: ...".
pub fn create(dir: Str, name: Str) -> Str {
  let clean = string.str_replace_all(name, " ", "_");
  if clean.len() == 0 || string.str_contains(clean, "/") || string.str_contains(clean, "..") {
    return "ERR: invalid migration name";
  }
  if !io.is_dir(dir) {
    let d = io.create_dir_all(dir);
    if !d.is_ok { return "ERR: cannot create " + dir; }
  }
  let ts = ctime.timestamp_now();
  let date = ctime.timestamp_to_date(ts);
  let sod = ts - (ts / 86400) * 86400;
  let hh = string.str_pad_left((sod / 3600).to_str(), 2, '0');
  let mi = string.str_pad_left(((sod % 3600) / 60).to_str(), 2, '0');
  let ss = string.str_pad_left((sod % 60).to_str(), 2, '0');
  let stamp = date.year.to_str() + string.str_pad_left(date.month.to_str(), 2, '0') + string.str_pad_left(date.day.to_str(), 2, '0') + hh + mi + ss;
  let path = dir + "/" + stamp + "_" + clean + ".sql";
  var body: Str = "-- " + clean + "\n" + MARK_UP + "\n-- forward migration\n\n" + MARK_DOWN + "\n-- rollback\n";
  let w = io.write_file(path, body);
  if !w.is_ok { return "ERR: cannot write " + path; }
  return "OK: created " + path;
}

fn dsn_path(dsn: Str) -> Str {
  var p = dsn;
  let q = string.str_index_of(p, "?");
  if q.is_some { p = string.str_slice(p, 0, q.value); }
  if string.str_starts_with(p, "sqlite://") { return string.str_slice(p, 9, p.len()); }
  if string.str_starts_with(p, "sqlite3://") { return string.str_slice(p, 10, p.len()); }
  if string.str_starts_with(p, "sqlite:") { return string.str_slice(p, 7, p.len()); }
  if string.str_starts_with(p, "sqlite3:") { return string.str_slice(p, 8, p.len()); }
  return p;
}

fn manifest_value(text: Str, key: Str) -> Str {
  let lines = string.str_split(text, "\n");
  var i: Int = 0;
  while i < lines.len() {
    let prefix = key + "=";
    if string.str_starts_with(lines[i], prefix) {
      return string.str_slice(lines[i], prefix.len(), lines[i].len());
    }
    i = i + 1;
  }
  return "";
}

/// backup writes a consistent SQLite snapshot (VACUUM INTO) plus a
/// manifest that the migration fence can check. Returns "OK:"/"ERR:".
pub fn backup(dsn: Str, out_path: Str) -> Str {
  if dsn.len() == 0 { return "ERR: PULSE_SQL_DSN is not set"; }
  let o = driver.SqlDriver.open_from_dsn(dsn);
  if !o.is_ok { return "ERR: cannot open " + dsn; }
  let drv = o.value;
  let path = dsn_path(dsn);
  if !io.file_exists(path) {
    let _ = driver.SqlDriver.close(&drv);
    return "ERR: database file not found: " + path;
  }
  let mt = fs.fs_mtime(path);
  if !mt.is_ok {
    let _ = driver.SqlDriver.close(&drv);
    return "ERR: cannot stat " + path;
  }
  let out = out_path;
  if out.len() == 0 { out = path + "." + ctime.timestamp_now().to_str() + ".bak"; }
  let v = exec_ok(&drv, "VACUUM INTO " + quote_sql(out) + ";");
  let _ = driver.SqlDriver.close(&drv);
  if !v { return "ERR: backup failed: " + out; }
  var size: Int = 0;
  let sz = io.file_size(out);
  if sz.is_some { size = sz.value; }
  var manifest: Str = "db=" + path + "\nbackup=" + out + "\ncreated_at=" + ctime.timestamp_now().to_str() + "\nsize=" + size.to_str() + "\n";
  let w = io.write_file(out + ".manifest", manifest);
  if !w.is_ok { return "ERR: backup written but manifest failed: " + out; }
  return "OK: " + out + " manifest=" + out + ".manifest";
}

/// backup_ok is the fence predicate: the manifest names this DB and was
/// created at/after the DB's last write. Complexity: O(1).
pub fn backup_ok(dsn: Str, manifest_path: Str) -> Bool {
  if manifest_path.len() == 0 { return false; }
  let r = io.read_file(manifest_path);
  if !r.is_ok { return false; }
  let db = manifest_value(r.value, "db");
  if db != dsn_path(dsn) { return false; }
  let created = manifest_value(r.value, "created_at");
  if created.len() == 0 { return false; }
  if !io.file_exists(dsn_path(dsn)) { return false; }
  let mt = fs.fs_mtime(dsn_path(dsn));
  if !mt.is_ok { return false; }
  return convert_str_int(created) >= mt.value;
}

fn convert_str_int(s: Str) -> Int {
  let p = parse.parse_int(s);
  if p.is_ok { return p.value; }
  return 0;
}

fn cli_owner() -> Str {
  return "pulse:" + ctime.timestamp_now().to_str();
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
pub fn cli_up(dsn: Str, dir: Str, stale_secs: Int, force: Bool, allow_missing: Bool, no_backup_check: Bool) -> Int {
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
  let r = up(&drv, dir, cli_owner(), stale_secs, force, allow_missing, config.cfg_sql_backup_manifest(), no_backup_check);
  io.println("migrations: " + r);
  let _ = driver.SqlDriver.close(&drv);
  if string.str_starts_with(r, "OK:") { return 0; }
  return 1;
}

/// cli_down is the `migrate down` entry: rolls back the latest batch.
pub fn cli_down(dsn: Str, dir: Str, stale_secs: Int, force: Bool) -> Int {
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
  let r = down(&drv, dir, cli_owner(), stale_secs, force);
  io.println("migrations: " + r);
  let _ = driver.SqlDriver.close(&drv);
  if string.str_starts_with(r, "OK:") { return 0; }
  return 1;
}

/// cli_create makes a stamped up/down stub in the migrations directory.
pub fn cli_create(dir: Str, name: Str) -> Int {
  let r = create(dir, name);
  io.println("migrations: " + r);
  if string.str_starts_with(r, "OK:") { return 0; }
  return 1;
}

/// cli_backup writes a snapshot + manifest; prints the manifest path so
/// the operator can export PULSE_SQL_BACKUP_MANIFEST.
pub fn cli_backup(dsn: Str, out_path: Str) -> Int {
  let r = backup(dsn, out_path);
  io.println("migrations: " + r);
  if string.str_starts_with(r, "OK:") { return 0; }
  return 1;
}

/// cli dispatches `migrate status|up|down|backup|create`; unknown
/// subcommands print usage.
pub fn cli(sub: Str, force: Bool, allow_missing: Bool, no_backup_check: Bool, name: Str) -> Int {
  let dsn = config.cfg_sql_dsn();
  let dir = config.cfg_migrations_dir();
  if sub == "status" { return cli_status(dsn, dir); }
  if sub == "up" { return cli_up(dsn, dir, config.cfg_migration_stale_secs(), force, allow_missing, no_backup_check); }
  if sub == "down" { return cli_down(dsn, dir, config.cfg_migration_stale_secs(), force); }
  if sub == "backup" { return cli_backup(dsn, name); }
  if sub == "create" { return cli_create(dir, name); }
  io.println("usage: pulse_migrate status|up|down [--force] [--allow-missing-applied] [--no-backup-check] | backup [path] | create <name>");
  return 1;
}
