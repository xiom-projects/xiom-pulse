// XIOM PULSE -- app route table, consumed from the registry xiom.router 0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Matching semantics (pattern shapes, :param capture, registration-order
// first match, 404/405 + allowed-methods) are the registry package's job.
// This module owns the app's route-id mapping, query-string splitting and
// percent-decoding, and the PULSE-shaped outcome.
//
// Route ids are the 1-based index of route_defs() (the single source of
// truth for dispatch, `routes_list` and the OpenAPI drift guard):
// 1 GET /health, 2 GET /api/version, 3 POST /api/echo,
// 4 POST /api/session/login, 5 GET /api/me, 6 POST /api/session/logout,
// 7 POST /api/token, 8 POST /api/token/verify, 9 GET /metrics,
// 10 GET /api/items/:id, 11 POST /api/events, 12 GET /api/events/count,
// 13 GET /api/events, 14 GET /favicon.ico, 15 GET /, 16 POST /api/events/compact,
// 17 GET /openapi.json, 18 POST /api/uploads, 19 POST /api/game/register,
// 20 POST /api/game/heartbeat, 21 GET /api/game/config, 22 GET /api/game/compat,
// 23 POST /api/game/match-report, 24 POST /api/game/telemetry,
// 25 POST /api/game/admin/command. Every route is also reachable
// through the `/v1` alias prefix (v1_path strips it before matching); new
// surfaces are introduced under `/v1` first.
module xiom.pulse.station.router

use xiom.string;
use xiom.router;
use xiom.pulse.urlenc;

/// PulseRoute - PULSE's route outcome: kind 0 = not found, 1 = matched,
/// 2 = method not allowed (allow holds "GET, POST"). Query parameters are
/// split off the target and exposed decoded.
pub type PulseRoute = {
  kind: Int;
  route_id: Int;
  allow: Str;
  param_names: Vec[Str];
  param_values: Vec[Str];
  query_names: Vec[Str];
  query_values: Vec[Str];
}

/// split_target splits "/path?query" into (path, query). Pure.
pub fn split_target(target: Str) -> (Str, Str) {
  let qo = string.str_index_of(target, "?");
  if qo.is_none {
    return (target, "");
  }
  let q = qo.value;
  return (string.str_slice(target, 0, q), string.str_slice(target, q + 1, target.len()));
}

/// v1_path maps a versioned `/v1/<rest>` alias onto the canonical
/// `<rest>` path, query preserved: `/v1/api/events?limit=1` ->
/// `/api/events?limit=1`; `/v1` and `/v1/` map to `/`; anything else
/// passes through untouched. Complexity: O(n). Pure.
pub fn v1_path(target: Str) -> Str {
  let parts = split_target(target);
  let p = parts.0;
  let q = parts.1;
  if p == "/v1" {
    if q.len() > 0 { return "/?" + q; }
    return "/";
  }
  if string.str_starts_with(p, "/v1/") {
    let rest = string.str_slice(p, 3, p.len());
    if q.len() > 0 { return rest + "?" + q; }
    return rest;
  }
  return target;
}

/// url_decode decodes %XX and '+' in a query component. The decoder lives
/// in xiom.pulse.urlenc so query strings and form bodies share one
/// implementation. Complexity: O(n). Pure.
pub fn url_decode(s: Str) -> Str {
  return urlenc.url_decode(s);
}

/// parse_query parses "a=1&b=x%20y&c" into name/value lists (decoded).
/// Complexity: O(n). Pure.
pub fn parse_query(qs: Str) -> (Vec[Str], Vec[Str]) {
  return urlenc.parse_pairs(qs);
}

fn join_methods(ms: &Vec[Str]) -> Str {
  var out: Str = "";
  var i: Int = 0;
  while i < ms.len() {
    if i > 0 { out = out + ", "; }
    let s = ms[i];
    out = out + s;
    i = i + 1;
  }
  return out;
}

/// route_defs returns the single source of truth for the app route table:
/// (method, pattern) pairs in registration order; the app route id is the
/// 1-based index in this list. `routes_list` (CLI) and `route_match`
/// (dispatch) both derive from it, and the OpenAPI drift guard walks it.
/// Complexity: O(1).
pub fn route_defs() -> Vec[(Str, Str)] {
  var out: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  out.push(("GET", "/health"));
  out.push(("GET", "/api/version"));
  out.push(("POST", "/api/echo"));
  out.push(("POST", "/api/session/login"));
  out.push(("GET", "/api/me"));
  out.push(("POST", "/api/session/logout"));
  out.push(("POST", "/api/token"));
  out.push(("POST", "/api/token/verify"));
  out.push(("GET", "/metrics"));
  out.push(("GET", "/api/items/:id"));
  out.push(("POST", "/api/events"));
  out.push(("GET", "/api/events/count"));
  out.push(("GET", "/api/events"));
  out.push(("GET", "/favicon.ico"));
  out.push(("GET", "/"));
  out.push(("POST", "/api/events/compact"));
  out.push(("GET", "/openapi.json"));
  out.push(("POST", "/api/uploads"));
  out.push(("POST", "/api/game/register"));
  out.push(("POST", "/api/game/heartbeat"));
  out.push(("GET", "/api/game/config"));
  out.push(("GET", "/api/game/compat"));
  out.push(("POST", "/api/game/match-report"));
  out.push(("POST", "/api/game/telemetry"));
  out.push(("POST", "/api/game/admin/command"));
  return out;
}

/// routes_list returns the app route table as (method, path) pairs in
/// registration order (the `routes` CLI and the openapi contract test use
/// it). Complexity: O(1).
pub fn routes_list() -> Vec[(Str, Str)] {
  return route_defs();
}

/// route_match builds the app table from route_defs(), matches
/// (method, target) via the registry router and maps the registration
/// index to the app route id (index + 1). The table is rebuilt per call
/// (negligible at current load and avoids module-global mutable state).
/// Complexity: O(routes).
pub fn route_match(method: Str, target: Str) -> PulseRoute {
  var m: PulseRoute = PulseRoute{
    kind: 0;
    route_id: 0;
    allow: "";
    param_names: Vec[Str].new();
    param_values: Vec[Str].new();
    query_names: Vec[Str].new();
    query_values: Vec[Str].new();
  };
  let parts = split_target(target);
  let path = parts.0;
  let qp = parse_query(parts.1);
  m.query_names = qp.0;
  m.query_values = qp.1;

  var t = router.router_new();
  let defs = route_defs();
  var di: Int = 0;
  while di < defs.len() {
    let d = defs[di];
    let _r = router.router_add(&mut t, d.0, d.1);
    di = di + 1;
  }

  let rm = router.router_match(&t, method, path);
  if rm.code == 404 {
    return m;
  }
  if rm.code == 405 {
    m.kind = 2;
    let allowed = router.router_allowed_methods(&t, path);
    m.allow = join_methods(&allowed);
    return m;
  }
  m.kind = 1;
  if rm.index >= 0 && rm.index < defs.len() {
    m.route_id = rm.index + 1;
  }
  var i: Int = 0;
  while i < rm.params.len() {
    let p = rm.params[i];
    m.param_names.push(p.name);
    m.param_values.push(p.value);
    i = i + 1;
  }
  return m;
}
