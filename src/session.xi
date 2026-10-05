// XIOM PULSE -- in-memory sessions bound to the `sid` cookie.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Step 2 store: parallel vectors, expiry checked on read, logout marks the
// session expired (no compaction yet -- documented limitation).
module xiom.pulse.session

use xiom.string;
use xiom.time;
use xiom.crypto.rng_crypto;
use xiom.cookie;

var s_ids: Vec[Str] = Vec[Str].new();
var s_users: Vec[Str] = Vec[Str].new();
var s_exp: Vec[Int] = Vec[Int].new();

/// session_create creates a session for `user` and returns its id.
/// Complexity: O(1) plus one crypto draw.
pub fn session_create(user: Str, ttl_secs: Int) -> Str {
  let id = rng_crypto.crypto_random_string(32, "0123456789abcdef");
  s_ids.push(id);
  s_users.push(user);
  s_exp.push(time.unix_timestamp() + ttl_secs);
  return id;
}

/// session_get returns the user for an unexpired id, or "".
/// Complexity: O(sessions).
pub fn session_get(id: Str) -> Str {
  let now = time.unix_timestamp();
  var i: Int = 0;
  while i < s_ids.len() {
    let sid = s_ids[i];
    if string.str_compare(sid, id) == 0 {
      if s_exp[i] > now {
        let u = s_users[i];
        return u;
      }
      return "";
    }
    i = i + 1;
  }
  return "";
}

/// session_drop expires the session id immediately.
/// Complexity: O(sessions).
pub fn session_drop(id: Str) {
  var i: Int = 0;
  while i < s_ids.len() {
    let sid = s_ids[i];
    if string.str_compare(sid, id) == 0 {
      s_exp[i] = 0;
      return;
    }
    i = i + 1;
  }
}

/// session_count returns the number of stored sessions (live + expired).
/// Complexity: O(1).
pub fn session_count() -> Int {
  return s_ids.len();
}

/// session_reset clears the store (tests).
/// Complexity: O(1).
pub fn session_reset() {
  s_ids = Vec[Str].new();
  s_users = Vec[Str].new();
  s_exp = Vec[Int].new();
}

/// session_cookie_header returns the Set-Cookie VALUE for a session
/// (header name is added by the response builder).
/// Complexity: O(1). Pure.
pub fn session_cookie_header(id: Str, ttl_secs: Int) -> Str {
  return "sid=" + id + "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" + ttl_secs.to_str();
}

/// session_expired_cookie_header returns the clearing Set-Cookie VALUE.
/// Complexity: O(1). Pure.
pub fn session_expired_cookie_header() -> Str {
  return "sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0";
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

/// csrf_new_token returns a fresh CSRF token (crypto random hex).
/// Complexity: O(1).
pub fn csrf_new_token() -> Str {
  return rng_crypto.crypto_random_string(32, "0123456789abcdef");
}

/// csrf_cookie_header returns the Set-Cookie VALUE for the CSRF token.
/// Complexity: O(1). Pure.
pub fn csrf_cookie_header(token: Str) -> Str {
  return "csrf=" + token + "; Path=/; SameSite=Lax; Max-Age=3600";
}

/// csrf_matches compares the `csrf` cookie with the request header token
/// in constant time. Complexity: O(n).
pub fn csrf_matches(cookie_header: Str, header_token: Str) -> Bool {
  if cookie_header.len() == 0 || header_token.len() == 0 { return false; }
  let jar = cookie.cookie_parse_request(cookie_header);
  let opt = cookie.cookie_get(&jar, "csrf");
  if opt.is_none { return false; }
  let tok = opt.value;
  if tok.len() != header_token.len() { return false; }
  var diff: Int = 0;
  var i: Int = 0;
  while i < tok.len() {
    var d: Int = (tok.byte_at(i) as Int) - (header_token.byte_at(i) as Int);
    if d < 0 { d = 0 - d; }
    diff = diff + d;
    i = i + 1;
  }
  return diff == 0;
}
