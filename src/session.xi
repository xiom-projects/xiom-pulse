// XIOM PULSE -- sessions bound to the `sid` cookie, backed by the registry
// xiom.session 0.1.0 store (C-PULSE-09 CLOSED on v0.64.2: the v0.64.0
// cross-module wrapper crash is fixed -- see docs/COMPILER-FINDINGS-PULSE.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Discipline: every xiom.session call stays inside THIS module (one wrapper
// per package); the store travels in a std Vec holder (C-PULSE-07: no
// module-scope package constructors). The module is named `sessions` on
// purpose -- a module whose last segment matches an import alias shadows it
// (C-PULSE-12), so `xiom.pulse.session` + `use xiom.session;` would poison
// the package alias inside this file.
//
// The package owns: 128-bit hex ids, per-session entries (the user is
// stored under the "user" key), absolute expiry on the explicit caller
// clock in milliseconds, pruning, and exact Set-Cookie rendering. PULSE
// keeps the HTTP-facing API, cookie parsing and the CSRF pieces
// (xiom.http.middleware 0.1.0).
module xiom.pulse.sessions

use xiom.string;
use xiom.time;
use xiom.session;
use xiom.cookie;
use xiom.http.middleware;

// SessionStore holder: index 0 once the store exists (Vec-holder pattern).
var s_stores: Vec[SessionStore] = Vec[SessionStore].new();

// _store returns the live store index, creating a store with the default
// 1h ttl on first use (session_init overrides it at startup).
fn _store() -> Int {
  if s_stores.len() == 0 {
    s_stores.push(session.session_store_new(3600000));
  }
  return 0;
}

// _now_ms is the caller clock for the store (absolute milliseconds).
fn _now_ms() -> Int {
  return time.unix_timestamp() * 1000;
}

/// session_init configures the store with the configured ttl (seconds).
/// Complexity: O(1).
pub fn session_init(ttl_secs: Int) {
  var ttl = ttl_secs;
  if ttl < 1 { ttl = 1; }
  s_stores = Vec[SessionStore].new();
  s_stores.push(session.session_store_new(ttl * 1000));
}

/// session_create creates a session for `user` and returns its id ("" on
/// id-generation failure). Expired sessions are pruned opportunistically;
/// the store ttl (session_init / default 1h) governs expiry.
/// Complexity: O(stored sessions).
pub fn session_create(user: Str, ttl_secs: Int) -> Str {
  let _t = ttl_secs; // the initialized store ttl governs expiry
  let si = _store();
  let now = _now_ms();
  let _pruned = session.session_prune(&mut s_stores[si], now);
  let r = session.session_create(&mut s_stores[si], now);
  if !r.is_ok { return ""; }
  let id = r.value;
  let _wrote = session.session_set(&mut s_stores[si], id, "user", user, now);
  return id;
}

/// session_get returns the user for a live session id, or "".
/// Complexity: O(stored sessions + entries).
pub fn session_get(id: Str) -> Str {
  let si = _store();
  let r = session.session_value(&s_stores[si], id, "user", _now_ms());
  if r.is_none { return ""; }
  return r.value;
}

/// session_drop removes the session id immediately (expired or not).
/// Complexity: O(stored sessions).
pub fn session_drop(id: Str) {
  let si = _store();
  let _removed = session.session_remove(&mut s_stores[si], id);
}

/// session_count returns the number of stored sessions (live + expired).
/// Complexity: O(1).
pub fn session_count() -> Int {
  let si = _store();
  return session.session_count(&s_stores[si]);
}

/// session_reset clears the store (tests).
/// Complexity: O(1).
pub fn session_reset() {
  s_stores = Vec[SessionStore].new();
}

/// session_cookie_header returns the Set-Cookie VALUE for a session
/// (header name is added by the response builder). Not `Secure`: TLS
/// terminates at the front proxy.
/// Complexity: O(n). Pure.
pub fn session_cookie_header(id: Str, ttl_secs: Int) -> Str {
  return session.session_cookie_header("sid", id, ttl_secs, false);
}

/// session_expired_cookie_header returns the clearing Set-Cookie VALUE.
/// Complexity: O(1). Pure.
pub fn session_expired_cookie_header() -> Str {
  return session.session_cookie_clear("sid");
}

/// session_id_from_cookie extracts the `sid` value from a Cookie header.
/// Complexity: O(header).
pub fn session_id_from_cookie(cookie_header: Str) -> Str {
  if cookie_header.len() == 0 { return ""; }
  let jar = cookie.cookie_parse_request(cookie_header);
  let opt = cookie.cookie_get(&jar, "sid");
  if opt.is_none { return ""; }
  let v = opt.value;
  return v;
}

/// csrf_new_token returns a fresh CSRF token (registry middleware, "" on
/// generation failure). Complexity: O(1).
pub fn csrf_new_token() -> Str {
  let r = middleware_csrf_token_new();
  if r.is_err { return ""; }
  return r.value;
}

/// csrf_cookie_header returns the Set-Cookie VALUE for the CSRF token.
/// Complexity: O(1). Pure.
pub fn csrf_cookie_header(token: Str) -> Str {
  return "csrf=" + token + "; Path=/; SameSite=Lax; Max-Age=3600";
}

/// csrf_matches compares the `csrf` cookie with the request header token in
/// constant time (registry middleware_csrf_valid).
/// Complexity: O(n).
pub fn csrf_matches(cookie_header: Str, header_token: Str) -> Bool {
  if cookie_header.len() == 0 || header_token.len() == 0 { return false; }
  let jar = cookie.cookie_parse_request(cookie_header);
  let opt = cookie.cookie_get(&jar, "csrf");
  if opt.is_none { return false; }
  let tok = opt.value;
  return middleware_csrf_valid(header_token, tok);
}
