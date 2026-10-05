// XIOM PULSE -- append-only JSONL event store (Step 3, zero-dependency).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One JSON object per line. The first record is the schema marker; the
// loader tolerates a torn trailing line (crash mid-append) by skipping any
// line that does not parse. `xiom.kv` (package wishlist) is the intended
// embedded replacement when the packages lane ships it.
module xiom.pulse.store

use xiom.io;
use xiom.string;
use xiom.time;
use xiom.convert;
use xiom.serialize.json;

const SCHEMA_VERSION: Int = 1;

fn schema_line() -> Str {
  // Workaround: `SCHEMA_VERSION.to_str()` on a module-level const receiver
  // hits the W005 erased-interface stub on v0.63.1 (renders empty ->
  // invalid JSON). The free function resolves correctly.
  return "{\"kind\":\"schema\",\"version\":" + convert.int_to_string(SCHEMA_VERSION) + "}";
}

/// store_init creates the file with a schema record when missing.
/// Complexity: O(1).
pub fn store_init(path: Str) -> Bool {
  if io.file_exists(path) { return true; }
  let w = io.write_file(path, schema_line() + "\n");
  return w.is_ok;
}

fn file_ends_with_newline(path: Str) -> Bool {
  let r = io.read_file(path);
  if r.is_err { return true; }
  let s = r.value;
  if s.len() == 0 { return true; }
  let b = s.byte_at(s.len() - 1);
  return b == 10u8;
}

/// store_append appends one already-valid JSON record line. If a crash left
/// a torn trailing line (no newline), a newline is written first so the new
/// record cannot fuse with the torn remainder. Complexity: O(n).
pub fn store_append(path: Str, record: Str) -> Bool {
  if !file_ends_with_newline(path) {
    let heal = io.append_file(path, "\n");
    if heal.is_err { return false; }
  }
  let r = io.append_line(path, record);
  return r.is_ok;
}

/// store_valid_records returns valid non-schema records in file order.
/// Torn/invalid lines (crash truncation) are skipped. Complexity: O(n).
pub fn store_valid_records(path: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  let rr = io.read_file_lines(path);
  if rr.is_err { return out; }
  let lines = rr.value;
  var i: Int = 0;
  while i < lines.len() {
    let line = lines[i];
    if line.len() > 0 {
      let pv = json.json_parse(line);
      if pv.is_ok && !string.str_contains(line, "\"kind\":\"schema\"") {
        out.push(line);
      }
    }
    i = i + 1;
  }
  return out;
}

/// store_count returns the number of valid records. Complexity: O(n).
pub fn store_count(path: Str) -> Int {
  return store_valid_records(path).len();
}

/// store_last returns up to `n` most recent records (oldest first).
/// Complexity: O(n).
pub fn store_last(path: Str, n: Int) -> Vec[Str] {
  let all = store_valid_records(path);
  var out: Vec[Str] = Vec[Str].new();
  var start: Int = all.len() - n;
  if start < 0 { start = 0; }
  var i: Int = start;
  while i < all.len() {
    out.push(all[i]);
    i = i + 1;
  }
  return out;
}

/// store_append_event appends `{"kind":"event","ts":<unix>,"data":<body>}`.
/// `body_json` must already be valid JSON. Complexity: O(1).
pub fn store_append_event(path: Str, body_json: Str) -> Bool {
  let rec = "{\"kind\":\"event\",\"ts\":" + time.unix_timestamp().to_str() + ",\"data\":" + body_json + "}";
  return store_append(path, rec);
}

/// store_compact rewrites the file with only valid records (drops torn or
/// corrupt lines) via a temp file + atomic replace (Windows
/// MoveFileEx REPLACE_EXISTING). Complexity: O(n).
pub fn store_compact(path: Str) -> Bool {
  if !io.file_exists(path) { return true; }
  var content: Str = schema_line() + "\n";
  let recs = store_valid_records(path);
  var i: Int = 0;
  while i < recs.len() {
    let r = recs[i];
    content = content + r + "\n";
    i = i + 1;
  }
  let tmp = path + ".tmp";
  let w = io.write_file(tmp, content);
  if w.is_err { return false; }
  let mv = io.rename(tmp, path);
  if mv.is_err {
    let _rm = io.remove_file(tmp);
    return false;
  }
  return true;
}

/// record_kind returns the record's `data.kind` string, or "".
/// Complexity: O(record).
fn record_kind(rec: Str) -> Str {
  let pv = json.json_parse(rec);
  if pv.is_err { return ""; }
  let dopt = json.json_get(pv.value, "data");
  if dopt.is_none { return ""; }
  let dv = dopt.value;
  if json.json_type(dv) != "object" { return ""; }
  let kopt = json.json_get(dv, "kind");
  if kopt.is_none { return ""; }
  let kv = kopt.value;
  if json.json_type(kv) != "string" { return ""; }
  var ks: Str = "";
  match kv {
    JsonValue.String(x) => { ks = x; },
    _ => { return ""; },
  }
  return ks;
}

/// store_last_kind returns up to `n` newest records whose `data.kind`
/// equals `kind`, oldest-first. Complexity: O(n).
pub fn store_last_kind(path: Str, kind: Str, n: Int) -> Vec[Str] {
  let all = store_valid_records(path);
  var picked: Vec[Str] = Vec[Str].new();
  var i: Int = all.len() - 1;
  while i >= 0 && picked.len() < n {
    let r = all[i];
    let k = record_kind(r);
    if k == kind {
      picked.push(r);
    }
    i = i - 1;
  }
  var rev: Vec[Str] = Vec[Str].new();
  var j: Int = picked.len() - 1;
  while j >= 0 {
    rev.push(picked[j]);
    j = j - 1;
  }
  return rev;
}

/// store_join_array renders records as a JSON array text.
/// Complexity: O(n). Pure.
pub fn store_join_array(records: &Vec[Str]) -> Str {
  var out: Str = "[";
  var i: Int = 0;
  while i < records.len() {
    if i > 0 { out = out + ","; }
    let r = records[i];
    out = out + r;
    i = i + 1;
  }
  return out + "]";
}
