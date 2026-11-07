// XIOM PULSE -- JSON body schema validation (typed field rules).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Small rule-list validator over xiom.serialize.json: each rule pins a
// field name, JSON type, required-ness, and (for strings/numbers) bounds.
//
// Extra-field policy: unknown object fields are accepted by default. This
// is the documented forward-compatible contract: adding optional fields to
// a payload never breaks an older validator. Callers that need a closed
// object must enumerate every accepted field and reject surprises in their
// own handler; schema_validate intentionally has no strict/deny mode.
//
// String length policy: schema_string() keeps the historical UTF-8 BYTE
// length (backward compatible). schema_string_utf8() opts into Unicode
// CODEPOINT length; both are exposed through schema_string_units(). The
// min/max values always use the selected unit.
//
// Callers decide how to map SchemaResult.code/message (routes use 400
// invalid_request).
module xiom.pulse.schema

use xiom.serialize.json;
use xiom.convert;

// Length units for SchemaRule.length_unit.
const LENGTH_BYTES: Int = 0;
const LENGTH_CODEPOINTS: Int = 1;

/// SchemaRule -- one field rule. `kind` is a json_type() string:
/// "string" | "number" | "bool" | "object" | "array". `min_val`/`max_val`
/// are length bounds for strings (in `length_unit`) and numeric bounds for
/// numbers (max_val <= 0 means "no upper bound"). `enum_values` is empty
/// unless the field is a string enum.
pub type SchemaRule = {
  name: Str;
  kind: Str;
  required: Bool;
  min_val: Int;
  max_val: Int;
  enum_values: Vec[Str];
  length_unit: Int;
}

/// SchemaResult -- ok, or the first failing field with a code and message.
/// Codes: "invalid_json" | "not_object" | "missing" | "type" | "min" |
/// "max" | "enum".
pub type SchemaResult = {
  ok: Bool;
  field: Str;
  code: Str;
  message: Str;
}

fn mk_rule_units(name: Str, kind: Str, required: Bool, min_val: Int, max_val: Int, unit: Int) -> SchemaRule {
  return SchemaRule{ name: name; kind: kind; required: required; min_val: min_val; max_val: max_val; enum_values: Vec[Str].new(); length_unit: unit; };
}

fn mk_rule(name: Str, kind: Str, required: Bool, min_val: Int, max_val: Int) -> SchemaRule {
  return mk_rule_units(name, kind, required, min_val, max_val, LENGTH_BYTES);
}

fn bad(field: Str, code: Str, message: Str) -> SchemaResult {
  return SchemaResult{ ok: false; field: field; code: code; message: message; };
}

fn enum_contains(values: &Vec[Str], s: Str) -> Bool {
  var i: Int = 0;
  while i < values.len() {
    if values[i] == s { return true; }
    i = i + 1;
  }
  return false;
}

fn enum_list(values: &Vec[Str]) -> Str {
  var out: Str = "";
  var i: Int = 0;
  while i < values.len() {
    if i > 0 { out = out + ", "; }
    out = out + values[i];
    i = i + 1;
  }
  return out;
}

