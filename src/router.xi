// XIOM PULSE -- HTTP route matching (exact + one path parameter).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Static route table, no function pointers (pin-safe). Route ids:
//   1 GET  /health            6 POST /api/session/logout
//   2 GET  /api/version       7 POST /api/token
//   3 POST /api/echo          8 POST /api/token/verify
//   4 POST /api/session/login 9 GET  /metrics
//   5 GET  /api/me           10 GET  /api/items/:id
module xiom.pulse.router

use xiom.string;

/// RouteMatch - outcome of matching method+target against the table:
/// kind 0 = not found, 1 = matched, 2 = method not allowed (allow holds
/// the allowed-methods string for the 405 Allow header).
pub type RouteMatch = {
  kind: Int;
  route_id: Int;
  allow: Str;
  param_names: Vec[Str];
  param_values: Vec[Str];
}

const ITEMS_PREFIX: Str = "/api/items/";

/// route_id_of returns the static route id for a path, or 0.
/// Complexity: O(routes). Pure.
pub fn route_id_of(path: Str) -> Int {
  if path == "/health" { return 1; }
  if path == "/api/version" { return 2; }
  if path == "/api/echo" { return 3; }
  if path == "/api/session/login" { return 4; }
  if path == "/api/me" { return 5; }
  if path == "/api/session/logout" { return 6; }
  if path == "/api/token" { return 7; }
  if path == "/api/token/verify" { return 8; }
  if path == "/metrics" { return 9; }
  if string.str_starts_with(path, ITEMS_PREFIX) && path.len() > ITEMS_PREFIX.len() {
    return 10;
  }
  return 0;
}

/// allowed_methods_of returns the allowed methods for a known path, or "".
/// Complexity: O(routes). Pure.
pub fn allowed_methods_of(path: Str) -> Str {
  let id = route_id_of(path);
  if id == 1 { return "GET"; }
  if id == 2 { return "GET"; }
  if id == 3 { return "POST"; }
  if id == 4 { return "POST"; }
  if id == 5 { return "GET"; }
  if id == 6 { return "POST"; }
  if id == 7 { return "POST"; }
  if id == 8 { return "POST"; }
  if id == 9 { return "GET"; }
  if id == 10 { return "GET"; }
  return "";
}

/// route_match dispatches (method, target) to the table.
/// Complexity: O(routes). Pure.
pub fn route_match(method: Str, target: Str) -> RouteMatch {
  var m: RouteMatch = RouteMatch{
    kind: 0;
    route_id: 0;
    allow: "";
    param_names: Vec[Str].new();
    param_values: Vec[Str].new();
  };
  let id = route_id_of(target);
  if id == 0 {
    return m;
  }
  let allowed = allowed_methods_of(target);
  if allowed != method {
    m.kind = 2;
    m.route_id = id;
    m.allow = allowed;
    return m;
  }
  m.kind = 1;
  m.route_id = id;
  if id == 10 {
    m.param_names.push("id");
    m.param_values.push(string.str_slice(target, ITEMS_PREFIX.len(), target.len()));
  }
  return m;
}
