// probe_pkg_static -- registry-package consumption check: xiom.static 0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run from the repo root (static_serve reads resources/img/pulse-ico.ico):
//   scripts/run.sh tests\probes\probe_pkg_static.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_static

use xiom.static;
use xiom.string;
use xiom.io;

fn header_value(res: StaticResult, name: Str) -> Str {
  var i: Int = 0;
  while i < res.headers.len() {
    let h = res.headers[i];
    if h.name == name {
      return h.value;
    }
    i = i + 1;
  }
  return "";
}

pub fn main() -> Int {
  var fails: Int = 0;

  // --- mime + etag + date --------------------------------------------------
  let m1 = static_mime_of("x.html");
  if !string.str_contains(m1, "text/html") {
    io.println("[FAIL] mime html: " + m1);
    fails = fails + 1;
  } else {
    io.println("[PASS] mime html");
  }
  let m2 = static_mime_of("pulse-ico.ico");
  if !string.str_contains(m2, "image") {
    io.println("[FAIL] mime ico: " + m2);
    fails = fails + 1;
  } else {
    io.println("[PASS] mime ico");
  }
  let e1 = static_etag_stat(100, 5);
  let e2 = static_etag_stat(100, 5);
  if e1 != e2 || e1.len() == 0 {
    io.println("[FAIL] etag deterministic");
    fails = fails + 1;
  } else {
    io.println("[PASS] etag deterministic");
  }
  if !static_etag_matches(e1, e1) {
    io.println("[FAIL] etag match");
    fails = fails + 1;
  } else {
    io.println("[PASS] etag match");
  }
  let d = static_http_date(0);
  if d != "Thu, 01 Jan 1970 00:00:00 GMT" {
    io.println("[FAIL] http date: " + d);
    fails = fails + 1;
  } else {
    io.println("[PASS] http date epoch");
  }

  let pol = StaticPolicy{ max_age: 3600; immutable: false; must_revalidate: false; no_store: false; };
  let cc = static_cache_control(&pol);
  if !string.str_contains(cc, "max-age=3600") {
    io.println("[FAIL] cache-control: " + cc);
    fails = fails + 1;
  } else {
    io.println("[PASS] cache-control");
  }

  // --- ranges --------------------------------------------------------------
  let r1 = static_range_parse("bytes=0-1", 10);
  if !r1.valid || r1.start != 0 || r1.end != 1 {
    io.println("[FAIL] range 0-1");
    fails = fails + 1;
  } else {
    io.println("[PASS] range 0-1");
  }
  let r2 = static_range_parse("bytes=5-", 10);
  if !r2.valid || r2.start != 5 || r2.end != 9 {
    io.println("[FAIL] range open-ended");
    fails = fails + 1;
  } else {
    io.println("[PASS] range open-ended");
  }
  let r3 = static_range_parse("bytes=20-", 10);
  if !r3.unsatisfiable {
    io.println("[FAIL] range unsatisfiable");
    fails = fails + 1;
  } else {
    io.println("[PASS] range unsatisfiable");
  }
  let r4 = static_range_parse("garbage", 10);
  if r4.valid || r4.unsatisfiable {
    io.println("[FAIL] malformed range must be ignored");
    fails = fails + 1;
  } else {
    io.println("[PASS] malformed range ignored");
  }

  // --- path resolution -----------------------------------------------------
  // NOTE: the API takes the path AFTER the leading "/" (a leading slash is
  // rejected as "absolute"); callers strip it from the request target.
  let p1 = static_resolve_path("resources/img", "pulse-ico.ico");
  if !p1.is_ok {
    io.println("[FAIL] resolve icon");
    fails = fails + 1;
  } else {
    io.println("[PASS] resolve icon");
  }
  let p2 = static_resolve_path("resources/img", "../secret.txt");
  if p2.is_ok {
    io.println("[FAIL] traversal must fail");
    fails = fails + 1;
  } else {
    io.println("[PASS] traversal rejected");
  }

  // --- serve (200/304/206/404) --------------------------------------------
  let s1 = static_serve("resources/img", "pulse-ico.ico", "", "", false, &pol);
  if s1.status != 200 || s1.body.len() < 1000 {
    io.println("[FAIL] serve 200 body");
    fails = fails + 1;
  } else {
    io.println("[PASS] serve 200 body");
  }
  let et = header_value(s1, "ETag");
  if et.len() == 0 {
    io.println("[FAIL] serve etag header");
    fails = fails + 1;
  } else {
    let s2 = static_serve("resources/img", "pulse-ico.ico", et, "", false, &pol);
    if s2.status != 304 {
      io.println("[FAIL] serve 304");
      fails = fails + 1;
    } else {
      io.println("[PASS] serve 304");
    }
  }
  let s3 = static_serve("resources/img", "pulse-ico.ico", "", "bytes=0-9", false, &pol);
  if s3.status != 206 || s3.body.len() != 10 {
    io.println("[FAIL] serve 206");
    fails = fails + 1;
  } else {
    io.println("[PASS] serve 206");
  }
  let s4 = static_serve("resources/img", "nope.ico", "", "", false, &pol);
  if s4.status != 404 {
    io.println("[FAIL] serve 404");
    fails = fails + 1;
  } else {
    io.println("[PASS] serve 404");
  }

  if fails == 0 {
    io.println("[PASS] pkg-static");
    return 0;
  }
  io.println("[FAIL] pkg-static fails=" + fails.to_str());
  return fails;
}
