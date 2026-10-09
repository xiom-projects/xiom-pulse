// XIOM PULSE -- append-only event store: JSONL (default) or xiom.kv (opt-in).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Two backends behind the same functions:
//   * jsonl (default): one JSON object per line; the loader tolerates a
//     torn trailing line (crash mid-append) by skipping invalid lines.
//   * kv (PULSE_STORE_BACKEND=kv, v0.64.1+): the registry xiom.kv embedded
//     store; records live under `PULSE_KV_PREFIX` + a 10-digit sequence in
//     `PULSE_KV_DIR` (created on demand). No torn lines; compact is native.
//     Requires a compiler with the m217 fix (kv_get); on v0.64.0 kv_get is
//     defective and values are read through the bytes API instead.
//
// The kv mode keeps the module-level store holder + direct calls in THIS
// module only (the single-module pattern proven green in probe_pkg_kv and
// probe_pkg_session; cross-module aggregate bridges crash -- C-PULSE-09).
module xiom.pulse.store

use xiom.io;
use xiom.string;
use xiom.time;
use xiom.convert;
use xiom.serialize.json;
use xiom.env;
use xiom.kv;

const SCHEMA_VERSION: Int = 1;

/// StorePage - one timeline page of event records: records oldest-first
/// within the page, `first_seq` = cursor of the oldest record (0 when the
/// page is empty; pass it as `before` to fetch the next older page), and
/// `has_more` = an older eligible record exists beyond this page.
pub type StorePage = {
  records: Vec[Str];
  first_seq: Int;
  has_more: Bool;
}

// --- kv backend state -------------------------------------------------------

var g_kvs: Vec[KvStore] = Vec[KvStore].new();
var g_seq: Int = 0;

fn backend_kv() -> Bool {
  return env.var_or("PULSE_STORE_BACKEND", "jsonl") == "kv";
}

fn kv_mode_dir() -> Str {
  return env.var_or("PULSE_KV_DIR", "pulse-kv");
}

fn kv_mode_prefix() -> Str {
  return env.var_or("PULSE_KV_PREFIX", "evt-");
}

fn pad10(n: Int) -> Str {
  let s = convert.int_to_string(n);
  var zeros: Str = "";
  var i: Int = s.len();
  while i < 10 {
    zeros = zeros + "0";
    i = i + 1;
  }
  return zeros + s;
}

/// kv_ensure opens the embeded store on first use (dir created on demand)
/// and seeds the sequence from the entry count. Complexity: O(1).
fn kv_ensure() -> Bool {
  if g_kvs.len() > 0 { return true; }
  let _cd = io.create_dir_all(kv_mode_dir());
  let orr = kv_open(kv_mode_dir(), kv_mode_prefix(), 4096);
  if orr.is_err { return false; }
  g_kvs.push(orr.value);
  g_seq = kv_count(&g_kvs[0]);
  return true;
}

/// kv_get_text reads a value through the bytes API (stable on every
/// version; the vector is passed by value per the v0.64.1 notes).
/// Complexity: O(value).
fn kv_get_text(key: Str) -> Str {
  let gb = kv_get_bytes(&g_kvs[0], key);
  if gb.is_err { return ""; }
  if gb.value.is_none { return ""; }
  let vb = gb.value.value;
  return Str::from_utf8(vb);
}

/// kv_records returns every live record in sequence order (our keys are
/// prefix + zero-padded sequence, so enumeration needs no sorting).
/// Complexity: O(n).
fn kv_records() -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  if !kv_ensure() { return out; }
  var seq: Int = 1;
  while seq <= g_seq {
    let key = kv_mode_prefix() + pad10(seq);
    if kv_contains(&g_kvs[0], key) {
      let t = kv_get_text(key);
      if t.len() > 0 { out.push(t); }
    }
    seq = seq + 1;
  }
  return out;
}

// --- shared helpers ---------------------------------------------------------

fn schema_line() -> Str {
  // Workaround: `SCHEMA_VERSION.to_str()` on a module-level const receiver
  // hits the W005 erased-interface stub on v0.63.1 (renders empty ->
  // invalid JSON). The free function resolves correctly.
  return "{\"kind\":\"schema\",\"version\":" + convert.int_to_string(SCHEMA_VERSION) + "}";
}

// --- public API -------------------------------------------------------------

