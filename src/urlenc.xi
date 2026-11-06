// XIOM PULSE -- application/x-www-form-urlencoded decoding (site surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Query strings and HTML form bodies share one encoding (RFC 3986 percent
// escapes plus '+' for space), so this module is the single decoder used by
// the router (query strings) and by site handlers (form bodies). It is pure:
// no I/O, no state, no allocation beyond the returned Vecs.
//
// The parser is deliberately tolerant, matching the shipped query parser:
// empty pairs are skipped, a pair without '=' maps to an empty value, and a
// malformed %XX sequence is kept byte-exact rather than rejected. Body size
// and framing caps are owned by the HTTP layer before a handler sees `body`.

module xiom.pulse.urlenc

use xiom.string;

/// hex_val maps an ASCII hex digit to 0..15, or -1 when it is not one.
/// Complexity: O(1). Pure.
fn hex_val(b: UInt8) -> Int {
  if b >= 48u8 && b <= 57u8 { return (b as Int) - 48; }
  if b >= 65u8 && b <= 70u8 { return (b as Int) - 55; }
  if b >= 97u8 && b <= 102u8 { return (b as Int) - 87; }
  return -1;
}

/// url_decode decodes %XX and '+' in a query or form component. A malformed
/// escape is copied byte-exact. Complexity: O(n). Pure.
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

/// parse_pairs parses "a=1&b=x%20y&c" into decoded name/value lists. Empty
/// pairs are skipped; a pair without '=' has an empty value; duplicate
/// names are preserved in order. Complexity: O(n). Pure.
pub fn parse_pairs(qs: Str) -> (Vec[Str], Vec[Str]) {
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

/// form_is_urlencoded reports whether a Content-Type header names
/// application/x-www-form-urlencoded. The media type is compared
/// case-insensitively and may carry parameters (e.g. charset=UTF-8); an
/// empty or unrelated type is false. Complexity: O(ct). Pure.
pub fn form_is_urlencoded(content_type: Str) -> Bool {
  if content_type.len() == 0 {
    return false;
  }
  let ct = string.str_lower(string.str_trim(content_type));
  return string.str_starts_with(ct, "application/x-www-form-urlencoded");
}

/// parse_form parses an application/x-www-form-urlencoded body. The wire
/// encoding is identical to a query string, so this delegates to
/// parse_pairs; the caller is responsible for the Content-Type check
/// (form_is_urlencoded) and the HTTP body cap. Complexity: O(n). Pure.
pub fn parse_form(body: Str) -> (Vec[Str], Vec[Str]) {
  return parse_pairs(body);
}

/// form_value returns the first value for `name`, or "" when it is absent.
/// Duplicate names keep their first occurrence (the HTML form convention).
/// Complexity: O(n). Pure.
pub fn form_value(names: &Vec[Str], values: &Vec[Str], name: Str) -> Str {
  var i: Int = 0;
  while i < names.len() && i < values.len() {
    if names[i] == name {
      return values[i];
    }
    i = i + 1;
  }
  return "";
}
