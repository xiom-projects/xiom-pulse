// XIOM PULSE -- opt-in SQL store + repository/query layer over xiom.sqlite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Design: docs/DESIGN-SQL-STORE.md (knex query-builder matrix).
// This module is NOT imported by the serving binary; SQL stays opt-in until
// the pool and the serving surface are settled. Builds that include it must
// pass the vendored sqlite C source (the build scripts detect the import).
//
// Safety rules:
//   * Values are ALWAYS bound through xiom.sqlite.prepare/bind_*; the
//     string-interpolating xiom.sqlite.query helpers are deliberately unused.
//   * Table/column names are the only interpolated tokens and must pass
//     ident_ok() (ASCII [A-Za-z_][A-Za-z0-9_]*).
//   * Results cross the module boundary as JSON text (exact integers, typed
//     reals/text/null). Blobs are not exposed in v1 (no column_blob accessor).
//
// Cross-module returns are Int/Str/Bool only (compiler finding m371):
// connections are integer handles into a module-local registry, mirroring
// the kv-holder pattern proven in src/store.xi.
module xiom.pulse.station.sql

use xiom.string;
use xiom.convert;
use xiom.convert.parse;
use xiom.serialize.json;
use xiom.sqlite;
use xiom.sqlite.driver;
use xiom.sqlite.types;

// Fundamental SQLite datatypes (frozen ABI; literals avoid cross-module
// const-alias resolver issues noted by the package).
const SQL_INTEGER: Int = 1;
const SQL_FLOAT: Int = 2;
const SQL_TEXT: Int = 3;
const SQL_BLOB: Int = 4;
const SQL_NULL: Int = 5;

const MAX_PAGE: Int = 1000;

var g_drvs: Vec[driver.SqlDriver] = Vec[driver.SqlDriver].new();
var g_closed: Vec[Int] = Vec[Int].new();

// --- connection registry ----------------------------------------------------

fn is_closed(handle: Int) -> Bool {
  var i: Int = 0;
  while i < g_closed.len() {
    if g_closed[i] == handle { return true; }
    i = i + 1;
  }
  return false;
}

fn is_open(handle: Int) -> Bool {
  if handle < 1 { return false; }
  if handle > g_drvs.len() { return false; }
  return !is_closed(handle);
}

fn err_text(e: types.SqliteError) -> Str {
  return "SQLITE " + e.code.to_str() + ": " + e.message;
}

/// open opens a connection from a DSN and returns its integer handle.
/// The DSN grammar is the driver's (sqlite path + busy_timeout/journal_mode).
/// Complexity: O(1).
pub fn open(dsn: Str) -> Result[Int, Str] {
  if dsn.len() == 0 { return Err("sql: empty DSN"); }
  let o = driver.SqlDriver.open_from_dsn(dsn);
  if !o.is_ok { return Err("sql: open failed: " + o.error.message); }
  g_drvs.push(o.value);
  return Ok(g_drvs.len());
}

/// close releases a connection handle. Closing twice fails (false).
/// Complexity: O(n) in the small closed-handle list.
pub fn close(handle: Int) -> Bool {
  if !is_open(handle) { return false; }
  let c = driver.SqlDriver.close(&g_drvs[handle - 1]);
  g_closed.push(handle);
  return c.is_ok;
}

/// last_error returns the connection's most recent code+message pair.
/// Complexity: O(1).
pub fn last_error(handle: Int) -> Str {
  if !is_open(handle) { return "sql: invalid handle"; }
  return err_text(driver.SqlDriver.last_error(&g_drvs[handle - 1]));
}

/// ping verifies the connection can execute a trivial query.
/// Complexity: O(1).
pub fn ping(handle: Int) -> Bool {
  if !is_open(handle) { return false; }
  let q = query_one_json(handle, "SELECT 1 AS ok;");
  return q.is_ok && q.value != "null";
}

// --- parameter encoding -----------------------------------------------------

/// p_text encodes a text parameter ("s:" + payload).
pub fn p_text(value: Str) -> Str { return "s:" + value; }

/// p_int encodes an integer parameter ("i:" + decimal).
pub fn p_int(value: Int) -> Str { return "i:" + value.to_str(); }