// str_length returns the selected length unit: bytes (default) or UTF-8
// codepoints (counts every non-continuation byte). O(n). Pure.
fn str_length(s: Str, unit: Int) -> Int {
  if unit != LENGTH_CODEPOINTS {
    return s.len();
  }
  var n: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let c = s.byte_at(i) as Int;
    if (c & 0xC0) != 0x80 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// schema_rules_new returns an empty rule list.
/// Complexity: O(1). Pure.
pub fn schema_rules_new() -> Vec[SchemaRule] {
  return Vec[SchemaRule].new();
}

/// schema_length_unit_bytes returns the default byte-length unit.
/// Complexity: O(1). Pure.
pub fn schema_length_unit_bytes() -> Int {
  return LENGTH_BYTES;
}

/// schema_length_unit_codepoints returns the UTF-8 codepoint-length unit.
/// Complexity: O(1). Pure.
pub fn schema_length_unit_codepoints() -> Int {
  return LENGTH_CODEPOINTS;
}

/// schema_string adds a string rule with UTF-8 BYTE length bounds (the
/// historical behavior; min_len bytes, max_len bytes; max_len <= 0 =
/// unbounded). Use schema_string_utf8 for codepoint bounds.
/// Complexity: O(1).
pub fn schema_string(rules: &mut Vec[SchemaRule], name: Str, required: Bool, min_len: Int, max_len: Int) {
  rules.push(mk_rule(name, "string", required, min_len, max_len));
}

/// schema_string_units adds a string rule with an explicit length policy
/// (LENGTH_BYTES or LENGTH_CODEPOINTS; unknown units fall back to bytes).
/// Complexity: O(1).
pub fn schema_string_units(rules: &mut Vec[SchemaRule], name: Str, required: Bool, min_len: Int, max_len: Int, unit: Int) {
  var u: Int = LENGTH_BYTES;
  if unit == LENGTH_CODEPOINTS {
    u = LENGTH_CODEPOINTS;
  }
  rules.push(mk_rule_units(name, "string", required, min_len, max_len, u));
}

/// schema_string_utf8 adds a string rule whose bounds count UTF-8
/// codepoints instead of bytes.
/// Complexity: O(1).
pub fn schema_string_utf8(rules: &mut Vec[SchemaRule], name: Str, required: Bool, min_len: Int, max_len: Int) {
  schema_string_units(rules, name, required, min_len, max_len, LENGTH_CODEPOINTS);
}

/// schema_enum adds a string rule restricted to `values` (exact,
/// case-sensitive membership). The failure code is "enum".
/// Complexity: O(values).
pub fn schema_enum(rules: &mut Vec[SchemaRule], name: Str, required: Bool, values: &Vec[Str]) {
  var r = mk_rule(name, "string", required, 0, 0);
  var i: Int = 0;
  while i < values.len() {
    r.enum_values.push(values[i]);
    i = i + 1;
  }
  rules.push(r);
}

/// schema_number adds a number rule with integer bounds.
/// Complexity: O(1).
pub fn schema_number(rules: &mut Vec[SchemaRule], name: Str, required: Bool, min_val: Int, max_val: Int) {
  rules.push(mk_rule(name, "number", required, min_val, max_val));
}

/// schema_bool adds a boolean rule.
/// Complexity: O(1).
pub fn schema_bool(rules: &mut Vec[SchemaRule], name: Str, required: Bool) {
  rules.push(mk_rule(name, "bool", required, 0, 0));
}

/// schema_object adds an object rule.
/// Complexity: O(1).
pub fn schema_object(rules: &mut Vec[SchemaRule], name: Str, required: Bool) {
  rules.push(mk_rule(name, "object", required, 0, 0));
}

/// schema_array adds an array rule.
/// Complexity: O(1).
pub fn schema_array(rules: &mut Vec[SchemaRule], name: Str, required: Bool) {
  rules.push(mk_rule(name, "array", required, 0, 0));
}

/// schema_validate checks `body` against the rules and returns the first
/// failure (or ok). Unknown fields are ignored by the extra-field policy
/// documented in the module header. Complexity: O(body + rules). Pure.
pub fn schema_validate(rules: &Vec[SchemaRule], body: Str) -> SchemaResult {
  let pv = json.json_parse(body);
  if pv.is_err {
    return bad("", "invalid_json", "body is not valid JSON");
  }
  let obj = pv.value;
  if json.json_type(obj) != "object" {
    return bad("", "not_object", "body must be a JSON object");
  }
  var i: Int = 0;
  while i < rules.len() {
    let ru = rules[i];
    let opt = json.json_get(obj, ru.name);
    if opt.is_none {
      if ru.required {
        return bad(ru.name, "missing", "missing required field '" + ru.name + "'");
      }
    } else {
      let v = opt.value;
      if json.json_type(v) != ru.kind {
        return bad(ru.name, "type", "field '" + ru.name + "' must be a " + ru.kind);
      }
      if ru.kind == "string" {
        var s: Str = "";
        match v {
          JsonValue.String(x) => { s = x; },
          _ => { return bad(ru.name, "type", "field '" + ru.name + "' must be a string"); },
        }
        if ru.enum_values.len() > 0 && !enum_contains(&ru.enum_values, s) {
          return bad(ru.name, "enum", "field '" + ru.name + "' must be one of: " + enum_list(&ru.enum_values));
        }
        let n = str_length(s, ru.length_unit);
        if n < ru.min_val {
          return bad(ru.name, "min", "field '" + ru.name + "' must be at least " + ru.min_val.to_str() + " chars");
        }
        if ru.max_val > 0 && n > ru.max_val {
          return bad(ru.name, "max", "field '" + ru.name + "' must be at most " + ru.max_val.to_str() + " chars");
        }
      } else if ru.kind == "number" {
        match v {
          JsonValue.Number(f) => {
            let iv = convert.float_to_int(f);
            if iv < ru.min_val {
              return bad(ru.name, "min", "field '" + ru.name + "' must be >= " + ru.min_val.to_str());
            }
            if ru.max_val > 0 && iv > ru.max_val {
              return bad(ru.name, "max", "field '" + ru.name + "' must be <= " + ru.max_val.to_str());
            }
          },
          _ => { return bad(ru.name, "type", "field '" + ru.name + "' must be a number"); },
        }
      }
    }
    i = i + 1;
  }
  return SchemaResult{ ok: true; field: ""; code: ""; message: "" };
}

/// schema_str_value extracts a string field value ("" when absent or of
/// another type). Call schema_validate first for typed errors.
/// Complexity: O(body). Pure.
pub fn schema_str_value(body: Str, name: Str) -> Str {
  let pv = json.json_parse(body);
  if pv.is_err { return ""; }
  let opt = json.json_get(pv.value, name);
  if opt.is_none { return ""; }
  var s: Str = "";
  match opt.value {
    JsonValue.String(x) => { s = x; },
    _ => { return ""; },
  }
  return s;
}
