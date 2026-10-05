// XIOM PULSE -- JWT HS256 sign/verify on the stdlib crypto primitives.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Uses stdlib `xiom.crypto.hmac_sha256` (links under XIOM_RUNTIME_DIR) and
// `xiom.encoding.base64url_*`. Constant-time signature compare; optional
// `exp` enforcement in hs256_verify_now. Structural decode stays in the
// registry `xiom.jwt` package for callers that want claim parsing.
module xiom.pulse.jwt_hs

use xiom.string;
use xiom.encoding;
use xiom.crypto;
use xiom.convert;
use xiom.serialize.json;

fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn ct_eq(a: Str, b: Str) -> Bool {
  if a.len() != b.len() { return false; }
  var diff: Int = 0;
  var i: Int = 0;
  while i < a.len() {
    var d: Int = (a.byte_at(i) as Int) - (b.byte_at(i) as Int);
    if d < 0 { d = 0 - d; }
    diff = diff + d;
    i = i + 1;
  }
  return diff == 0;
}

fn hs256_parts(token: Str) -> (Str, Str, Str) {
  var empty: (Str, Str, Str) = ("", "", "");
  let d1o = string.str_index_of(token, ".");
  if d1o.is_none { return empty; }
  let d1 = d1o.value;
  let rest = string.str_slice(token, d1 + 1, token.len());
  let d2o = string.str_index_of(rest, ".");
  if d2o.is_none { return empty; }
  let d2 = d2o.value;
  let h = string.str_slice(token, 0, d1);
  let p = string.str_slice(rest, 0, d2);
  let s = string.str_slice(rest, d2 + 1, rest.len());
  if h.len() == 0 || p.len() == 0 || s.len() == 0 { return empty; }
  return (h, p, s);
}

/// hs256_sign signs `payload_json` with `secret` (header is fixed
/// `{"alg":"HS256","typ":"JWT"}`).
/// Complexity: O(n). Pure.
pub fn hs256_sign(payload_json: Str, secret: Str) -> Str {
  let header: Str = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
  let hb = str_to_bytes(header);
  let pb = str_to_bytes(payload_json);
  let h64 = encoding.base64url_encode(&hb);
  let p64 = encoding.base64url_encode(&pb);
  let signing_input = h64 + "." + p64;
  let si = str_to_bytes(signing_input);
  let key = str_to_bytes(secret);
  let mac = crypto.hmac_sha256(&key, &si);
  let sig = encoding.base64url_encode(&mac);
  return signing_input + "." + sig;
}

/// hs256_verify checks the HS256 signature (constant-time).
/// Complexity: O(n). Pure.
pub fn hs256_verify(token: Str, secret: Str) -> Bool {
  let parts = hs256_parts(token);
  let h = parts.0;
  let p = parts.1;
  let sig = parts.2;
  if h.len() == 0 { return false; }
  let signing_input = h + "." + p;
  let si = str_to_bytes(signing_input);
  let key = str_to_bytes(secret);
  let mac = crypto.hmac_sha256(&key, &si);
  let want = encoding.base64url_encode(&mac);
  return ct_eq(want, sig);
}

/// hs256_payload_text returns the decoded payload JSON, or "".
/// Complexity: O(n). Pure.
pub fn hs256_payload_text(token: Str) -> Str {
  let parts = hs256_parts(token);
  let p = parts.1;
  if p.len() == 0 { return ""; }
  let dec = encoding.base64url_decode(p);
  if dec.is_err { return ""; }
  return Str::from_utf8(dec.value);
}

/// hs256_verify_now verifies the signature and rejects an `exp` claim that
/// is <= now_secs. A missing `exp` passes (signature-only).
/// Complexity: O(n). Pure.
pub fn hs256_verify_now(token: Str, secret: Str, now_secs: Int) -> Bool {
  if !hs256_verify(token, secret) { return false; }
  let payload = hs256_payload_text(token);
  if payload.len() == 0 { return false; }
  let pv = json.json_parse(payload);
  if pv.is_err { return false; }
  let exp_opt = json.json_get(pv.value, "exp");
  if exp_opt.is_none { return true; }
  let ev = exp_opt.value;
  if json.json_type(ev) != "number" { return true; }
  match ev {
    JsonValue.Number(f) => {
      let now_f = convert.int_to_float(now_secs);
      if f <= now_f { return false; }
      return true;
    },
    _ => { return true; },
  }
}
