// XIOM PULSE -- HTTP/1.1 request parsing and response building.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure, socket-free helpers (unit-testable). Reads are done by the caller
// through xiom.net.socket (raw fd) because C-PULSE-01 disables one-arg
// `.read(...)` methods on the pinned compiler.
module xiom.pulse.http

use xiom.string;
use xiom.string.compare;
use xiom.convert.parse;

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

/// str_to_bytes converts Str to its raw bytes (no FFI reach-around).
/// Complexity: O(n). Pure.
pub fn str_to_bytes(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
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

/// find_crlf returns the index of the next CRLF in [from, limit), or -1.
/// Complexity: O(n). Pure.
fn find_crlf(buf: &Vec[UInt8], from: Int, limit: Int) -> Int {
  var i: Int = from;
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

  let line_end = find_crlf(raw, 0, hdr_end + 2);
  if line_end < 0 || line_end > hdr_end {
    req.error = "malformed request line";
    return req;
  }
  let rl = bytes_to_str(raw, 0, line_end);

  var sp1: Int = -1;
  match string.str_index_of(rl, " ") {
    Some(v) => { sp1 = v; },
    None => {
      req.error = "request line: no separator";
      return req;
    },
  }
  if sp1 <= 0 {
    req.error = "request line: empty method";
    return req;
  }
  let rest = string.str_slice(rl, sp1 + 1, rl.len());
  var sp2: Int = -1;
  match string.str_index_of(rest, " ") {
    Some(v) => { sp2 = v; },
    None => {
      req.error = "request line: no target/version separator";
      return req;
    },
  }
  if sp2 <= 0 {
    req.error = "request line: empty target";
    return req;
  }
  req.method = string.str_slice(rl, 0, sp1);
  req.target = string.str_slice(rest, 0, sp2);
  req.version = string.str_slice(rest, sp2 + 1, rest.len());
  if req.version.len() == 0 {
    req.error = "request line: empty version";
    return req;
  }

  var pos: Int = line_end + 2;
  while pos < hdr_end {
    let next = find_crlf(raw, pos, hdr_end + 2);
    if next < 0 { break; }
    let line = bytes_to_str(raw, pos, next);
    if line.len() > 0 {
      var col: Int = -1;
      match string.str_index_of(line, ":") {
        Some(v) => { col = v; },
        None => {
          req.error = "malformed header";
          return req;
        },
      }
      if col <= 0 {
        req.error = "malformed header: empty name";
        return req;
      }
      let name = string.str_slice(line, 0, col);
      let value = string.str_trim(string.str_slice(line, col + 1, line.len()));
      req.header_names.push(name);
      req.header_values.push(value);
    }
    pos = next + 2;
  }

  let cl_str = header_get(&req, "content-length");
  var body_want: Int = 0;
  if cl_str.len() > 0 {
    let pr = parse_int(cl_str);
    if pr.is_ok {
      body_want = pr.value;
    }
  }
  if body_want > 0 {
    let bstart = hdr_end + 4;
    var i: Int = bstart;
    while i < raw.len() && req.body.len() < body_want {
      req.body.push(raw[i]);
      i = i + 1;
    }
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
  if code == 400 { return "Bad Request"; }
  if code == 401 { return "Unauthorized"; }
  if code == 403 { return "Forbidden"; }
  if code == 404 { return "Not Found"; }
  if code == 405 { return "Method Not Allowed"; }
  if code == 413 { return "Payload Too Large"; }
  if code == 429 { return "Too Many Requests"; }
  if code == 500 { return "Internal Server Error"; }
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

/// build_response builds a JSON response with Connection: close.
/// Complexity: O(n). Pure.
pub fn build_response(status: Int, body: Str) -> Vec[UInt8] {
  var none: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  return build_response_full(status, "application/json; charset=utf-8", &none, body);
}
