// XIOM PULSE -- CORS response headers (opt-in via PULSE_CORS_ORIGIN).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Off by default ("" origin). `*` allows any request origin; otherwise the
// configured origin must match the request exactly.
module xiom.pulse.cors

use xiom.pulse.config;

/// cors_enabled reports whether an allowed origin is configured.
/// Complexity: O(1). Pure.
pub fn cors_enabled() -> Bool {
  return config.cfg_cors_origin().len() > 0;
}

/// cors_allow_origin resolves the response origin for a request `Origin`:
/// "" when CORS is off or the origin is not allowed.
/// Complexity: O(1). Pure.
pub fn cors_allow_origin(req_origin: Str) -> Str {
  let allowed = config.cfg_cors_origin();
  if allowed.len() == 0 { return ""; }
  if allowed == "*" { return "*"; }
  if req_origin.len() > 0 && req_origin == allowed { return allowed; }
  return "";
}

/// cors_header_block returns the CORS headers to inject (no trailing blank
/// line), or "" when the origin is not allowed.
/// Complexity: O(1). Pure.
pub fn cors_header_block(req_origin: Str) -> Str {
  let oc = cors_allow_origin(req_origin);
  if oc.len() == 0 { return ""; }
  return "Access-Control-Allow-Origin: " + oc + "\r\n"
    + "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n"
    + "Access-Control-Allow-Headers: Content-Type, X-CSRF-Token\r\n"
    + "Access-Control-Max-Age: 600\r\n";
}