/// p_real encodes a real parameter ("r:" + decimal).
pub fn p_real(value: Float64) -> Str { return "r:" + convert.float_to_string(value); }

/// p_null encodes SQL NULL ("n:").
pub fn p_null() -> Str { return "n:"; }

fn malformed_param(index: Int) -> Str {
  return "sql: malformed parameter at index " + index.to_str();
}

/// bind_all binds encoded parameters in placeholder order. Returns "" on
/// success or the first validation/binding error. Complexity: O(params).
fn bind_all(stmt: Int, params: &Vec[Str]) -> Str {
  var i: Int = 0;
  while i < params.len() {
    let p = params[i];
    if p.len() < 2 { return malformed_param(i + 1); }
    let kind = string.str_slice(p, 0, 1);
    let value = string.str_slice(p, 2, p.len());
    if kind == "s" {
      let r = sqlite.bind_text(stmt, i + 1, value);
      if !r.is_ok { return err_text(r.error); }
    } elif kind == "i" {
      let pi = parse.parse_int(value);
      if !pi.is_ok { return malformed_param(i + 1); }
      let r = sqlite.bind_int64(stmt, i + 1, pi.value);
      if !r.is_ok { return err_text(r.error); }
    } elif kind == "r" {
      let pf = parse.parse_float(value);
      if !pf.is_ok { return malformed_param(i + 1); }
      let r = sqlite.bind_double(stmt, i + 1, pf.value);
      if !r.is_ok { return err_text(r.error); }
    } elif kind == "n" {
      let r = sqlite.bind_null(stmt, i + 1);
      if !r.is_ok { return err_text(r.error); }
    } else {
      return malformed_param(i + 1);
    }
    i = i + 1;
  }
  return "";
}

// --- result mapping ---------------------------------------------------------

fn value_json(stmt: Int, idx: Int) -> Str {
  let t = sqlite.column_type(stmt, idx);
  if t == SQL_NULL { return "null"; }
  if t == SQL_INTEGER { return sqlite.column_int64(stmt, idx).to_str(); }
  if t == SQL_FLOAT { return convert.float_to_string(sqlite.column_double(stmt, idx)); }
  if t == SQL_TEXT { return "\"" + json.json_escape(sqlite.column_text(stmt, idx)) + "\""; }
  // SQL_BLOB (and any unknown type): the driver has no blob accessor in
  // v1, so the wire format stays honest and maps it to null.
  return "null";
}

fn row_json(stmt: Int) -> Str {
  var out: Str = "{";
  var i: Int = 0;
  let n = sqlite.column_count(stmt);
  while i < n {
    if i > 0 { out = out + ","; }
    out = out + "\"" + json.json_escape(sqlite.column_name(stmt, i)) + "\":";
    out = out + value_json(stmt, i);
    i = i + 1;
  }
  return out + "}";
}

fn rows_json(rows: &Vec[Str], count: Int) -> Str {
  var out: Str = "[";
  var i: Int = 0;
  while i < count && i < rows.len() {
    if i > 0 { out = out + ","; }
    out = out + rows[i];
    i = i + 1;
  }
  return out + "]";
}

// --- execution --------------------------------------------------------------

fn run_rows(handle: Int, statement: Str, params: &Vec[Str], max_rows: Int) -> Result[Vec[Str], Str] {
  let db = driver.SqlDriver.db(&g_drvs[handle - 1]);
  let p = sqlite.prepare(db, statement);
  if !p.is_ok { return Err(err_text(p.error)); }
  let stmt = p.value;
  let be = bind_all(stmt, params);
  if be.len() > 0 {
    let _ = sqlite.finalize(stmt);
    return Err(be);
  }
  var out: Vec[Str] = Vec[Str].new();
  var done: Bool = false;
  var failed: Str = "";
  while !done && failed.len() == 0 {
    if max_rows >= 0 && out.len() >= max_rows {
      done = true;
    } else {
      let s = sqlite.step(stmt);
      if !s.is_ok {
        failed = err_text(s.error);
      } elif s.value {
        out.push(row_json(stmt));
      } else {
        done = true;
      }
    }
  }
  let f = sqlite.finalize(stmt);
  if failed.len() > 0 { return Err(failed); }
  if !f.is_ok { return Err(err_text(f.error)); }
  return Ok(out);
}

