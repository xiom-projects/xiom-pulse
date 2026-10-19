// XIOM PULSE -- SQL store/repository layer tests (bindings, CRUD, paging).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Gate for src/sql.xi. Runs against a throwaway SQLite file under
// probe-logs/; the build scripts pass the vendored amalgamation because this
// entry imports the SQL module.
module test_sql

use xiom.io;
use xiom.string;
use xiom.convert.time as ctime;
use xiom.serialize.json;
use xiom.pulse.station.sql;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn count_value(h: Int) -> Int {
  let r = sql.count_json(h, "users");
  if !r.is_ok { return -1; }
  let pv = json.json_parse(r.value);
  if !pv.is_ok { return -1; }
  let opt = json.json_get(pv.value, "count");
  if opt.is_some {
    let iv = json.json_as_int(opt.value);
    if iv.is_some { return iv.value; }
  }
  return -1;
}

fn pvec(one: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  out.push(one);
  return out;
}

fn user_cols() -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  out.push("name");
  out.push("score");
  out.push("note");
  return out;
}

fn user_vals(name: Str, score: Float64, note: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  out.push(sql.p_text(name));
  out.push(sql.p_real(score));
  out.push(note);
  return out;
}

pub fn main() -> Int {
  let dir = "probe-logs/sql-test-" + ctime.timestamp_now().to_str();
  let _ = io.create_dir_all(dir);
  let dsn = dir + "/pulse.db?busy_timeout=1500&journal_mode=wal";

  let o = sql.open(dsn);
  var f: Int = 0;
  f = f + check("open", o.is_ok);
  if !o.is_ok {
    io.println("open error: " + o.error);
    return f + 1;
  }
  let h = o.value;
  f = f + check("handle positive", h > 0);
  f = f + check("ping", sql.ping(h));
  f = f + check("not in transaction", !sql.in_tx(h));

  let ddl = sql.exec(h, "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, score REAL, note TEXT);");
  f = f + check("ddl exec", ddl.is_ok);

  let cols = user_cols();
  let v1 = user_vals("alice", 1.5, sql.p_text("first"));
  let i1 = sql.insert_json(h, "users", &cols, &v1);
  f = f + check("insert ok", i1.is_ok);
  if i1.is_ok {
    f = f + check("insert rowid 1", string.str_contains(i1.value, "\"last_insert_rowid\":1"));
  }
  let v2 = user_vals("bob", 2.5, sql.p_null());
  let i2 = sql.insert_json(h, "users", &cols, &v2);
  f = f + check("insert null ok", i2.is_ok);
  let v3 = user_vals("carol", 3.5, sql.p_text("third"));
  let i3 = sql.insert_json(h, "users", &cols, &v3);
  f = f + check("insert third ok", i3.is_ok);
  f = f + check("count 3", count_value(h) == 3);

  // Typed row mapping: exact integer, real, text, and NULL.
  let q = sql.query_json(h, "SELECT id, name, score, note FROM users ORDER BY id;");
  f = f + check("query json ok", q.is_ok);
  if q.is_ok {
    f = f + check("integer exact", string.str_contains(q.value, "\"id\":1,"));
    f = f + check("text value", string.str_contains(q.value, "\"name\":\"alice\""));
    f = f + check("real value", string.str_contains(q.value, "\"score\":1.5"));
    f = f + check("null value", string.str_contains(q.value, "\"note\":null"));
  }

  let hit = sql.find_json(h, "users", "id", sql.p_int(2));
  f = f + check("find hit", hit.is_ok && string.str_contains(hit.value, "\"name\":\"bob\""));
  let miss = sql.find_json(h, "users", "id", sql.p_int(999));
  f = f + check("find miss is null", miss.is_ok && miss.value == "null");

  // Bound values are literal: a quote/OR payload matches nothing.
  let inj_val = sql.find_json(h, "users", "name", sql.p_text("alice' OR '1'='1"));
  f = f + check("value injection is literal", inj_val.is_ok && inj_val.value == "null");
  f = f + check("value injection unchanged", count_value(h) == 3);

  // Identifiers are the only interpolated tokens and are validated.
  let inj_table = sql.find_json(h, "users; DROP TABLE users", "id", sql.p_int(1));
  f = f + check("table injection rejected", inj_table.is_err);
  var bad_cols: Vec[Str] = Vec[Str].new();
  bad_cols.push("name); DROP TABLE users;--");
  var bad_vals: Vec[Str] = Vec[Str].new();
  bad_vals.push(sql.p_text("x"));
  let inj_col = sql.insert_json(h, "users", &bad_cols, &bad_vals);
  f = f + check("column injection rejected", inj_col.is_err);
  f = f + check("table still present", count_value(h) == 3);

  // Malformed parameter encoding fails closed.
  let badp = sql.query_params_json(h, "SELECT * FROM users WHERE id = ?;", &pvec("x:1"));
  f = f + check("bad parameter kind rejected", badp.is_err);
  let btype = sql.query_params_json(h, "SELECT * FROM users WHERE id = ?;", &pvec("i:nope"));
  f = f + check("bad int parameter rejected", btype.is_err);

  // Generic typed parameter query.
  let gq = sql.query_params_json(h, "SELECT name FROM users WHERE score = ?;", &pvec(sql.p_real(2.5)));
  f = f + check("real parameter query", gq.is_ok && string.str_contains(gq.value, "\"name\":\"bob\""));

  // Update + find.
  var set_cols: Vec[Str] = Vec[Str].new();
  set_cols.push("name");
  var set_vals: Vec[Str] = Vec[Str].new();
  set_vals.push(sql.p_text("bob2"));
  let up = sql.update_json(h, "users", &set_cols, &set_vals, "id", sql.p_int(2));
  f = f + check("update ok", up.is_ok && string.str_contains(up.value, "\"rows_affected\":1"));
  let hit2 = sql.find_json(h, "users", "id", sql.p_int(2));
  f = f + check("update visible", hit2.is_ok && string.str_contains(hit2.value, "\"name\":\"bob2\""));

  // Paging: limit+1 has_more probe, then the tail page.
  let page1 = sql.list_json(h, "users", "id", false, 2, 0);
  f = f + check("page1 ok", page1.is_ok);
  if page1.is_ok {
    f = f + check("page1 has_more true", string.str_contains(page1.value, "\"has_more\":true"));
    f = f + check("page1 alice first", string.str_contains(page1.value, "\"name\":\"alice\""));
    f = f + check("page1 excludes carol", !string.str_contains(page1.value, "\"name\":\"carol\""));
  }
  let page2 = sql.list_json(h, "users", "id", false, 2, 2);
  f = f + check("page2 ok", page2.is_ok);
  if page2.is_ok {
    f = f + check("page2 has_more false", string.str_contains(page2.value, "\"has_more\":false"));
    f = f + check("page2 has carol", string.str_contains(page2.value, "\"name\":\"carol\""));
  }
  let badlimit = sql.list_json(h, "users", "id", false, 1001, 0);
  f = f + check("limit cap", badlimit.is_err);
  let badorder = sql.list_json(h, "users", "id; DROP TABLE users", false, 1, 0);
  f = f + check("order injection rejected", badorder.is_err);

  // Transactions: rollback drops the insert, commit keeps it.
  let v4 = user_vals("dave", 4.5, sql.p_text("fourth"));
  f = f + check("tx begin", sql.tx_begin(h));
  f = f + check("tx in progress", sql.in_tx(h));
  let ti = sql.insert_json(h, "users", &cols, &v4);
  f = f + check("tx insert ok", ti.is_ok);
  f = f + check("tx rollback", sql.tx_rollback(h));
  f = f + check("rollback dropped", count_value(h) == 3);
  f = f + check("tx begin 2", sql.tx_begin(h));
  let ti2 = sql.insert_json(h, "users", &cols, &v4);
  f = f + check("tx insert 2 ok", ti2.is_ok);
  f = f + check("tx commit", sql.tx_commit(h));
  f = f + check("commit kept", count_value(h) == 4);

  // Delete by key.
  let del = sql.delete_json(h, "users", "id", sql.p_int(4));
  f = f + check("delete ok", del.is_ok && string.str_contains(del.value, "\"rows_affected\":1"));
  f = f + check("delete count", count_value(h) == 3);

  // Driver errors keep the code+message pair.
  let badsql = sql.query_json(h, "SELECT * FROM nope;");
  f = f + check("bad sql is err", badsql.is_err);
  if badsql.is_err {
    f = f + check("bad sql names SQLITE", string.str_contains(badsql.error, "SQLITE "));
  }

  // Close fails closed for later calls.
  f = f + check("close", sql.close(h));
  f = f + check("close twice fails", !sql.close(h));
  f = f + check("query after close fails", sql.query_json(h, "SELECT 1;").is_err);
  f = f + check("open empty dsn fails", sql.open("").is_err);

  if f == 0 {
    io.println("pulse-sql: GREEN");
  } else {
    io.println("pulse-sql: FAILED=" + f.to_str());
  }
  return f;
}