/// store_init prepares the store. jsonl: creates the file with a schema
/// record when missing. kv: creates the directory and opens the store.
/// Complexity: O(1).
pub fn store_init(path: Str) -> Bool {
  if backend_kv() {
    return kv_ensure();
  }
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

/// store_append appends one already-valid JSON record. jsonl: heals a torn
/// trailing line first. kv: puts the next sequence key. Complexity: O(n).
pub fn store_append(path: Str, record: Str) -> Bool {
  if backend_kv() {
    if !kv_ensure() { return false; }
    g_seq = g_seq + 1;
    let key = kv_mode_prefix() + pad10(g_seq);
    let r = kv_put(&mut g_kvs[0], key, record);
    if r.is_err { g_seq = g_seq - 1; }
    return r.is_ok;
  }
  if !file_ends_with_newline(path) {
    let heal = io.append_file(path, "\n");
    if heal.is_err { return false; }
  }
  let r = io.append_line(path, record);
  return r.is_ok;
}

/// store_valid_records returns valid non-schema records in order.
/// Torn/invalid lines (crash truncation) are skipped in jsonl mode.
/// Complexity: O(n).
pub fn store_valid_records(path: Str) -> Vec[Str] {
  if backend_kv() {
    let recs = kv_records();
    var out: Vec[Str] = Vec[Str].new();
    var i: Int = 0;
    while i < recs.len() {
      let line = recs[i];
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

/// store_record_seq returns the record's embedded sequence cursor (the
/// `seq` field written by 0.2+ builds); 0 when absent (pre-0.2 records).
/// Complexity: O(record).
pub fn store_record_seq(rec: Str) -> Int {
  let pv = json.json_parse(rec);
  if pv.is_err { return 0; }
  let sopt = json.json_get(pv.value, "seq");
  if sopt.is_none { return 0; }
  let sv = sopt.value;
  match sv {
    JsonValue.Number(f) => {
      let n = convert.float_to_int(f);
      if n > 0 { return n; }
      return 0;
    },
    _ => { return 0; },
  }
}

/// effective_seq is the record's explicit seq; pre-0.2 records fall back to
/// their 1-based ordinal among valid records (stable under compaction,
/// which only drops invalid lines). Complexity: O(record).
fn effective_seq(rec: Str, ordinal: Int) -> Int {
  let s = store_record_seq(rec);
  if s > 0 { return s; }
  return ordinal;
}

/// store_max_seq returns the highest effective sequence in the store (0
/// when empty). Complexity: O(n).
fn store_max_seq(path: Str) -> Int {
  let all = store_valid_records(path);
  var m: Int = 0;
  var i: Int = 0;
  while i < all.len() {
    let s = effective_seq(all[i], i + 1);
    if s > m { m = s; }
    i = i + 1;
  }
  return m;
}

/// store_append_event appends
/// `{"kind":"event","seq":N,"ts":<unix>,"data":<body>}`; the sequence cursor
/// is durable in the record (kv keys mirror it; JSONL derives N from the
/// current maximum). `body_json` must already be valid JSON. Complexity:
/// O(n) jsonl / O(1) kv.
pub fn store_append_event(path: Str, body_json: Str) -> Bool {
  var seq: Int = 0;
  if backend_kv() {
    if !kv_ensure() { return false; }
    seq = g_seq + 1;
  } else {
    seq = store_max_seq(path) + 1;
  }
  let rec = "{\"kind\":\"event\",\"seq\":" + convert.int_to_string(seq) + ",\"ts\":" + time.unix_timestamp().to_str() + ",\"data\":" + body_json + "}";
  return store_append(path, rec);
}

/// store_compact drops invalid records. jsonl: temp file + atomic replace
/// (Windows MoveFileEx REPLACE_EXISTING). kv: native compact.
/// Complexity: O(n).
pub fn store_compact(path: Str) -> Bool {
  if backend_kv() {
    if !kv_ensure() { return false; }
    let r = kv_compact(&mut g_kvs[0]);
    return r.is_ok;
  }
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

/// store_page returns up to `limit` records older than the `before` cursor
/// (0 = newest page), oldest-first within the page; a non-empty `kind`
/// filters on `data.kind`. Complexity: O(n).
pub fn store_page(path: Str, kind: Str, limit: Int, before: Int) -> StorePage {
  var lim: Int = limit;
  if lim < 1 { lim = 1; }
  let all = store_valid_records(path);
  var picked_rev: Vec[Str] = Vec[Str].new();
  var first_seq: Int = 0;
  var has_more: Bool = false;
  var i: Int = all.len() - 1;
  while i >= 0 {
    let rec = all[i];
    let s = effective_seq(rec, i + 1);
    var eligible: Bool = (before == 0) || (s < before);
    if eligible && kind.len() > 0 {
      eligible = record_kind(rec) == kind;
    }
    if eligible {
      if picked_rev.len() < lim {
        picked_rev.push(rec);
        first_seq = s;
      } else {
        has_more = true;
        break;
      }
    }
    i = i - 1;
  }
  var records: Vec[Str] = Vec[Str].new();
  var j: Int = picked_rev.len() - 1;
  while j >= 0 {
    records.push(picked_rev[j]);
    j = j - 1;
  }
  return StorePage{ records: records; first_seq: first_seq; has_more: has_more; };
}

/// store_last returns up to `n` most recent records (oldest first).
/// Complexity: O(n).
pub fn store_last(path: Str, n: Int) -> Vec[Str] {
  return store_page(path, "", n, 0).records;
}

/// store_last_kind returns up to `n` newest records whose `data.kind`
/// equals `kind`, oldest-first. Complexity: O(n).
pub fn store_last_kind(path: Str, kind: Str, n: Int) -> Vec[Str] {
  return store_page(path, kind, n, 0).records;
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
