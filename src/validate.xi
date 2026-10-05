// XIOM PULSE -- minimal JSON body field validation.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Extracts required string fields with a length cap; "" means
// missing/wrong-type/too-long, which callers map to 400 invalid_request.
module xiom.pulse.validate

use xiom.serialize.json;

/// field_str returns the string value of `key` when present, of type
/// string, and at most `max_len` characters; otherwise "".
/// Complexity: O(body). Pure.
pub fn field_str(body: Str, key: Str, max_len: Int) -> Str {
  let pv = json.json_parse(body);
  if pv.is_err { return ""; }
  let opt = json.json_get(pv.value, key);
  if opt.is_none { return ""; }
  let v = opt.value;
  if json.json_type(v) != "string" { return ""; }
  var s: Str = "";
  match v {
    JsonValue.String(x) => { s = x; },
    _ => { return ""; },
  }
  if s.len() > max_len { return ""; }
  return s;
}

/// is_json_object reports whether `body` parses as a JSON object.
/// Complexity: O(body). Pure.
pub fn is_json_object(body: Str) -> Bool {
  let pv = json.json_parse(body);
  if pv.is_err { return false; }
  return json.json_type(pv.value) == "object";
}
