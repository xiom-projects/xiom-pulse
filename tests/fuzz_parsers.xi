// XIOM PULSE -- deterministic parser fuzz harness (WP2 assurance).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Seeds a PCG generator, then drives the pure parsers with a curated corpus
// plus mutations and random bytes:
//   * xiom.pulse.http.parse_request (request line, headers, CL, chunked,
//     caps, smuggling shapes),
//   * xiom.pulse.multipart.parse_multipart (boundary/parts/caps),
//   * xiom.pulse.urlenc.parse_form (percent/plus/duplicates),
//   * xiom.pulse.html.html_escape (the shared escape helper).
//
// Invariants: a parser either succeeds with a well-formed result or fails
// with a known error code; it never traps; decoded output never exceeds its
// input; the escape output never contains raw <, > or ". A crash or hang is
// a harness failure (the process aborts / the wrapper times out).
//
// Tunables (env): FUZZ_SEED (default 1592594004), FUZZ_HTTP_ITERS (20000),
// FUZZ_MULTIPART_ITERS (5000), FUZZ_URLENC_ITERS (10000),
// FUZZ_HTML_ITERS (10000). Exit code 0 = green, 1 = failures.
//
// Run: scripts\fuzz_parsers.ps1   (or build + out\fuzz_parsers.exe)

module fuzz_parsers

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.string.builder;
use xiom.convert.parse;
use xiom.rand.pcg;
use xiom.pulse.http;
use xiom.pulse.multipart;
use xiom.pulse.urlenc;
use xiom.pulse.html;

// Cap printed findings so a broad failure does not flood the log.
var logged: Int = 0;

fn fail(where: Str, detail: Str) -> Int {
  if logged < 20 {
    io.println("[FUZZ-FAIL] " + where + ": " + detail);
    logged = logged + 1;
  }
  return 1;
}

fn rint(r: &mut pcg.Pcg, lo: Int, hi: Int) -> Int {
  if hi <= lo { return lo; }
  return lo + pcg.pcg_next_bounded(r, hi - lo);
}

fn rb(r: &mut pcg.Pcg) -> UInt8 {
  return (pcg.pcg_next_bounded(r, 256)) as UInt8;
}

fn hex_char(n: Int) -> UInt8 {
  if n < 10 { return ((48 + n) as UInt8); }
  return ((87 + n) as UInt8);
}

