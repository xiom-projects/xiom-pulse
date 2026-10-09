// XIOM PULSE -- outbound HTTP seam: SSRF guard + request planning.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Two halves, deliberately split:
//   * this module is PURE and dependency-free (no xiom.http import), so
//     the guard compiles and is probed on every platform;
//   * `xiom.pulse.outbound_transport` performs the actual call through the
//     registry xiom.http client (libcurl). It needs the package build
//     hook (`--c-source <xiom-http-bridge.c> --link curl --link-path ..`,
//     the same `--c-source` story filed for xiom.sqlite) and is therefore
//     not imported by the server build yet.
//
// SSRF policy (default = blocklist; set PULSE_HTTP_ALLOWLIST to flip to
// an explicit allowlist):
//   * only http/https; userinfo refused;
//   * localhost/.localhost/.local/.internal/.home.arpa refused;
//   * numeric IPv4 in ANY inet_aton form (dotted, short, octal, hex,
//     single decimal) refused when loopback/private/CGNAT/link-local/
//     multicast/reserved;
//   * IPv6 loopback, unique-local, link-local (and v4-mapped forms)
//     refused;
//   * PULSE_HTTP_ALLOWLIST=host1,host2 (exact or subdomain) is consulted
//     first and wins -- an operator opt-in may include private hosts.
//   * DNS caveat: the guard checks the LITERAL host; a public hostname
//     that resolves to a private address (DNS rebinding) is not stopped
//     by the blocklist -- use the allowlist for strict egress control.
module xiom.pulse.outbound

use xiom.string;
use xiom.env;

/// OutboundVerdict - SSRF-guard decision for one URL.
pub type OutboundVerdict = {
  allowed: Bool;
  reason: Str;
  host: Str;
}

/// OutboundResult - one completed (or refused) outbound call.
pub type OutboundResult = {
  ok: Bool;
  status: Int;
  body: Str;
  error: Str;
}

