// XIOM PULSE -- HTTP/1.1 request parsing and response building.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure, socket-free helpers (unit-testable). Reads are done by the caller
// through xiom.net.socket (raw fd) because C-PULSE-01 disables one-arg
// `.read(...)` methods on the pinned compiler.
module xiom.pulse.http

use xiom.string;
use xiom.string.slice;
use xiom.string.compare;
use xiom.convert.parse;
use xiom.net.server;

/// PulseRequest - a parsed HTTP/1.1 request head plus buffered body bytes.
pub type PulseRequest = {
  method: Str;
  target: Str;
  version: Str;
  header_names: Vec[Str];
  header_values: Vec[Str];
  body: Vec[UInt8];
  ok: Bool;
  error: Str;
}

/// RouteResult - status code + JSON body for one route dispatch.
pub type RouteResult = {
  status: Int;
  body: Str;
}

/// str_to_bytes converts Str to its raw bytes. Thin alias for the stdlib
/// `xiom.string.slice.str_bytes` (submodule import; the root `xiom.string`
/// does not re-export submodule functions). Complexity: O(n). Pure.
pub fn str_to_bytes(s: Str) -> Vec[UInt8] {
  return slice.str_bytes(s);
}

/// bytes_to_str converts the byte span [start, end) to Str.
/// Complexity: O(n). Pure.
pub fn bytes_to_str(buf: &Vec[UInt8], start: Int, end: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = start;
  while i < end && i < buf.len() {
    out.push(buf[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// find_header_end returns the index of the CRLFCRLF terminator, or -1.
/// Complexity: O(n). Pure.
pub fn find_header_end(buf: &Vec[UInt8]) -> Int {
  let n = buf.len();
  if n < 4 { return -1; }
  var i: Int = 0;
  while i + 4 <= n {
    if buf[i] == 13u8 && buf[i + 1] == 10u8 && buf[i + 2] == 13u8 && buf[i + 3] == 10u8 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// header_limit_bytes returns the max request-head size the server buffers.
/// Complexity: O(1). Pure.
pub fn header_limit_bytes() -> Int {
  return 16384;
}

/// header_overflow is true when no CRLFCRLF terminator was seen within the
/// head-size limit (slow-client / oversized-header guard). O(n). Pure.
pub fn header_overflow(raw: &Vec[UInt8]) -> Bool {
  return find_header_end(raw) < 0 && raw.len() > header_limit_bytes();
}

/// header_count_limit returns the max accepted header lines. O(1). Pure.
pub fn header_count_limit() -> Int {
  return 100;
}

/// find_crlf returns the index of the next CRLF in [from, limit), or -1.
/// Complexity: O(n). Pure.
fn find_crlf(buf: &Vec[UInt8], from: Int, limit: Int) -> Int {  var i: Int = from;
  while i + 2 <= limit && i + 2 <= buf.len() {
    if buf[i] == 13u8 && buf[i + 1] == 10u8 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// parse_request parses the request line, headers and Content-Length body
/// from raw bytes. Never traps: failures set ok=false + error.
///
/// Since 2026-10-07 the syntax layer is the shared stdlib parser
/// (`xiom.net.server.server_parse_request`, built for PULSE); this adapter
/// keeps PULSE's contract:
///   - 100-header cap (error "too many headers") in addition to the
///     16 KiB read-loop guard (header_overflow);
///   - header names arrive lowercased from the stdlib; `header_get` stays
///     case-insensitive, so callers are unaffected;
///   - header values are trimmed (stdlib strips one leading space only);
///   - invalid Content-Length (negative/non-numeric) is now REJECTED
///     (hardening; the differential probe pins it on both parsers).
/// Complexity: O(n). Pure.
pub fn parse_request(raw: &Vec[UInt8]) -> PulseRequest {
  var req: PulseRequest = PulseRequest{
    method: "";
    target: "";
    version: "";
    header_names: Vec[Str].new();
    header_values: Vec[Str].new();
    body: Vec[UInt8].new();
    ok: false;
    error: "";
  };

  let hdr_end = find_header_end(raw);
  if hdr_end < 0 {
    req.error = "incomplete headers";
    return req;
  }

  // PULSE cap: count header lines before handing the raw bytes over.
  let line_end = find_crlf(raw, 0, hdr_end + 2);
  if line_end < 0 || line_end > hdr_end {
    req.error = "malformed request line";
    return req;
  }
  var pos: Int = line_end + 2;
  var hcount: Int = 0;
  while pos < hdr_end {
    let next = find_crlf(raw, pos, hdr_end + 2);
    if next < 0 { break; }
    if next > pos {
      hcount = hcount + 1;
      if hcount > header_count_limit() {
        req.error = "too many headers";
        return req;
      }
    }
    pos = next + 2;
  }

  let sr = server.server_parse_request(raw);
  if sr.is_none {
    req.error = "malformed request";
    return req;
  }
  let r = sr.value;
  req.method = r.method;
  req.target = r.target;
  req.version = r.version;

  var hi: Int = 0;
  while hi < r.headers.len() {
    req.header_names.push(r.headers[hi].0);
    req.header_values.push(string.str_trim(r.headers[hi].1));
    hi = hi + 1;
  }

  var bs: Int = r.body_start;
  var be: Int = r.body_start + r.body_len;
  if be > raw.len() { be = raw.len(); }
  var bi: Int = bs;
  while bi < be {
    req.body.push(raw[bi]);
    bi = bi + 1;
  }

  req.ok = true;
  return req;
}

/// header_get returns the value of the named header (case-insensitive),
/// or "" when absent. Complexity: O(headers). Pure.
pub fn header_get(req: &PulseRequest, name: Str) -> Str {
  var i: Int = 0;
  while i < req.header_names.len() {
    let hname = req.header_names[i];
    if str_eq_ignore_case(hname, name) {
      return req.header_values[i];
    }
    i = i + 1;
  }
  return "";
}

/// content_length_of returns the request's Content-Length parsed from the
/// header span [0, hdr_end), or 0 when absent/invalid. O(n). Pure.
pub fn content_length_of(raw: &Vec[UInt8], hdr_end: Int) -> Int {
  var pos: Int = 0;
  var line_end = find_crlf(raw, pos, hdr_end + 2);
  if line_end < 0 { return 0; }
  pos = line_end + 2;
  while pos < hdr_end {
    let next = find_crlf(raw, pos, hdr_end + 2);
    if next < 0 { break; }
    let line = bytes_to_str(raw, pos, next);
    var col: Int = -1;
    match string.str_index_of(line, ":") {
      Some(v) => { col = v; },
      None => { col = -1; },
    }
    if col > 0 {
      let name = string.str_slice(line, 0, col);
      if str_eq_ignore_case(name, "content-length") {
        let value = string.str_trim(string.str_slice(line, col + 1, line.len()));
        let pr = parse_int(value);
        if pr.is_ok {
          return pr.value;
        }
        return 0;
      }
    }
    pos = next + 2;
  }
  return 0;
}

/// status_text returns the HTTP/1.1 reason phrase. Complexity: O(1).
pub fn status_text(code: Int) -> Str {
  if code == 200 { return "OK"; }
  if code == 201 { return "Created"; }
  if code == 204 { return "No Content"; }
  if code == 206 { return "Partial Content"; }
  if code == 301 { return "Moved Permanently"; }
  if code == 302 { return "Found"; }
  if code == 304 { return "Not Modified"; }
  if code == 400 { return "Bad Request"; }
  if code == 401 { return "Unauthorized"; }
  if code == 403 { return "Forbidden"; }
  if code == 404 { return "Not Found"; }
  if code == 405 { return "Method Not Allowed"; }
  if code == 408 { return "Request Timeout"; }
  if code == 411 { return "Length Required"; }
  if code == 413 { return "Payload Too Large"; }
  if code == 415 { return "Unsupported Media Type"; }
  if code == 416 { return "Range Not Satisfiable"; }
  if code == 429 { return "Too Many Requests"; }
  if code == 500 { return "Internal Server Error"; }
  if code == 501 { return "Not Implemented"; }
  if code == 502 { return "Bad Gateway"; }
  if code == 503 { return "Service Unavailable"; }
  if code == 504 { return "Gateway Timeout"; }
  return "Unknown";
}

/// build_response_full builds a response with a custom content type and
/// extra headers (Set-Cookie, Allow, ...). Complexity: O(n). Pure.
pub fn build_response_full(status: Int, content_type: Str, extra_headers: &Vec[(Str, Str)], body: Str) -> Vec[UInt8] {
  var head: Str = "HTTP/1.1 " + status.to_str() + " " + status_text(status) + "\r\n";
  head = head + "Content-Type: " + content_type + "\r\n";
  var i: Int = 0;
  while i < extra_headers.len() {
    let h = extra_headers[i];
    head = head + h.0 + ": " + h.1 + "\r\n";
    i = i + 1;
  }
  head = head + "X-Content-Type-Options: nosniff\r\n";
  head = head + "X-Frame-Options: DENY\r\n";
  head = head + "Referrer-Policy: no-referrer\r\n";
  head = head + "Content-Length: " + body.len().to_str() + "\r\n";
  head = head + "Connection: close\r\n";
  head = head + "Server: xiom-pulse/0.1.0\r\n";
  head = head + "\r\n";
  var out: Vec[UInt8] = str_to_bytes(head);
  var body_bytes: Vec[UInt8] = str_to_bytes(body);
  var j: Int = 0;
  while j < body_bytes.len() {
    out.push(body_bytes[j]);
    j = j + 1;
  }
  return out;
}

/// build_response_bytes builds a response with a raw byte body (icons,
/// binary assets). Complexity: O(n). Pure.
pub fn build_response_bytes(status: Int, content_type: Str, extra_headers: &Vec[(Str, Str)], body: &Vec[UInt8]) -> Vec[UInt8] {
  var head: Str = "HTTP/1.1 " + status.to_str() + " " + status_text(status) + "\r\n";
  head = head + "Content-Type: " + content_type + "\r\n";
  var i: Int = 0;
  while i < extra_headers.len() {
    let h = extra_headers[i];
    head = head + h.0 + ": " + h.1 + "\r\n";
    i = i + 1;
  }
  head = head + "X-Content-Type-Options: nosniff\r\n";
  head = head + "X-Frame-Options: DENY\r\n";
  head = head + "Referrer-Policy: no-referrer\r\n";
  head = head + "Content-Length: " + body.len().to_str() + "\r\n";
  head = head + "Connection: close\r\n";
  head = head + "Server: xiom-pulse/0.1.0\r\n";
  head = head + "\r\n";
  var out: Vec[UInt8] = str_to_bytes(head);
  var j: Int = 0;
  while j < body.len() {
    out.push(body[j]);
    j = j + 1;
  }
  return out;
}

/// build_response builds a JSON response with Connection: close.
/// Complexity: O(n). Pure.
pub fn build_response(status: Int, body: Str) -> Vec[UInt8] {
  var none: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  return build_response_full(status, "application/json; charset=utf-8", &none, body);
}
