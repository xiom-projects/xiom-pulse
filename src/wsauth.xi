// XIOM PULSE -- stream-route authentication (SSE + WebSocket, opt-in).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// PULSE_WS_AUTH selects the policy for stream routes (/api/sse, /api/ws
// and any registered stream path):
//   off      (default) same-origin/CORS guard only -- no credentials
//   jwt      a valid HS256 JWT signed with PULSE_JWT_SECRET
//   session  a live PULSE session cookie (`sid`)
//
// Browsers cannot set request headers on WebSocket/EventSource, so the JWT
// may arrive in any of:
//   Authorization: Bearer <jwt>            (non-browser clients)
//   Sec-WebSocket-Protocol: pulse.jwt.<jwt> (browser WebSocket carrier)
//   ?token=<jwt> / ?access_token=<jwt>      (browser EventSource fallback)
// Credentials in the query string are redacted from the access log and the
// audit file (redact_target); the Authorization/protocol headers are not
// logged at all.
//
// Unknown PULSE_WS_AUTH values fail CLOSED (stream routes reject) so a typo
// cannot silently disable authentication; PULSE_WS_AUTH=jwt with no
// PULSE_JWT_SECRET also fails closed (the dev default secret is public).
module xiom.pulse.station.wsauth

use xiom.env;
use xiom.string;
use xiom.string.slice;
use xiom.time;
use xiom.jwt;
use xiom.pulse.http;
use xiom.pulse.station.router;
use xiom.pulse.sessions;

const AUTH_OFF: Str = "off";
const AUTH_JWT: Str = "jwt";
const AUTH_SESSION: Str = "session";

/// ws_auth_mode normalizes PULSE_WS_AUTH (lowercase/trim): off, jwt or
/// session; any other non-empty value is returned verbatim so the caller
/// can fail closed (cfg_validate names it at startup).
/// Complexity: O(n). Pure.
pub fn ws_auth_mode() -> Str {
  let raw = string.str_lower(string.str_trim(env.var_or("PULSE_WS_AUTH", "")));
  if raw.len() == 0 || raw == "0" || raw == "false" || raw == AUTH_OFF {
    return AUTH_OFF;
  }
  if raw == "bearer" { return AUTH_JWT; }
  if raw == "cookie" { return AUTH_SESSION; }
  return raw;
}

fn is_token_param(name: Str) -> Bool {
  let n = string.str_lower(name);
  return n == "token" || n == "access_token";
}

/// bearer_token extracts the credential from an Authorization header value
/// ("Bearer <token>", case-insensitive scheme); "" when absent/malformed.
/// Complexity: O(n). Pure.
fn bearer_token(v: Str) -> Str {
  let t = string.str_trim(v);
  if t.len() <= 7 { return ""; }
  let scheme = string.str_lower(string.str_slice(t, 0, 7));
  if scheme != "bearer " { return ""; }
  return string.str_trim(string.str_slice(t, 7, t.len()));
}