/// dump_bytes renders up to 256 bytes as printable ASCII or \xNN so a fuzz
/// finding can be replayed. Complexity: O(n). Pure.
fn dump_bytes(v: &Vec[UInt8]) -> Str {
  var sb = builder.sb_new();
  var i: Int = 0;
  while i < v.len() && i < 256 {
    let b = v[i];
    if b >= 32u8 && b <= 126u8 && b != 92u8 {
      builder.sb_push_byte(&mut sb, b);
    } else {
      builder.sb_push_str(&mut sb, "\\x");
      builder.sb_push_byte(&mut sb, hex_char((b as Int) / 16));
      builder.sb_push_byte(&mut sb, hex_char((b as Int) % 16));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn copy_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn truncate_bytes(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

/// head_has_nul scans only the request head (through CRLFCRLF); a NUL in the
/// body is legal binary data. Complexity: O(head). Pure.
fn head_has_nul(raw: &Vec[UInt8]) -> Bool {
  let he = http.find_header_end(raw);
  var end = raw.len();
  if he >= 0 {
    end = he + 4;
    if end > raw.len() { end = raw.len(); }
  }
  var i: Int = 0;
  while i < end {
    if raw[i] == 0u8 { return true; }
    i = i + 1;
  }
  return false;
}

fn known_http_error(e: Str) -> Bool {
  return e == "incomplete headers" ||
         e == "malformed request line" ||
         e == "too many headers" ||
         e == "malformed request" ||
         e == "body too large" ||
         e == "incomplete chunked body" ||
         e == "malformed chunked body" ||
         e == "chunked body too large";
}

fn known_multipart_error(e: Str) -> Bool {
  return e == "boundary_not_found" ||
         e == "malformed" ||
         e == "too_many_parts" ||
         e == "part_too_large";
}

/// mutate applies 1-4 rebuild-based mutations (no in-place Vec writes) and
/// never grows past 8 KiB. Complexity: O(len * ops). Pure.
fn mutate(r: &mut pcg.Pcg, base: &Vec[UInt8]) -> Vec[UInt8] {
  var out = copy_bytes(base);
  let ops = rint(r, 1, 4);
  var k: Int = 0;
  while k < ops {
    let op = rint(r, 0, 6);
    if op == 0 && out.len() > 0 {
      let idx = rint(r, 0, out.len());
      let b = rb(r);
      var next: Vec[UInt8] = Vec[UInt8].new();
      var i: Int = 0;
      while i < out.len() {
        if i == idx { next.push(b); } else { next.push(out[i]); }
        i = i + 1;
      }
      out = next;
    } elif op == 1 && out.len() < 8192 {
      out.push(rb(r));
    } elif op == 2 && out.len() > 1 {
      out = truncate_bytes(&out, rint(r, 0, out.len()));
    } elif op == 3 && out.len() > 1 {
      let idx = rint(r, 0, out.len() - 1);
      var next: Vec[UInt8] = Vec[UInt8].new();
      var i: Int = 0;
      while i < out.len() {
        if i == idx { next.push(13u8); }
        elif i == idx + 1 { next.push(10u8); }
        else { next.push(out[i]); }
        i = i + 1;
      }
      out = next;
    } elif op == 4 && out.len() > 0 {
      let idx = rint(r, 0, out.len());
      var next: Vec[UInt8] = Vec[UInt8].new();
      var i: Int = 0;
      while i < out.len() {
        if i == idx { next.push(0u8); } else { next.push(out[i]); }
        i = i + 1;
      }
      out = next;
    } else {
      if out.len() > 0 && out.len() < 8192 {
        let start = rint(r, 0, out.len());
        let end = rint(r, start, out.len());
        var i: Int = start;
        while i < end && out.len() < 8192 {
          out.push(out[i]);
          i = i + 1;
        }
      }
    }
    k = k + 1;
  }
  return out;
}

fn random_request(r: &mut pcg.Pcg) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  let n = rint(r, 0, 1024);
  var i: Int = 0;
  while i < n {
    let pick = rint(r, 0, 10);
    if pick == 0 { out.push(13u8); }
    elif pick == 1 { out.push(10u8); }
    elif pick == 2 { out.push(58u8); }
    elif pick == 3 { out.push(32u8); }
    elif pick == 4 { out.push(47u8); }
    elif pick == 5 { out.push(37u8); }
    else { out.push(rb(r)); }
    i = i + 1;
  }
  if rint(r, 0, 3) == 0 {
    out.push(13u8);
    out.push(10u8);
    out.push(13u8);
    out.push(10u8);
  }
  return out;
}

/// seed_corpus is the curated edge-case set; keep additions small and named
/// in the comment so a regression can be traced to a shape.
fn seed_corpus() -> Vec[Str] {
  var s: Vec[Str] = Vec[Str].new();
  s.push("GET / HTTP/1.1\r\nHost: t\r\n\r\n");
  s.push("GET /health?x=1 HTTP/1.1\r\nHost: t\r\nUser-Agent: fuzz\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 5\r\n\r\nhello");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n0\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: gzip\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5;ext=1\r\nhello\r\n0\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX-T: v\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\nZ\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFFFFFF\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n200000\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 2000000\r\n\r\n");
  s.push("POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 10\r\n\r\nhi");
  s.push("GET\r\n\r\n");
  s.push(" HTTP/1.1\r\n\r\n");
  s.push("GET / HTTP/1.1 extra\r\n\r\n");
  s.push("GET / HTTP/1.1\r\nHost: t\r\nBad Header\r\n\r\n");
  s.push("GET / HTTP/1.1\r\nHost: t\r\nX: ab\r\n\r\n");
  var many = builder.sb_new();
  builder.sb_push_str(&mut many, "GET / HTTP/1.1\r\nHost: t\r\n");
  var i: Int = 0;
  while i < 120 {
    builder.sb_push_str(&mut many, "X-");
    builder.sb_push_int(&mut many, i);
    builder.sb_push_str(&mut many, ": v\r\n");
    i = i + 1;
  }
  builder.sb_push_str(&mut many, "\r\n");
  s.push(builder.sb_to_str(&many));
  var big = builder.sb_new();
  builder.sb_push_str(&mut big, "GET / HTTP/1.1\r\nHost: t\r\nX-Big: ");
  i = 0;
  while i < 17000 {
    builder.sb_push_byte(&mut big, 97u8);
    i = i + 1;
  }
  builder.sb_push_str(&mut big, "\r\n\r\n");
  s.push(builder.sb_to_str(&big));
  return s;
}

fn fuzz_http(r: &mut pcg.Pcg, seeds: &Vec[Str], n: Int, strict_nul: Bool) -> (Int, Int) {
  var f: Int = 0;
  var known_nul: Int = 0;
  var i: Int = 0;
  while i < n {
    let mode = rint(r, 0, 3);
    var raw: Vec[UInt8];
    if mode == 0 {
      raw = random_request(r);
    } elif mode == 1 {
      let si = rint(r, 0, seeds.len());
      raw = http.str_to_bytes(seeds[si]);
      raw = mutate(r, &raw);
    } else {
      let si = rint(r, 0, seeds.len());
      raw = http.str_to_bytes(seeds[si]);
    }
    let req = http.parse_request(&raw);
    if req.ok {
      if head_has_nul(&raw) {
        // Known upstream finding REL-20261106-1716-pulse: the stdlib parser
        // truncates at a NUL and still reports ok. Track it until the parser
        // rejects the head; FUZZ_STRICT_NUL=1 turns it into a hard failure
        // (use that to verify the upstream fix).
        if strict_nul {
          f = f + fail("http NUL in head accepted (strict)", "iter=" + i.to_str() + " raw=" + dump_bytes(&raw));
        } else {
          known_nul = known_nul + 1;
        }
      } else {
        if req.method.len() == 0 || req.target.len() == 0 {
          f = f + fail("http ok with empty method/target", "iter=" + i.to_str() + " raw=" + dump_bytes(&raw));
        }
        if req.header_names.len() != req.header_values.len() {
          f = f + fail("http header vectors out of step", "iter=" + i.to_str());
        }
        if req.body.len() > http.body_limit_bytes() {
          f = f + fail("http body exceeds cap", "iter=" + i.to_str() + " len=" + req.body.len().to_str());
        }
        let _h = http.header_get(&req, "content-length");
      }
    } else {
      if req.error.len() == 0 || !known_http_error(req.error) {
        f = f + fail("http unknown error", "iter=" + i.to_str() + " err=" + req.error);
      }
    }
    i = i + 1;
  }
  return (f, known_nul);
}

fn multipart_seed() -> Str {
  return "--B1\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--B1--\r\n";
}

fn fuzz_multipart(r: &mut pcg.Pcg, n: Int) -> Int {
  var f: Int = 0;
  let base = http.str_to_bytes(multipart_seed());
  var i: Int = 0;
  while i < n {
    var raw: Vec[UInt8];
    if rint(r, 0, 3) == 0 {
      raw = random_request(r);
    } else {
      raw = mutate(r, &base);
    }
    let res = multipart.parse_multipart(&raw, "B1", 4, 512);
    if res.ok {
      if res.parts.len() > 4 {
        f = f + fail("multipart part count exceeds cap", "iter=" + i.to_str());
      }
      var j: Int = 0;
      while j < res.parts.len() {
        if res.parts[j].content.len() > 512 {
          f = f + fail("multipart part exceeds byte cap", "iter=" + i.to_str());
        }
        j = j + 1;
      }
    } else {
      if res.error.len() == 0 || !known_multipart_error(res.error) {
        f = f + fail("multipart unknown error", "iter=" + i.to_str() + " err=" + res.error);
      }
    }
    i = i + 1;
  }
  return f;
}

fn random_form(r: &mut pcg.Pcg) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  let n = rint(r, 0, 256);
  let alphabet = "ab=+%&;0123AF";
  let alen = alphabet.len();
  var i: Int = 0;
  while i < n {
    let k = rint(r, 0, alen);
    out.push(alphabet.byte_at(k));
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn fuzz_urlenc(r: &mut pcg.Pcg, n: Int) -> Int {
  var f: Int = 0;
  var i: Int = 0;
  while i < n {
    let s = random_form(r);
    let p = urlenc.parse_form(s);
    if p.0.len() != p.1.len() {
      f = f + fail("urlenc names/values out of step", "iter=" + i.to_str());
    }
    var j: Int = 0;
    while j < p.0.len() {
      if p.0[j].len() > s.len() || p.1[j].len() > s.len() {
        f = f + fail("urlenc decoded output grew", "iter=" + i.to_str());
      }
      j = j + 1;
    }
    let _ct = urlenc.form_is_urlencoded(s);
    i = i + 1;
  }
  return f;
}

fn fuzz_html(r: &mut pcg.Pcg, n: Int) -> Int {
  var f: Int = 0;
  var i: Int = 0;
  while i < n {
    let s = random_form(r);
    let e = html.html_escape(s);
    if e.len() < s.len() {
      f = f + fail("html escape shrank output", "iter=" + i.to_str());
    }
    if string.str_contains(e, "<") || string.str_contains(e, ">") || string.str_contains(e, "\"") {
      f = f + fail("html escape left a raw tag delimiter", "iter=" + i.to_str());
    }
    i = i + 1;
  }
  return f;
}

fn env_int(name: Str, fallback: Int) -> Int {
  let p = parse_int(env.var_or(name, ""));
  if p.is_ok { return p.value; }
  return fallback;
}

pub fn main() -> Int {
  let seed = env_int("FUZZ_SEED", 1592594004);
  let n_http = env_int("FUZZ_HTTP_ITERS", 20000);
  let n_mp = env_int("FUZZ_MULTIPART_ITERS", 5000);
  let n_url = env_int("FUZZ_URLENC_ITERS", 10000);
  let n_html = env_int("FUZZ_HTML_ITERS", 10000);
  let strict_nul = env_int("FUZZ_STRICT_NUL", 0) != 0;
  var r = pcg.pcg_from_seed(seed as UInt64);
  let seeds = seed_corpus();
  var f: Int = 0;
  let hr = fuzz_http(&mut r, &seeds, n_http, strict_nul);
  f = f + hr.0;
  let known_nul = hr.1;
  f = f + fuzz_multipart(&mut r, n_mp);
  f = f + fuzz_urlenc(&mut r, n_url);
  f = f + fuzz_html(&mut r, n_html);
  if f == 0 {
    io.println("fuzz: GREEN seed=" + seed.to_str() + " http=" + n_http.to_str() + " multipart=" + n_mp.to_str() + " urlenc=" + n_url.to_str() + " html=" + n_html.to_str() + " known_nul=" + known_nul.to_str());
    return 0;
  }
  io.println("fuzz: RED failures=" + f.to_str());
  return 1;
}
