// XIOM PULSE -- global request rate limiting (consumer of xiom.rate 0.2.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Single global token bucket because per-client keys need the peer address
// (`socket_peer_addr` is still a stdlib stub). Disabled by default; enable
// with PULSE_RATE_LIMIT=<req/s> (+ optional PULSE_RATE_BURST).
//
// The limiter is a VALUE the caller owns (main/tests), never a module-level
// package struct: module-scope initialization of cross-package aggregates
// crashes on v0.64.0 (same class as C-PULSE-06).
module xiom.pulse.ratelimit

use xiom.string;
use xiom.convert.parse;
use xiom.rate;

/// Limiter - PULSE's global token bucket wrapper.
pub type Limiter = {
  enabled: Bool;
  bucket: KeyedBuckets;
  per_sec: Int;
}

/// limiter_new builds a limiter; per_sec <= 0 returns a disabled one.
/// Complexity: O(1).
pub fn limiter_new(per_sec: Int, burst: Int) -> Limiter {
  if per_sec <= 0 {
    return Limiter{ enabled: false; bucket: rate.rate_keyed_new(1, 1); per_sec: 0; };
  }
  var cap: Int = burst;
  if cap <= 0 { cap = per_sec; }
  return Limiter{ enabled: true; bucket: rate.rate_keyed_new(cap, per_sec); per_sec: per_sec; };
}

/// limiter_allow consumes one token for the global key.
/// Complexity: O(1) amortized.
pub fn limiter_allow(l: &mut Limiter, now_ms: Int) -> Bool {
  if !l.enabled { return true; }
  return rate.rate_keyed_allow(&mut l.bucket, "global", now_ms);
}

/// bucket_step is the Phase B HookCtx adapter: a stateless token-bucket
/// step over four int handles (tokens, last_ms) so the rate limiter can
/// live in the hook seam's int bag. Returns (allowed, new_tokens,
/// new_last_ms); per_sec <= 0 always allows. Same refill/cap semantics as
/// limiter_allow, without a captured aggregate. Complexity: O(1).
pub fn bucket_step(tokens: Int, last_ms: Int, per_sec: Int, burst: Int, now_ms: Int) -> (Bool, Int, Int) {
  if per_sec <= 0 { return (true, tokens, last_ms); }
  var cap: Int = burst;
  if cap < 1 { cap = per_sec; }
  var t: Int = tokens;
  var last: Int = last_ms;
  if last <= 0 {
    last = now_ms;
    t = cap;
  }
  let elapsed = now_ms - last;
  if elapsed > 0 {
    let refill = (elapsed * per_sec) / 1000;
    if refill > 0 {
      t = t + refill;
      if t > cap { t = cap; }
      last = now_ms;
    }
  }
  if t <= 0 { return (false, t, last); }
  return (true, t - 1, last);
}

/// limiter_retry_after_ms returns ms until the next token (0 when disabled).
/// Complexity: O(1).
pub fn limiter_retry_after_ms(l: &Limiter, now_ms: Int) -> Int {
  if !l.enabled { return 0; }
  return rate.rate_keyed_retry_after_ms(&l.bucket, "global", 1, now_ms);
}

// --- per-route policy -------------------------------------------------------
//
// Policy spec: `METHOD PATH=RATE[/BURST]` entries separated by commas.
// METHOD may be `*`; PATH is a route template from router.route_defs()
// (e.g. `/api/events`, `/api/items/:id`), not a raw request path. The
// global bucket runs first; this table is additive (a route can be tighter
// than the global cap, never looser).
//
// State is deliberately scalar Vec state (no cross-package aggregate at
// module scope, the v0.64.0 crash class); buckets use the same stateless
// `bucket_step` math as the Phase B HookCtx adapter.

/// RouteRates - one token bucket per configured policy.
pub type RouteRates = {
  enabled: Bool;
  methods: Vec[Str];
  patterns: Vec[Str];
  per_sec: Vec[Int];
  burst: Vec[Int];
  tokens: Vec[Int];
  last_ms: Vec[Int];
  errors: Vec[Str];
}

fn method_ok(m: Str) -> Bool {
  if m == "*" { return true; }
  if m == "GET" { return true; }
  if m == "HEAD" { return true; }
  if m == "POST" { return true; }
  if m == "PUT" { return true; }
  if m == "PATCH" { return true; }
  if m == "DELETE" { return true; }
  if m == "OPTIONS" { return true; }
  return false;
}

fn split_once(s: Str, delim: Str) -> (Str, Str) {
  let idx = string.str_index_of(s, delim);
  if idx.is_none { return (s, ""); }
  return (string.str_slice(s, 0, idx.value), string.str_slice(s, idx.value + delim.len(), s.len()));
}

fn parse_positive(s: Str) -> Int {
  let p = parse.parse_int(s);
  if !p.is_ok { return -1; }
  if p.value <= 0 { return -1; }
  return p.value;
}

fn replace_int(v: &Vec[Int], idx: Int, val: Int) -> Vec[Int] {
  var out: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  while i < v.len() {
    if i == idx { out.push(val); } else { out.push(v[i]); }
    i = i + 1;
  }
  return out;
}

fn has_policy(r: &RouteRates, method: Str, pattern: Str) -> Bool {
  var i: Int = 0;
  while i < r.patterns.len() {
    if r.methods[i] == method && r.patterns[i] == pattern { return true; }
    i = i + 1;
  }
  return false;
}