fn run_exec_params(handle: Int, statement: Str, params: &Vec[Str]) -> Result[Int, Str] {
  let db = driver.SqlDriver.db(&g_drvs[handle - 1]);
  let p = sqlite.prepare(db, statement);
  if !p.is_ok { return Err(err_text(p.error)); }
  let stmt = p.value;
  let be = bind_all(stmt, params);
  if be.len() > 0 {
    let _ = sqlite.finalize(stmt);
    return Err(be);
  }
  var done: Bool = false;
  var failed: Str = "";
  while !done && failed.len() == 0 {
    let s = sqlite.step(stmt);
    if !s.is_ok {
      failed = err_text(s.error);
    } elif !s.value {
      done = true;
    }
  }
  let f = sqlite.finalize(stmt);
  if failed.len() > 0 { return Err(failed); }
  if !f.is_ok { return Err(err_text(f.error)); }
  return Ok(sqlite.changes(db));
}

/// exec runs a non-query statement (or a multi-statement DDL script) and
/// returns the rows affected by the LAST statement. Use exec_params for
/// statements with values. Complexity: O(statements).
pub fn exec(handle: Int, statement: Str) -> Result[Int, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  if statement.len() == 0 { return Err("sql: empty statement"); }
  let r = driver.SqlDriver.execute(&g_drvs[handle - 1], statement);
  if !r.is_ok { return Err(err_text(r.error)); }
  return Ok(r.value.rows_affected);
}

/// exec_params runs one prepared statement with bound values.
/// Complexity: O(rows changed).
pub fn exec_params(handle: Int, statement: Str, params: &Vec[Str]) -> Result[Int, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  if statement.len() == 0 { return Err("sql: empty statement"); }
  return run_exec_params(handle, statement, params);
}

/// query_params_json runs a SELECT with bound values and returns rows as a
/// JSON array. Complexity: O(rows * columns).
pub fn query_params_json(handle: Int, statement: Str, params: &Vec[Str]) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  if statement.len() == 0 { return Err("sql: empty statement"); }
  let r = run_rows(handle, statement, params, -1);
  if !r.is_ok { return Err(r.error); }
  return Ok(rows_json(&r.value, r.value.len()));
}

/// query_json runs a SELECT without values.
pub fn query_json(handle: Int, statement: Str) -> Result[Str, Str] {
  var none: Vec[Str] = Vec[Str].new();
  return query_params_json(handle, statement, &none);
}

/// query_one_params_json returns the first row as an object or "null".
pub fn query_one_params_json(handle: Int, statement: Str, params: &Vec[Str]) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  if statement.len() == 0 { return Err("sql: empty statement"); }
  let r = run_rows(handle, statement, params, 1);
  if !r.is_ok { return Err(r.error); }
  if r.value.len() == 0 { return Ok("null"); }
  return Ok(r.value[0]);
}

/// query_one_json returns the first row as an object or "null".
pub fn query_one_json(handle: Int, statement: Str) -> Result[Str, Str] {
  var none: Vec[Str] = Vec[Str].new();
  return query_one_params_json(handle, statement, &none);
}

// --- identifier validation --------------------------------------------------

fn is_alpha(b: UInt8) -> Bool {
  return (b >= 65u8 && b <= 90u8) || (b >= 97u8 && b <= 122u8);
}