/// protocol_token extracts a browser-supplied credential from a
/// Sec-WebSocket-Protocol list: an entry `pulse.jwt.<token>` (or
/// `bearer.<token>`). Other subprotocols are ignored.
/// Complexity: O(n). Pure.
fn protocol_token(v: Str) -> Str {
  if v.len() == 0 { return ""; }
  var i: Int = 0;
  var start: Int = 0;
  while i <= v.len() {
    if i == v.len() || v.byte_at(i) == 44u8 {
      let tok = string.str_trim(string.str_slice(v, start, i));
      let lt = string.str_lower(tok);
      if string.str_starts_with(lt, "pulse.jwt.") {
        return string.str_trim(string.str_slice(tok, 10, tok.len()));
      }
      if string.str_starts_with(lt, "bearer.") {
        return string.str_trim(string.str_slice(tok, 7, tok.len()));
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return "";
}

/// query_token extracts ?token= / ?access_token= from the request target.
/// Complexity: O(n). Pure.
fn query_token(target: Str) -> Str {
  let parts = router.split_target(target);
  if parts.1.len() == 0 { return ""; }
  let pq = router.parse_query(parts.1);
  var i: Int = 0;
  while i < pq.0.len() {
    let nm: Str = pq.0[i];
    if is_token_param(nm) {
      let vv: Str = pq.1[i];
      return vv;
    }
    i = i + 1;
  }
  return "";
}

/// extract_token returns the first credential found across the supported
/// carriers (Authorization, subprotocol, query); "" when none is present.
/// Complexity: O(headers + n). Pure.
pub fn extract_token(req: &PulseRequest) -> Str {
  let a = bearer_token(http.header_get(req, "authorization"));
  if a.len() > 0 { return a; }
  let p = protocol_token(http.header_get(req, "sec-websocket-protocol"));
  if p.len() > 0 { return p; }
  return query_token(req.target);
}

/// redact_target rewrites token/access_token query values to REDACTED for
/// logs and audit. Targets without a token parameter are returned verbatim
/// (no re-encoding of unrelated queries). Complexity: O(n). Pure.
pub fn redact_target(target: Str) -> Str {
  let parts = router.split_target(target);
  if parts.1.len() == 0 { return target; }
  let pq = router.parse_query(parts.1);
  var has_token: Bool = false;
  var i: Int = 0;
  while i < pq.0.len() {
    let nm: Str = pq.0[i];
    if is_token_param(nm) { has_token = true; }
    i = i + 1;
  }
  if !has_token { return target; }
  var out: Str = parts.0 + "?";
  var j: Int = 0;
  while j < pq.0.len() {
    if j > 0 { out = out + "&"; }
    let nm: Str = pq.0[j];
    let vv: Str = pq.1[j];
    if is_token_param(nm) {
      out = out + nm + "=REDACTED";
    } else {
      out = out + nm + "=" + vv;
    }
    j = j + 1;
  }
  return out;
}

/// jwt_allowed verifies an HS256 token against an explicitly configured
/// PULSE_JWT_SECRET (the packaged dev default is deliberately refused).
/// Complexity: O(token). Pure.
fn jwt_allowed(token: Str) -> Bool {
  let secret: Str = env.var_or("PULSE_JWT_SECRET", "");
  if secret.len() == 0 { return false; }
  let key = slice.str_bytes(secret);
  let vr = jwt.jwt_verify_hs256(token, &key, time.unix_timestamp());
  return vr.is_ok;
}

/// session_allowed requires a live `sid` session cookie.
/// Complexity: O(cookie + sessions). Pure.
fn session_allowed(req: &PulseRequest) -> Bool {
  let id: Str = sessions.session_id_from_cookie(http.header_get(req, "cookie"));
  if id.len() == 0 { return false; }
  let user: Str = sessions.session_get(id);
  return user.len() > 0;
}

/// challenge_header returns the WWW-Authenticate value for a 401 ("" when
/// the active mode is not bearer-based). Complexity: O(1). Pure.
pub fn challenge_header() -> Str {
  if ws_auth_mode() == AUTH_JWT { return "Bearer"; }
  return "";
}

/// denied_reason is "" when the stream request may proceed; otherwise a
/// short diagnostic (mapped to a generic 401 body at the call site).
/// Complexity: O(headers + token + sessions). Pure.
pub fn denied_reason(req: &PulseRequest) -> Str {
  let mode: Str = ws_auth_mode();
  if mode == AUTH_OFF { return ""; }
  if mode == AUTH_JWT {
    let secret: Str = env.var_or("PULSE_JWT_SECRET", "");
    if secret.len() == 0 {
      return "jwt secret not configured";
    }
    let tok: Str = extract_token(req);
    if tok.len() == 0 { return "missing token"; }
    if !jwt_allowed(tok) { return "invalid token"; }
    return "";
  }
  if mode == AUTH_SESSION {
    if session_allowed(req) { return ""; }
    return "missing session";
  }
  return "invalid auth mode";
}
