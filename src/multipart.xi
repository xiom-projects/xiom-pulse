// XIOM PULSE -- multipart/form-data parser (0.2 uploads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Byte-level parser for `multipart/form-data` request bodies. Part
// content is held in a byte-transparent Str (the same representation the
// static server round-trips binary files with), so binary uploads are
// safe. Caps are parameters: `max_parts` per request and
// `max_file_bytes` per part (the 1 MiB decoded-body cap in the HTTP core
// still bounds the total). Error codes are stable:
//   boundary_not_found / malformed / too_many_parts / part_too_large.
module xiom.pulse.multipart

use xiom.string;
use xiom.pulse.http;

/// MultipartPart - one decoded part (content is byte-transparent Str).
pub type MultipartPart = {
  name: Str;
  filename: Str;
  content_type: Str;
  content: Str;
}

/// MultipartParse - parse outcome with stable `error` codes.
pub type MultipartParse = {
  ok: Bool;
  error: Str;
  parts: Vec[MultipartPart];
}

/// PartScan - one decoded part plus header-policy observations.
type PartScan = {
  part: MultipartPart;
  dup_disposition: Bool;
}

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

/// boundary_from_content_type extracts the boundary parameter of a
/// multipart/form-data content type ("" when absent/not multipart).
/// Complexity: O(n). Pure.
pub fn boundary_from_content_type(ct: Str) -> Str {
  let lower = ascii_lower(ct);
  let midx = string.str_index_of(lower, "multipart/form-data");
  if midx.is_none { return ""; }
  let bidx = string.str_index_of(lower, "boundary=");
  if bidx.is_none { return ""; }
  var raw = string.str_slice(ct, bidx.value + 9, ct.len());
  let semi = string.str_index_of(raw, ";");
  if !semi.is_none { raw = string.str_slice(raw, 0, semi.value); }
  raw = string.str_trim(raw);
  if raw.len() >= 2 && raw.byte_at(0) == 34u8 && raw.byte_at(raw.len() - 1) == 34u8 {
    raw = string.str_slice(raw, 1, raw.len() - 1);
  }
  return raw;
}

/// sanitized_ext returns a lowercase alphanumeric extension (max 8 chars)
/// from a client filename, or "" when there is none/unsafe. The client
/// filename is NEVER used as a path component. Complexity: O(n). Pure.
pub fn sanitized_ext(filename: Str) -> Str {
  var dot: Int = -1;
  var i: Int = filename.len() - 1;
  while i >= 0 {
    let b = filename.byte_at(i);
    if b == 46u8 {
      dot = i;
      break;
    }
    if b == 47u8 || b == 92u8 { break; }
    i = i - 1;
  }
  if dot < 0 || dot + 1 >= filename.len() { return ""; }
  var out: Str = "";
  var j: Int = dot + 1;
  while j < filename.len() && out.len() < 8 {
    let b = filename.byte_at(j);
    var c: UInt8 = b;
    if b >= 65u8 && b <= 90u8 { c = ((b as Int) + 32) as UInt8; }
    let ok_digit = c >= 48u8 && c <= 57u8;
    let ok_alpha = c >= 97u8 && c <= 122u8;
    if !(ok_digit || ok_alpha) { return ""; }
    out = out + string.str_slice(filename, j, j + 1);
    j = j + 1;
  }
  return out;
}

/// csv_has reports whether tok is a comma-separated list entry. Entries
/// and tok are trimmed and lower-cased; extension entries may carry a
/// leading dot. Complexity: O(n). Pure.
fn csv_has(csv: Str, tok: Str, strip_dot: Bool) -> Bool {
  if tok.len() == 0 { return false; }
  let items = string.str_split(csv, ",");
  var i: Int = 0;
  while i < items.len() {
    var t = ascii_lower(string.str_trim(items[i]));
    if strip_dot && t.len() > 0 && t.byte_at(0) == 46u8 {
      t = string.str_slice(t, 1, t.len());
    }
    if t == tok { return true; }
    i = i + 1;
  }
  return false;
}

/// ext_allowed reports whether a sanitized extension is in the allowlist
/// (comma-separated, e.g. "txt,md,png"). Unknown/empty extensions are
/// always rejected. Complexity: O(n). Pure.
pub fn ext_allowed(ext: Str, allowed_csv: Str) -> Bool {
  return csv_has(allowed_csv, ext, true);
}

/// mime_base normalizes a Content-Type to its lower-case media type
/// (parameters such as `; charset=utf-8` are dropped). Complexity: O(n). Pure.
pub fn mime_base(content_type: Str) -> Str {
  let lower = ascii_lower(string.str_trim(content_type));
  let semi = string.str_index_of(lower, ";");
  if semi.is_none { return lower; }
  return string.str_trim(string.str_slice(lower, 0, semi.value));
}

/// mime_allowed reports whether a part Content-Type's media type is in the
/// allowlist. An absent/unknown media type is rejected. Complexity: O(n). Pure.
pub fn mime_allowed(content_type: Str, allowed_csv: Str) -> Bool {
  let m = mime_base(content_type);
  if m.len() == 0 { return false; }
  return csv_has(allowed_csv, m, false);
}