fn is_digit(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

/// ident_ok accepts ASCII [A-Za-z_][A-Za-z0-9_]* -- the only tokens this
/// module interpolates. Complexity: O(len).
fn ident_ok(name: Str) -> Bool {
  if name.len() == 0 { return false; }
  let first = name.byte_at(0);
  if !is_alpha(first) && first != 95u8 { return false; }
  var i: Int = 1;
  while i < name.len() {
    let b = name.byte_at(i);
    if !is_alpha(b) && !is_digit(b) && b != 95u8 { return false; }
    i = i + 1;
  }
  return true;
}

fn valid_ident(name: Str, what: Str) -> Str {
  if ident_ok(name) { return ""; }
  return "sql: invalid " + what + " identifier";
}

fn columns_sql(columns: &Vec[Str], out: &mut Str) -> Str {
  var i: Int = 0;
  while i < columns.len() {
    let bad = valid_ident(columns[i], "column");
    if bad.len() > 0 { return bad; }
    if i > 0 { *out = *out + ", "; }
    *out = *out + columns[i];
    i = i + 1;
  }
  return "";
}

fn placeholders(count: Int, out: &mut Str) -> Str {
  var i: Int = 0;
  while i < count {
    if i > 0 { *out = *out + ", "; }
    *out = *out + "?";
    i = i + 1;
  }
  return "";
}

// --- repository -------------------------------------------------------------

/// find_json selects one row by an equality key; "null" when absent.
/// Complexity: O(1) with an indexed key.
pub fn find_json(handle: Int, table_name: Str, key_column: Str, key_value: Str) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  let bt = valid_ident(table_name, "table");
  if bt.len() > 0 { return Err(bt); }
  let bk = valid_ident(key_column, "column");
  if bk.len() > 0 { return Err(bk); }
  var params: Vec[Str] = Vec[Str].new();
  params.push(key_value);
  let sql = "SELECT * FROM " + table_name + " WHERE " + key_column + " = ? LIMIT 1;";
  return query_one_params_json(handle, sql, &params);
}

/// list_json pages a table with the limit+1 has_more probe.
/// order_column may be "" to use the engine's natural order.
/// Complexity: O(limit).
pub fn list_json(handle: Int, table_name: Str, order_column: Str, desc: Bool, limit: Int, offset: Int) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  let bt = valid_ident(table_name, "table");
  if bt.len() > 0 { return Err(bt); }
  if order_column.len() > 0 {
    let bo = valid_ident(order_column, "column");
    if bo.len() > 0 { return Err(bo); }
  }
  if limit < 0 { return Err("sql: limit must be >= 0"); }
  if limit > MAX_PAGE { return Err("sql: limit exceeds " + MAX_PAGE.to_str()); }
  if offset < 0 { return Err("sql: offset must be >= 0"); }
  var sql = "SELECT * FROM " + table_name;
  if order_column.len() > 0 {
    sql = sql + " ORDER BY " + order_column;
    if desc { sql = sql + " DESC"; } else { sql = sql + " ASC"; }
  }
  sql = sql + " LIMIT ? OFFSET ?;";
  var params: Vec[Str] = Vec[Str].new();
  params.push(p_int(limit + 1));
  params.push(p_int(offset));
  let r = run_rows(handle, sql, &params, limit + 1);
  if !r.is_ok { return Err(r.error); }
  var has_more: Bool = r.value.len() > limit;
  var count = r.value.len();
  if has_more { count = limit; }
  var out = "{\"rows\":" + rows_json(&r.value, count) + ",\"has_more\":";
  if has_more { out = out + "true"; } else { out = out + "false"; }
  return Ok(out + "}");
}

/// count_json returns {"count":N} for a table.
/// Complexity: O(rows) unless the engine optimizes COUNT(*).
pub fn count_json(handle: Int, table_name: Str) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  let bt = valid_ident(table_name, "table");
  if bt.len() > 0 { return Err(bt); }
  let q = query_one_json(handle, "SELECT COUNT(*) AS n FROM " + table_name + ";");
  if !q.is_ok { return Err(q.error); }
  // Raw-int parse keeps 64-bit counts exact (the JSON tree stores numbers
  // as Float64; the raw accessor reads the decimal text).
  let iv = json.json_raw_get_int(q.value, "n");
  if iv.is_ok { return Ok("{\"count\":" + iv.value.to_str() + "}"); }
  return Err("sql: count mapping failed");
}