fn add_policy(r: &mut RouteRates, entry: Str) {
  let eq = split_once(entry, "=");
  if eq.1.len() == 0 {
    r.errors.push("missing '=' in \"" + entry + "\"");
    return;
  }
  let left = string.str_trim(eq.0);
  let right = string.str_trim(eq.1);
  let sp = split_once(left, " ");
  let method = string.str_upper(string.str_trim(sp.0));
  let pattern = string.str_trim(sp.1);
  if pattern.len() == 0 {
    r.errors.push("expected METHOD PATH=RATE in \"" + entry + "\"");
    return;
  }
  if !method_ok(method) {
    r.errors.push("unknown method \"" + sp.0 + "\" in \"" + entry + "\"");
    return;
  }
  if !string.str_starts_with(pattern, "/") {
    r.errors.push("path must start with '/' in \"" + entry + "\"");
    return;
  }
  let rb = split_once(right, "/");
  let per_sec = parse_positive(string.str_trim(rb.0));
  if per_sec <= 0 {
    r.errors.push("rate must be a positive integer in \"" + entry + "\"");
    return;
  }
  var burst = per_sec;
  if rb.1.len() > 0 {
    burst = parse_positive(string.str_trim(rb.1));
    if burst <= 0 {
      r.errors.push("burst must be a positive integer in \"" + entry + "\"");
      return;
    }
  }
  if has_policy(r, method, pattern) {
    r.errors.push("duplicate policy for " + method + " " + pattern);
    return;
  }
  r.methods.push(method);
  r.patterns.push(pattern);
  r.per_sec.push(per_sec);
  r.burst.push(burst);
  r.tokens.push(burst);
  r.last_ms.push(0);
}

/// route_rates_new parses the policy spec. Invalid entries are skipped and
/// named in `errors` (surfaced by cfg_validate/--check-config/startup).
/// Complexity: O(entries).
pub fn route_rates_new(spec: Str) -> RouteRates {
  var r: RouteRates = RouteRates{
    enabled: false;
    methods: Vec[Str].new();
    patterns: Vec[Str].new();
    per_sec: Vec[Int].new();
    burst: Vec[Int].new();
    tokens: Vec[Int].new();
    last_ms: Vec[Int].new();
    errors: Vec[Str].new();
  };
  if spec.len() == 0 { return r; }
  let entries = string.str_split(spec, ",");
  var i: Int = 0;
  while i < entries.len() {
    let e = string.str_trim(entries[i]);
    if e.len() > 0 { add_policy(&mut r, e); }
    i = i + 1;
  }
  if r.patterns.len() > 0 { r.enabled = true; }
  return r;
}

/// route_rates_enabled reports whether at least one valid policy parsed.
pub fn route_rates_enabled(r: &RouteRates) -> Bool {
  return r.enabled;
}

/// route_rates_summary is the one-line startup/--check-config label.
pub fn route_rates_summary(r: &RouteRates) -> Str {
  if !r.enabled {
    if r.errors.len() > 0 { return "off (" + r.errors.len().to_str() + " invalid)"; }
    return "off";
  }
  return r.patterns.len().to_str() + " policies";
}

/// route_rates_errors joins parse errors ("" when the spec is clean).
pub fn route_rates_errors(r: &RouteRates) -> Str {
  var out: Str = "";
  var i: Int = 0;
  while i < r.errors.len() {
    if out.len() > 0 { out = out + "; "; }
    out = out + r.errors[i];
    i = i + 1;
  }
  return out;
}

/// route_rates_spec_error validates a spec without keeping state (used by
/// config validation). Complexity: O(entries).
pub fn route_rates_spec_error(spec: Str) -> Str {
  let r = route_rates_new(spec);
  return route_rates_errors(&r);
}

fn policy_index(r: &RouteRates, method: Str, pattern: Str) -> Int {
  var i: Int = 0;
  while i < r.patterns.len() {
    if r.methods[i] == method && r.patterns[i] == pattern { return i; }
    i = i + 1;
  }
  i = 0;
  while i < r.patterns.len() {
    if r.methods[i] == "*" && r.patterns[i] == pattern { return i; }
    i = i + 1;
  }
  return -1;
}

/// route_rates_allow consumes a per-route token (true when no policy
/// matches). Complexity: O(policies) + O(1).
pub fn route_rates_allow(r: &mut RouteRates, method: Str, pattern: Str, now_ms: Int) -> Bool {
  if !r.enabled { return true; }
  let idx = policy_index(r, method, pattern);
  if idx < 0 { return true; }
  let b = bucket_step(r.tokens[idx], r.last_ms[idx], r.per_sec[idx], r.burst[idx], now_ms);
  r.tokens = replace_int(&r.tokens, idx, b.1);
  r.last_ms = replace_int(&r.last_ms, idx, b.2);
  return b.0;
}

/// route_rates_retry_after_ms is the Retry-After hint for the matched
/// policy (0 when none matches). Conservative: one refill interval.
pub fn route_rates_retry_after_ms(r: &RouteRates, method: Str, pattern: Str) -> Int {
  let idx = policy_index(r, method, pattern);
  if idx < 0 { return 0; }
  let per = r.per_sec[idx];
  if per <= 0 { return 0; }
  let ms = 1000 / per;
  if ms < 1 { return 1; }
  return ms;
}
