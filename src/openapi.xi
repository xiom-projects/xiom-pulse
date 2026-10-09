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
use xiom.pulse.config;

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