/// insert_json inserts one row from column/value pairs and reports the
/// generated rowid. Values are encoded with p_text/p_int/p_real/p_null.
/// Complexity: O(columns).
pub fn insert_json(handle: Int, table_name: Str, columns: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  let bt = valid_ident(table_name, "table");
  if bt.len() > 0 { return Err(bt); }
  if columns.len() == 0 { return Err("sql: insert needs at least one column"); }
  if columns.len() != values.len() { return Err("sql: insert columns/values mismatch"); }
  var sql = "INSERT INTO " + table_name + " (";
  let bc = columns_sql(columns, &mut sql);
  if bc.len() > 0 { return Err(bc); }
  sql = sql + ") VALUES (";
  let _ph = placeholders(columns.len(), &mut sql);
  sql = sql + ");";
  let r = run_exec_params(handle, sql, values);
  if !r.is_ok { return Err(r.error); }
  let db = driver.SqlDriver.db(&g_drvs[handle - 1]);
  let rowid = sqlite.last_insert_rowid(db);
  return Ok("{\"rows_affected\":" + r.value.to_str() + ",\"last_insert_rowid\":" + rowid.to_str() + "}");
}

/// update_json updates rows by an equality key.
/// Complexity: O(columns).
pub fn update_json(handle: Int, table_name: Str, set_columns: &Vec[Str], set_values: &Vec[Str], key_column: Str, key_value: Str) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  let bt = valid_ident(table_name, "table");
  if bt.len() > 0 { return Err(bt); }
  let bk = valid_ident(key_column, "column");
  if bk.len() > 0 { return Err(bk); }
  if set_columns.len() == 0 { return Err("sql: update needs at least one column"); }
  if set_columns.len() != set_values.len() { return Err("sql: update columns/values mismatch"); }
  var sql = "UPDATE " + table_name + " SET ";
  var i: Int = 0;
  while i < set_columns.len() {
    let bc = valid_ident(set_columns[i], "column");
    if bc.len() > 0 { return Err(bc); }
    if i > 0 { sql = sql + ", "; }
    sql = sql + set_columns[i] + " = ?";
    i = i + 1;
  }
  sql = sql + " WHERE " + key_column + " = ?;";
  var params: Vec[Str] = Vec[Str].new();
  i = 0;
  while i < set_values.len() {
    params.push(set_values[i]);
    i = i + 1;
  }
  params.push(key_value);
  let r = run_exec_params(handle, sql, &params);
  if !r.is_ok { return Err(r.error); }
  return Ok("{\"rows_affected\":" + r.value.to_str() + "}");
}

/// delete_json deletes rows by an equality key.
/// Complexity: O(rows deleted).
pub fn delete_json(handle: Int, table_name: Str, key_column: Str, key_value: Str) -> Result[Str, Str] {
  if !is_open(handle) { return Err("sql: invalid handle"); }
  let bt = valid_ident(table_name, "table");
  if bt.len() > 0 { return Err(bt); }
  let bk = valid_ident(key_column, "column");
  if bk.len() > 0 { return Err(bk); }
  var params: Vec[Str] = Vec[Str].new();
  params.push(key_value);
  let r = run_exec_params(handle, "DELETE FROM " + table_name + " WHERE " + key_column + " = ?;", &params);
  if !r.is_ok { return Err(r.error); }
  return Ok("{\"rows_affected\":" + r.value.to_str() + "}");
}

// --- transactions -----------------------------------------------------------

/// tx_begin opens an explicit transaction. Complexity: O(1).
pub fn tx_begin(handle: Int) -> Bool {
  if !is_open(handle) { return false; }
  let r = driver.SqlDriver.transaction_begin(&g_drvs[handle - 1]);
  return r.is_ok;
}

/// tx_commit commits the open transaction. Complexity: O(1).
pub fn tx_commit(handle: Int) -> Bool {
  if !is_open(handle) { return false; }
  let r = driver.SqlDriver.transaction_commit(&g_drvs[handle - 1]);
  return r.is_ok;
}

/// tx_rollback rolls back the open transaction. Complexity: O(1).
pub fn tx_rollback(handle: Int) -> Bool {
  if !is_open(handle) { return false; }
  let r = driver.SqlDriver.transaction_rollback(&g_drvs[handle - 1]);
  return r.is_ok;
}

/// in_tx reports whether a transaction is open on this handle.
/// Complexity: O(1).
pub fn in_tx(handle: Int) -> Bool {
  if !is_open(handle) { return false; }
  return driver.SqlDriver.in_transaction(&g_drvs[handle - 1]);
}
