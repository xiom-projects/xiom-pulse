// XIOM PULSE -- app route table, consumed from the registry xiom.router 0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Matching semantics (pattern shapes, :param capture, registration-order
// first match, 404/405 + allowed-methods) are the registry package's job.
// This module owns the app's route-id mapping, query-string splitting and
// percent-decoding, and the PULSE-shaped outcome.
//
// Route ids: 1 GET /health, 2 GET /api/version, 3 POST /api/echo,
// 4 POST /api/session/login, 5 GET /api/me, 6 POST /api/session/logout,
// 7 POST /api/token, 8 POST /api/token/verify, 9 GET /metrics,
// 10 GET /api/items/:id, 11 POST /api/events, 12 GET /api/events/count,
// 13 GET /api/events, 14 GET /favicon.ico, 15 GET /, 16 POST /api/events/compact,
// 17 GET /openapi.json. Every route is also reachable through the `/v1`
// alias prefix (v1_path strips it before matching); new surfaces are
// introduced under `/v1` first.
module xiom.pulse.router

use xiom.string;
use xiom.router;

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

fn hex_val(b: UInt8) -> Int {
  if b >= 48u8 && b <= 57u8 { return (b as Int) - 48; }
  if b >= 65u8 && b <= 70u8 { return (b as Int) - 55; }
  if b >= 97u8 && b <= 102u8 { return (b as Int) - 87; }
  return -1;
}

/// url_decode decodes %XX and '+' in a query component. Pure.
pub fn url_decode(s: Str) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b == 37u8 && i + 2 < s.len() {
      let h1 = hex_val(s.byte_at(i + 1));
      let h2 = hex_val(s.byte_at(i + 2));
      if h1 >= 0 && h2 >= 0 {
        out.push(((h1 * 16 + h2) as UInt8));
        i = i + 3;
      } else {
        out.push(b);
        i = i + 1;
      }
    } else if b == 43u8 {
      out.push(32u8);
      i = i + 1;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Str::from_utf8(out);
}

/// parse_query parses "a=1&b=x%20y&c" into name/value lists (decoded). Pure.
pub fn parse_query(qs: Str) -> (Vec[Str], Vec[Str]) {
  var names: Vec[Str] = Vec[Str].new();
  var values: Vec[Str] = Vec[Str].new();
  if qs.len() == 0 {
    return (names, values);
  }
  let pairs = string.str_split(qs, "&");
  var i: Int = 0;
  while i < pairs.len() {
    let p = pairs[i];
    if p.len() > 0 {
      let eo = string.str_index_of(p, "=");
      if eo.is_none {
        names.push(url_decode(p));
        values.push("");
      } else {
        let e = eo.value;
        names.push(url_decode(string.str_slice(p, 0, e)));
        values.push(url_decode(string.str_slice(p, e + 1, p.len())));
      }
    }
    i = i + 1;
  }
  return (names, values);
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

/// routes_list returns the app route table as (method, path) pairs in
/// registration order (the `routes` CLI and the openapi contract test use
/// it). Complexity: O(1).
pub fn routes_list() -> Vec[(Str, Str)] {
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
  return out;
}

/// route_match builds the app table, matches (method, target) via the
/// registry router and maps the registration index to the app route id.
/// The table is rebuilt per call (16 registrations; negligible at current
/// load and avoids module-global mutable struct state).
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
  var ids: Vec[Int] = Vec[Int].new();
  let _r1 = router.router_add(&mut t, "GET", "/health");            ids.push(1);
  let _r2 = router.router_add(&mut t, "GET", "/api/version");       ids.push(2);
  let _r3 = router.router_add(&mut t, "POST", "/api/echo");         ids.push(3);
  let _r4 = router.router_add(&mut t, "POST", "/api/session/login"); ids.push(4);
  let _r5 = router.router_add(&mut t, "GET", "/api/me");            ids.push(5);
  let _r6 = router.router_add(&mut t, "POST", "/api/session/logout"); ids.push(6);
  let _r7 = router.router_add(&mut t, "POST", "/api/token");        ids.push(7);
  let _r8 = router.router_add(&mut t, "POST", "/api/token/verify"); ids.push(8);
  let _r9 = router.router_add(&mut t, "GET", "/metrics");           ids.push(9);
  let _r10 = router.router_add(&mut t, "GET", "/api/items/:id");    ids.push(10);
  let _r11 = router.router_add(&mut t, "POST", "/api/events");      ids.push(11);
  let _r12 = router.router_add(&mut t, "GET", "/api/events/count"); ids.push(12);
  let _r13 = router.router_add(&mut t, "GET", "/api/events");       ids.push(13);
  let _r14 = router.router_add(&mut t, "GET", "/favicon.ico");      ids.push(14);
  let _r15 = router.router_add(&mut t, "GET", "/");                 ids.push(15);
  let _r16 = router.router_add(&mut t, "POST", "/api/events/compact"); ids.push(16);
  let _r17 = router.router_add(&mut t, "GET", "/openapi.json");    ids.push(17);

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
  if rm.index >= 0 && rm.index < ids.len() {
    m.route_id = ids[rm.index];
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
