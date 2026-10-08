// XIOM PULSE -- JSON body schema validation (typed field rules).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Small rule-list validator over xiom.serialize.json: each rule pins a
// field name, JSON type, required-ness, and (for strings/numbers) bounds.
// Unknown extra fields are allowed; callers decide how to map
// SchemaResult.code/message (routes use 400 invalid_request).
module xiom.pulse.schema

use xiom.serialize.json;
use xiom.convert;

/// SchemaRule -- one field rule. `kind` is a json_type() string:
/// "string" | "number" | "bool" | "object" | "array". `min_val`/`max_val`
/// are character bounds for strings and numeric bounds for numbers
/// (max_val <= 0 means "no upper bound").
pub type SchemaRule = {
  name: Str;
  kind: Str;
  required: Bool;
  min_val: Int;
  max_val: Int;
}

/// SchemaResult -- ok, or the first failing field with a code and message.
/// Codes: "invalid_json" | "not_object" | "missing" | "type" | "min" | "max".
pub type SchemaResult = {
  ok: Bool;
  field: Str;
  code: Str;
  message: Str;
}

fn mk_rule(name: Str, kind: Str, required: Bool, min_val: Int, max_val: Int) -> SchemaRule {
  return SchemaRule{ name: name; kind: kind; required: required; min_val: min_val; max_val: max_val; };
}

fn bad(field: Str, code: Str, message: Str) -> SchemaResult {
  return SchemaResult{ ok: false; field: field; code: code; message: message; };
}

/// schema_rules_new returns an empty rule list.
/// Complexity: O(1). Pure.
pub fn schema_rules_new() -> Vec[SchemaRule] {
  return Vec[SchemaRule].new();
}

/// schema_string adds a string rule with length bounds (min_len chars,
/// max_len chars; max_len <= 0 = unbounded).
/// Complexity: O(1).
pub fn schema_string(rules: &mut Vec[SchemaRule], name: Str, required: Bool, min_len: Int, max_len: Int) {
  rules.push(mk_rule(name, "string", required, min_len, max_len));
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
/// failure (or ok). Complexity: O(body + rules). Pure.
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
        if s.len() < ru.min_val {
          return bad(ru.name, "min", "field '" + ru.name + "' must be at least " + ru.min_val.to_str() + " chars");
        }
        if ru.max_val > 0 && s.len() > ru.max_val {
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