/// find_bytes returns the first index >= start where `needle` occurs in
/// `hay`, or -1. Naive O(n*m) scan (bodies are <= 1 MiB). Pure.
fn find_bytes(hay: &Vec[UInt8], needle: &Vec[UInt8], start: Int) -> Int {
  if needle.len() == 0 { return start; }
  if start < 0 { return -1; }
  var i: Int = start;
  while i + needle.len() <= hay.len() {
    var j: Int = 0;
    var hit: Bool = true;
    while j < needle.len() {
      if hay[i + j] != needle[j] {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit { return i; }
    i = i + 1;
  }
  return -1;
}

fn param_value(header_value: Str, param: Str) -> Str {
  let needle = param + "=\"";
  let idx = string.str_index_of(header_value, needle);
  if idx.is_none { return ""; }
  let start = idx.value + needle.len();
  let rest = string.str_slice(header_value, start, header_value.len());
  let end = string.str_index_of(rest, "\"");
  if end.is_none { return ""; }
  return string.str_slice(header_value, start, start + end.value);
}

fn part_from_scan(headers: Str, content: Str) -> PartScan {
  var p: MultipartPart = MultipartPart{ name: ""; filename: ""; content_type: ""; content: content };
  var seen_cd: Bool = false;
  var dup_cd: Bool = false;
  let lines = string.str_split(headers, "\r\n");
  var i: Int = 0;
  while i < lines.len() {
    let line = lines[i];
    let colon = string.str_index_of(line, ":");
    if !colon.is_none {
      let hn = ascii_lower(string.str_trim(string.str_slice(line, 0, colon.value)));
      let hv = string.str_trim(string.str_slice(line, colon.value + 1, line.len()));
      if hn == "content-disposition" {
        if seen_cd { dup_cd = true; }
        seen_cd = true;
        p.name = param_value(hv, "name");
        p.filename = param_value(hv, "filename");
      }
      if hn == "content-type" {
        p.content_type = hv;
      }
    }
    i = i + 1;
  }
  return PartScan{ part: p; dup_disposition: dup_cd };
}

/// parse_multipart decodes a multipart/form-data body. Complexity:
/// O(body * parts).
pub fn parse_multipart(body: &Vec[UInt8], boundary: Str, max_parts: Int, max_file_bytes: Int) -> MultipartParse {
  return parse_multipart_core(body, boundary, max_parts, max_file_bytes, 0, false);
}

/// parse_multipart_strict is the upload-policy parser: it additionally
/// enforces a part-header cap (`max_header_bytes`, 413 when exceeded) and
/// rejects a part with more than one Content-Disposition header instead of
/// letting the last one win. Complexity: O(body * parts).
pub fn parse_multipart_strict(body: &Vec[UInt8], boundary: Str, max_parts: Int, max_file_bytes: Int, max_header_bytes: Int) -> MultipartParse {
  return parse_multipart_core(body, boundary, max_parts, max_file_bytes, max_header_bytes, true);
}

fn parse_multipart_core(body: &Vec[UInt8], boundary: Str, max_parts: Int, max_file_bytes: Int, max_header_bytes: Int, reject_dup: Bool) -> MultipartParse {
  var out: MultipartParse = MultipartParse{ ok: false; error: ""; parts: Vec[MultipartPart].new() };
  if boundary.len() == 0 {
    out.error = "boundary_not_found";
    return out;
  }
  let delim = http.str_to_bytes("--" + boundary);
  let crlf2 = http.str_to_bytes("\r\n\r\n");
  let crlf_delim = http.str_to_bytes("\r\n--" + boundary);
  var pos = find_bytes(body, &delim, 0);
  if pos < 0 {
    out.error = "boundary_not_found";
    return out;
  }
  pos = pos + delim.len();
  while true {
    // Terminator: "--" right after the boundary token.
    if pos + 2 <= body.len() && body[pos] == 45u8 && body[pos + 1] == 45u8 {
      out.ok = true;
      return out;
    }
    if !(pos + 2 <= body.len() && body[pos] == 13u8 && body[pos + 1] == 10u8) {
      out.error = "malformed";
      return out;
    }
    pos = pos + 2;
    let he = find_bytes(body, &crlf2, pos);
    if he < 0 {
      out.error = "malformed";
      return out;
    }
    if max_header_bytes > 0 && he - pos > max_header_bytes {
      out.error = "header_too_large";
      return out;
    }
    let headers = http.bytes_to_str(body, pos, he);
    pos = he + 4;
    let ce = find_bytes(body, &crlf_delim, pos);
    if ce < 0 {
      out.error = "malformed";
      return out;
    }
    let part_len = ce - pos;
    if part_len > max_file_bytes {
      out.error = "part_too_large";
      return out;
    }
    if out.parts.len() >= max_parts {
      out.error = "too_many_parts";
      return out;
    }
    let content = http.bytes_to_str(body, pos, ce);
    let scan = part_from_scan(headers, content);
    if reject_dup && scan.dup_disposition {
      out.error = "duplicate_content_disposition";
      return out;
    }
    out.parts.push(scan.part);
    pos = ce + 2 + delim.len();
  }
  return out;
}
