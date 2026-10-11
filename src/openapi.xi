// XIOM PULSE -- served OpenAPI contract (GET /openapi.json, `openapi` CLI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The document lives in the repo (PULSE_OPENAPI_PATH, default
// resources/openapi.json) so it is reviewable in diffs; the wire copy has
// the "__PULSE_VERSION__" token replaced with the running build version,
// which keeps the contract and /api/version in lockstep with no duplicate
// literals to bump. Read failures surface as "" (the route answers 500).
module xiom.pulse.openapi

use xiom.io;
use xiom.string;
use xiom.serialize.json;
use xiom.pulse.config;
use xiom.pulse.router;

// _replace_first returns s with the first occurrence of `from` replaced by
// `to` (token substitution for the version placeholder). O(n).
fn _replace_first(s: Str, from: Str, to: Str) -> Str {
  let o = string.str_index_of(s, from);
  if o.is_none {
    return s;
  }
  let i = o.value;
  return string.str_slice(s, 0, i) + to + string.str_slice(s, i + from.len(), s.len());
}

/// openapi_document returns the served OpenAPI document with the version
/// token substituted, or "" when the resource cannot be read.
/// Complexity: O(size).
pub fn openapi_document(version: Str) -> Str {
  let r = io.read_file(config.cfg_openapi_path());
  if r.is_err {
    return "";
  }
  return _replace_first(r.value, "__PULSE_VERSION__", version);
}

/// openapi_template converts a router pattern (":param" segments) to the
/// OpenAPI path template ("{param}"). Complexity: O(n). Pure.
pub fn openapi_template(pattern: Str) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < pattern.len() {
    let b = pattern.byte_at(i);
    if b == 58u8 {
      // ':' starts a param segment: rewrite up to the next '/' as {name}.
      out.push(123u8);
      i = i + 1;
      while i < pattern.len() && pattern.byte_at(i) != 47u8 {
        out.push(pattern.byte_at(i));
        i = i + 1;
      }
      out.push(125u8);
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Str::from_utf8(out);
}

/// openapi_missing_routes reports route-table entries absent from `doc`:
/// for every (method, pattern) in router.route_defs() the parsed document
/// must carry the templated path key and the lowercase method verb under
/// it. One-way guard: a route-table addition/removal that never reaches
/// the contract fails the suite. Returns "METHOD /path" for missing
/// entries (and a marker when the document does not parse).
/// Complexity: O(routes * doc).
pub fn openapi_missing_routes(doc: Str) -> Vec[Str] {
  var missing: Vec[Str] = Vec[Str].new();
  let pv = json.json_parse(doc);
  if pv.is_err {
    missing.push("<document does not parse>");
    return missing;
  }
  let paths_o = json.json_get(pv.value, "paths");
  if paths_o.is_none {
    missing.push("<paths object missing>");
    return missing;
  }
  let paths = paths_o.value;
  let defs = router.route_defs();
  var i: Int = 0;
  while i < defs.len() {
    let d = defs[i];
    let tmpl = openapi_template(d.1);
    let po = json.json_get(paths, tmpl);
    if po.is_none {
      missing.push(d.0 + " " + tmpl);
    } else {
      let mo = json.json_get(po.value, string.str_lower(d.0));
      if mo.is_none { missing.push(d.0 + " " + tmpl + " (verb)"); }
    }
    i = i + 1;
  }
  return missing;
}
