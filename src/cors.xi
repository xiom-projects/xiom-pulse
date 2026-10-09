// XIOM PULSE -- CORS response headers (opt-in via PULSE_CORS_ORIGIN).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Off by default ("" origin). `*` allows any request origin; otherwise the
// configured value is a comma-separated allowlist and the request origin
// must match one entry exactly (entries are trimmed). Header lines are
// built by registry xiom.http.middleware 0.1.0.
module xiom.pulse.cors

use xiom.string;
use xiom.pulse.config;
use xiom.http.middleware;

/// cors_enabled reports whether an allowed origin is configured.
/// Complexity: O(1). Pure.
pub fn cors_enabled() -> Bool {
  return config.cfg_cors_origin().len() > 0;
}

/// cors_list_match is true when `origin` equals one comma-separated entry
/// of `list` (entries trimmed). Complexity: O(n). Pure.
fn cors_list_match(list: Str, origin: Str) -> Bool {
  var start: Int = 0;
  var i: Int = 0;
  while i < list.len() {
    if string.str_slice(list, i, i + 1) == "," {
      if string.str_trim(string.str_slice(list, start, i)) == origin { return true; }
      start = i + 1;
    }
    i = i + 1;
  }
  if string.str_trim(string.str_slice(list, start, list.len())) == origin { return true; }
  return false;
}

/// cors_allow_origin resolves the response origin for a request `Origin`:
/// "" when CORS is off or the origin is not allowed. `*` allows any origin;
/// otherwise PULSE_CORS_ORIGIN is a comma-separated allowlist.
/// Complexity: O(n). Pure.
pub fn cors_allow_origin(req_origin: Str) -> Str {
  let allowed = config.cfg_cors_origin();
  if allowed.len() == 0 { return ""; }
  if string.str_trim(allowed) == "*" { return "*"; }
  if req_origin.len() > 0 && cors_list_match(allowed, req_origin) { return req_origin; }
  return "";
}

/// cors_header_block returns the CORS headers to inject (no trailing blank
/// line), or "" when the origin is not allowed.
/// Complexity: O(1). Pure.
pub fn cors_header_block(req_origin: Str) -> Str {
  let oc = cors_allow_origin(req_origin);
  if oc.len() == 0 { return ""; }
  let lines = middleware_cors_headers(oc, "GET, POST, PUT, DELETE, OPTIONS", "Content-Type, X-CSRF-Token", 600);
  var out: Str = "";
  var i: Int = 0;
  while i < lines.len() {
    out = out + lines[i] + "\r\n";
    i = i + 1;
  }
  return out;
}