/// ascii_lower lowercases A-Z only (hosts are ASCII on the wire).
/// Complexity: O(n). Pure.
fn ascii_lower(s: Str) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b >= 65u8 && b <= 90u8 {
      out.push(((b as Int) + 32) as UInt8);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// scheme_of returns the lowercased URL scheme ("" when malformed).
/// Complexity: O(n). Pure.
fn scheme_of(url: Str) -> Str {
  let idx = string.str_index_of(url, "://");
  if idx.is_none { return ""; }
  return ascii_lower(string.str_slice(url, 0, idx.value));
}

/// authority_of returns the authority component ("" when malformed).
/// Complexity: O(n). Pure.
fn authority_of(url: Str) -> Str {
  let idx = string.str_index_of(url, "://");
  if idx.is_none { return ""; }
  let start = idx.value + 3;
  var end: Int = url.len();
  var i: Int = start;
  while i < url.len() {
    let b = url.byte_at(i);
    if b == 47u8 || b == 63u8 || b == 35u8 {
      end = i;
      break;
    }
    i = i + 1;
  }
  return string.str_slice(url, start, end);
}

/// host_of extracts the lowercased host from an authority; IPv6 brackets
/// are stripped. Returns "" for a bracketless multi-colon authority.
/// Complexity: O(n). Pure.
fn host_of(authority: Str) -> Str {
  if authority.len() == 0 { return ""; }
  if authority.byte_at(0) == 91u8 {
    let cb = string.str_index_of(authority, "]");
    if cb.is_none { return ""; }
    return ascii_lower(string.str_slice(authority, 1, cb.value));
  }
  var colons: Int = 0;
  var i: Int = 0;
  while i < authority.len() {
    if authority.byte_at(i) == 58u8 { colons = colons + 1; }
    i = i + 1;
  }
  if colons > 1 { return ""; }
  let co = string.str_index_of(authority, ":");
  if co.is_none { return ascii_lower(authority); }
  return ascii_lower(string.str_slice(authority, 0, co.value));
}

fn trim_trailing_dot(h: Str) -> Str {
  if h.len() > 0 && h.byte_at(h.len() - 1) == 46u8 {
    return string.str_slice(h, 0, h.len() - 1);
  }
  return h;
}

fn hex_digit(b: UInt8) -> Int {
  if b >= 48u8 && b <= 57u8 { return (b as Int) - 48; }
  if b >= 97u8 && b <= 102u8 { return (b as Int) - 87; }
  if b >= 65u8 && b <= 70u8 { return (b as Int) - 55; }
  return -1;
}

/// parse_part parses one inet_aton component (decimal, octal with a
/// leading 0, or hex with 0x). -1 when not a number. Complexity: O(n).
fn parse_part(p: Str) -> Int {
  if p.len() == 0 { return -1; }
  var base: Int = 10;
  var start: Int = 0;
  if p.len() > 2 && p.byte_at(0) == 48u8 && (p.byte_at(1) == 120u8 || p.byte_at(1) == 88u8) {
    base = 16;
    start = 2;
  } else if p.len() > 1 && p.byte_at(0) == 48u8 {
    base = 8;
    start = 1;
  }
  if start >= p.len() { return -1; }
  var v: Int = 0;
  var i: Int = start;
  while i < p.len() {
    let d = hex_digit(p.byte_at(i));
    if d < 0 { return -1; }
    if base == 8 && d > 7 { return -1; }
    if base == 10 && d > 9 { return -1; }
    v = v * base + d;
    if v > 4294967295 { return -1; }
    i = i + 1;
  }
  return v;
}

/// ipv4_value returns the numeric value of an inet_aton-style IPv4 host
/// (1-4 parts, last part may carry the remaining bytes), or -1 when the
/// host is not numeric. Complexity: O(n). Pure.
fn ipv4_value(host: Str) -> Int {
  let parts = string.str_split(host, ".");
  if parts.len() < 1 || parts.len() > 4 { return -1; }
  var vals: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  while i < parts.len() {
    let v = parse_part(parts[i]);
    if v < 0 { return -1; }
    vals.push(v);
    i = i + 1;
  }
  var j: Int = 0;
  while j < vals.len() - 1 {
    if vals[j] > 255 { return -1; }
    j = j + 1;
  }
  var value: Int = 0;
  if vals.len() == 4 {
    if vals[3] > 255 { return -1; }
    value = vals[0] * 16777216 + vals[1] * 65536 + vals[2] * 256 + vals[3];
  } else if vals.len() == 3 {
    if vals[2] > 65535 { return -1; }
    value = vals[0] * 16777216 + vals[1] * 65536 + vals[2];
  } else if vals.len() == 2 {
    if vals[1] > 16777215 { return -1; }
    value = vals[0] * 16777216 + vals[1];
  } else {
    value = vals[0];
  }
  if value > 4294967295 { return -1; }
  return value;
}

fn ipv4_blocked(v: Int) -> Bool {
  if v < 0 { return false; }
  let a = (v / 16777216) % 256;
  if a == 0 { return true; }                                       // 0.0.0.0/8
  if a == 10 { return true; }                                      // 10/8
  if a == 127 { return true; }                                     // loopback
  if a >= 224 { return true; }                                     // multicast + reserved
  if v >= 1681915904 && v <= 1686110207 { return true; }           // 100.64/10 CGNAT
  if v >= 2851995648 && v <= 2852061183 { return true; }           // 169.254/16
  if v >= 2886729728 && v <= 2887778303 { return true; }           // 172.16/12
  if v >= 3221225472 && v <= 3221225727 { return true; }           // 192.0.0/24
  if v >= 3232235520 && v <= 3232301055 { return true; }           // 192.168/16
  if v >= 3323068416 && v <= 3323199487 { return true; }           // 198.18/15
  return false;
}

fn ipv6_blocked(h: Str) -> Bool {
  if h == "::" || h == "::1" { return true; }
  if string.str_starts_with(h, "fc") || string.str_starts_with(h, "fd") { return true; }   // fc00::/7
  if string.str_starts_with(h, "fe8") || string.str_starts_with(h, "fe9") { return true; } // fe80::/10
  if string.str_starts_with(h, "fea") || string.str_starts_with(h, "feb") { return true; }
  if string.str_starts_with(h, "::ffff:") {
    let tail = string.str_slice(h, 7, h.len());
    let v = ipv4_value(tail);
    if v >= 0 { return ipv4_blocked(v); }
    return true;
  }
  return false;
}

fn host_in_allowlist(host: Str, allow: Str) -> Bool {
  let entries = string.str_split(allow, ",");
  var i: Int = 0;
  while i < entries.len() {
    let e = ascii_lower(string.str_trim(entries[i]));
    if e.len() > 0 {
      if host == e { return true; }
      if string.str_ends_with(host, "." + e) { return true; }
    }
    i = i + 1;
  }
  return false;
}

/// outbound_verdict applies the SSRF policy to `url`. Complexity: O(url).
pub fn outbound_verdict(url: Str) -> OutboundVerdict {
  var v: OutboundVerdict = OutboundVerdict{ allowed: false; reason: "malformed_url"; host: "" };
  let scheme = scheme_of(url);
  if scheme.len() == 0 { return v; }
  if scheme != "http" && scheme != "https" {
    v.reason = "scheme_not_allowed";
    return v;
  }
  let authority = authority_of(url);
  if authority.len() == 0 { return v; }
  if string.str_contains(authority, "@") {
    v.reason = "userinfo_not_allowed";
    return v;
  }
  let host = trim_trailing_dot(host_of(authority));
  v.host = host;
  if host.len() == 0 { return v; }
  let allow = env.var_or("PULSE_HTTP_ALLOWLIST", "");
  if allow.len() > 0 {
    if host_in_allowlist(host, allow) {
      v.allowed = true;
      return v;
    }
    v.reason = "not_in_allowlist";
    return v;
  }
  if host == "localhost" || string.str_ends_with(host, ".localhost") {
    v.reason = "private_host";
    return v;
  }
  if string.str_ends_with(host, ".local") || string.str_ends_with(host, ".internal") || string.str_ends_with(host, ".home.arpa") {
    v.reason = "private_host";
    return v;
  }
  let ipv4 = ipv4_value(host);
  if ipv4 >= 0 {
    if ipv4_blocked(ipv4) {
      v.reason = "private_address";
      return v;
    }
    v.allowed = true;
    return v;
  }
  if string.str_contains(host, ":") {
    if ipv6_blocked(host) {
      v.reason = "private_address";
      return v;
    }
    v.allowed = true;
    return v;
  }
  v.allowed = true;
  return v;
}

/// outbound_max_bytes returns the response-size cap
/// (PULSE_HTTP_MAX_BYTES, default 262144). Complexity: O(n). Pure.
pub fn outbound_max_bytes() -> Int {
  let s = env.var_or("PULSE_HTTP_MAX_BYTES", "262144");
  if s.len() == 0 { return 262144; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return 262144; }
    v = v * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  if v <= 0 { return 262144; }
  return v;
}
