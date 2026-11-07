// XIOM PULSE -- deterministic HTTP framing security corpus (parser level).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Complements scripts/framing_smoke.ps1/.sh (the live raw-TCP corpus) with
// a fast, server-free regression set for the parser + station gate. Every
// assertion encodes the SECURE expected result (reject ambiguous framing),
// not the currently observed one: a red line is a finding, never a reason
// to weaken the test. The NUL-in-head class is the one deliberate exception:
// the upstream parser accepts it (REL-20261106-1716-pulse), so it is
// reported as [KNOWN] until the pin fixes it; FRAMING_STRICT_NUL=1 turns it
// into a hard failure for post-fix verification.
//
// Run: .\scripts\run.ps1 tests\test_framing.xi
//           (or scripts/run.sh tests/test_framing.xi)
// Exit code = failures (0 = green).
module pulse_framing_tests

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.pulse.http;
use xiom.pulse.station.router;
use xiom.pulse.station.core;

fn check(name: Str, ok: Bool, detail: Str) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name + " -- " + detail);
  return 1;
}

fn known(name: Str, detail: Str) -> Int {
  io.println("[KNOWN] " + name + " -- REL-20261106-1716-pulse: " + detail);
  return 0;
}

fn strict_nul() -> Bool {
  return env.var_or("FRAMING_STRICT_NUL", "0") == "1";
}

/// with_nul inserts one 0x00 byte between two ASCII fragments so the
/// request-head repro is byte-exact and compiler escape-sequence independent.
fn with_nul(prefix: Str, suffix: Str) -> Vec[UInt8] {
  var out = http.str_to_bytes(prefix);
  out.push(0u8);
  let rest = http.str_to_bytes(suffix);
  var i: Int = 0;
  while i < rest.len() {
    out.push(rest[i]);
    i = i + 1;
  }
  return out;
}

fn header_count(req: PulseRequest, name: Str) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < req.header_names.len() {
    if string.str_lower(req.header_names[i]) == name {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

fn body_str(req: PulseRequest) -> Str {
  return http.bytes_to_str(&req.body, 0, req.body.len());
}

/// route_status runs the station dispatcher for (method, target) with the
/// parsed request, exactly like the live loop does after parse.
fn route_status(method: Str, target: Str, req: &PulseRequest, body: Str) -> Int {
  let m = router.route_match(method, target);
  let out = core.handle_route(m, req, body);
  return out.status;
}

fn is_reject(status: Int) -> Bool {
  return status == 400 || status == 408 || status == 413 || status == 414 || status == 431 || status == 501;
}

pub fn main() -> Int {
  var f: Int = 0;

  // --- duplicate Content-Length (CL.CL) ------------------------------------
  // RFC 9112 requires a single unambiguous length; duplicate fields with the
  // same or conflicting values are the classic CL.CL smuggling shape.
  let dup_same = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\nContent-Length: 7\r\n\r\n{\"a\":1}");
  let ds = http.parse_request(&dup_same);
  f = f + check("dup CL same rejected", !ds.ok, "accepted: cl=" + http.content_length_of(&dup_same, http.find_header_end(&dup_same)).to_str() + " headers=" + header_count(ds, "content-length").to_str());
  if ds.ok {
    let st = route_status("POST", "/api/echo", &ds, body_str(ds));
    f = f + check("dup CL same does not dispatch a body", st == 400, "dispatched status=" + st.to_str());
  }

  let dup_conflict = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7\r\nContent-Length: 8\r\n\r\n{\"a\":1}");
  let dc = http.parse_request(&dup_conflict);
  f = f + check("dup CL conflict rejected", !dc.ok, "accepted: first wins, headers=" + header_count(dc, "content-length").to_str());

  let comma_cl = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nContent-Length: 7, 7\r\n\r\n{\"a\":1}");
  let cc = http.parse_request(&comma_cl);
  f = f + check("comma Content-Length rejected", !cc.ok, "accepted: cl=" + http.content_length_of(&comma_cl, http.find_header_end(&comma_cl)).to_str());

  let cl_overflow = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nContent-Length: 999999999999999999999\r\n\r\n");
  let co = http.parse_request(&cl_overflow);
  f = f + check("overflow Content-Length rejected", !co.ok, "accepted: cl=" + http.content_length_of(&cl_overflow, http.find_header_end(&cl_overflow)).to_str());

  let cl_plus = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nContent-Length: +0\r\n\r\n");
  let cp = http.parse_request(&cl_plus);
  f = f + check("signed Content-Length rejected", !cp.ok, "accepted: cl=" + http.content_length_of(&cl_plus, http.find_header_end(&cl_plus)).to_str());

  // Whitespace between the field name and ':' is forbidden (RFC 9112 5.1).
  // A parser that ignores the line while a proxy honours it is a differential.
  let cl_space = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nContent-Length : 7\r\n\r\n{\"a\":1}");
  let cs = http.parse_request(&cl_space);
  f = f + check("whitespace before CL colon rejected", !cs.ok, "accepted: cl=" + http.content_length_of(&cl_space, http.find_header_end(&cl_space)).to_str());

  let hdr_space = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nX-Test : v\r\n\r\n");
  let hs = http.parse_request(&hdr_space);
  f = f + check("whitespace before header colon rejected", !hs.ok, "accepted: X-Test='" + http.header_get(&hs, "x-test") + "'");

  // --- Transfer-Encoding (TE.CL / TE.TE) -----------------------------------
  let te_cl = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nContent-Length: 7\r\n\r\n7\r\n{\"a\":1}\r\n0\r\n\r\n");
  let tc = http.parse_request(&te_cl);
  let tc_st = route_status("POST", "/api/echo", &tc, body_str(tc));
  f = f + check("TE with CL rejected 400", tc_st == 400, "status=" + tc_st.to_str());

  let te_comma = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked, chunked\r\n\r\n7\r\n{\"a\":1}\r\n0\r\n\r\n");
  let tcm = http.parse_request(&te_comma);
  let tcm_st = route_status("POST", "/api/echo", &tcm, body_str(tcm));
  f = f + check("comma Transfer-Encoding rejected", is_reject(tcm_st), "status=" + tcm_st.to_str());
  f = f + check("comma Transfer-Encoding not chunked", !http.te_is_chunked(http.transfer_encoding_of(&te_comma, http.find_header_end(&te_comma))), "te_is_chunked=true");

  // Two TE fields where the first is chunked: the route must not accept the
  // request as chunked without reconciling the second field.
  let te_dup = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: identity\r\n\r\n1\r\nx\r\n0\r\n\r\n");
  let td = http.parse_request(&te_dup);
  let td_st = route_status("GET", "/health", &td, body_str(td));
  f = f + check("duplicate TE (chunked then identity) rejected", is_reject(td_st), "status=" + td_st.to_str() + " te_headers=" + header_count(td, "transfer-encoding").to_str());

  let te_dup2 = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: identity\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx\r\n0\r\n\r\n");
  let td2 = http.parse_request(&te_dup2);
  let td2_st = route_status("GET", "/health", &td2, body_str(td2));
  f = f + check("duplicate TE (identity then chunked) rejected", is_reject(td2_st), "status=" + td2_st.to_str());

  let te_space = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nTransfer-Encoding : chunked\r\n\r\n1\r\nx\r\n0\r\n\r\n");
  let tsp = http.parse_request(&te_space);
  f = f + check("whitespace before TE colon rejected", !tsp.ok, "accepted: te='" + http.header_get(&tsp, "transfer-encoding") + "'");

  // Valid, case-insensitive/OWS-padded single "chunked" must still work.
  let te_case = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: Chunked\r\n\r\n7\r\n{\"a\":1}\r\n0\r\n\r\n");
  let tcase = http.parse_request(&te_case);
  let tcase_st = route_status("POST", "/api/echo", &tcase, body_str(tcase));
  f = f + check("case-insensitive chunked accepted", tcase.ok && tcase_st == 200 && body_str(tcase) == "{\"a\":1}", "ok=" + tcase.ok.to_str() + " status=" + tcase_st.to_str() + " body=" + body_str(tcase));

  let te_ows = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding:   chunked \r\n\r\n7\r\n{\"a\":1}\r\n0\r\n\r\n");
  let tows = http.parse_request(&te_ows);
  f = f + check("OWS-padded chunked accepted", tows.ok && body_str(tows) == "{\"a\":1}", "ok=" + tows.ok.to_str() + " body=" + body_str(tows));

  // --- obsolete line folding / bare LF -------------------------------------
  let obs_fold = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: t\r\nX-Test: a\r\n b\r\n\r\n");
  f = f + check("obs-fold generic header rejected", !http.parse_request(&obs_fold).ok, "accepted");

  let obs_fold_te = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n chunked\r\n\r\n0\r\n\r\n");
  f = f + check("obs-fold TE rejected", !http.parse_request(&obs_fold_te).ok, "accepted");

  let bare_lf = http.str_to_bytes("GET /health HTTP/1.1\nHost: t\n\n");
  f = f + check("bare-LF head has no header terminator", http.find_header_end(&bare_lf) == -1, "find_header_end=" + http.find_header_end(&bare_lf).to_str());
  f = f + check("bare-LF head rejected", !http.parse_request(&bare_lf).ok, "accepted");

  // --- NUL in the request head (known upstream differential) ---------------
  // REL-20261106-1716-pulse: the parser truncates at NUL and can still
  // report ok=true. Station's empty method/target guard is tested below.
  let nul_method = with_nul("GE", "T /health HTTP/1.1\r\nHost: t\r\n\r\n");
  let nm = http.parse_request(&nul_method);
  if nm.ok {
    if strict_nul() {
      f = f + check("NUL in method rejected (strict)", false, "method='" + nm.method + "' target='" + nm.target + "'");
    } else {
      known("NUL in method truncates (method='" + nm.method + "')", "parser ok=true");
    }
  } else {
    // The upstream fix landed: the corpus expectation is now the strict one.
    io.println("[PASS] NUL in method rejected (upstream fixed)");
  }

  let nul_target = with_nul("GET /hea", "lth HTTP/1.1\r\nHost: t\r\n\r\n");
  let nt = http.parse_request(&nul_target);
  if nt.ok {
    if strict_nul() {
      f = f + check("NUL in target rejected (strict)", false, "target='" + nt.target + "'");
    } else {
      known("NUL in target truncates (target='" + nt.target + "')", "parser ok=true");
    }
  } else {
    io.println("[PASS] NUL in target rejected (upstream fixed)");
  }

  let nul_hval = with_nul("GET /health HTTP/1.1\r\nHost: t\r\nX-A: a", "b\r\n\r\n");
  let nh = http.parse_request(&nul_hval);
  if nh.ok {
    if strict_nul() {
      f = f + check("NUL in header value rejected (strict)", false, "x-a='" + http.header_get(&nh, "x-a") + "'");
    } else {
      known("NUL in header value truncates (x-a='" + http.header_get(&nh, "x-a") + "')", "parser ok=true");
    }
  } else {
    io.println("[PASS] NUL in header value rejected (upstream fixed)");
  }

  // Station defense in depth: a NUL that empties the method must yield 400,
  // never a site/404 miss.
  let nul_empty = with_nul("", "OST /health HTTP/1.1\r\nHost: t\r\n\r\n");
  let ne = http.parse_request(&nul_empty);
  let ne_st = route_status("", "/health", &ne, body_str(ne));
  f = f + check("NUL-empty method -> station 400", ne_st == 400, "status=" + ne_st.to_str());

  // --- chunked framing abuse ----------------------------------------------
  let ck_over = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFFFFFF\r\n");
  f = f + check("chunk size overflow rejected", !http.parse_request(&ck_over).ok, "accepted");

  let ck_over2 = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n7FFFFFFFFFFFFFFF\r\nAAAAAAAA\r\n");
  f = f + check("signed chunk size overflow rejected", !http.parse_request(&ck_over2).ok, "accepted");

  let ck_bad = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n");
  f = f + check("non-hex chunk size rejected", !http.parse_request(&ck_bad).ok, "accepted");

  // Trailers are metadata, never request headers: a trailer carrying a
  // quit header, Content-Length or another Transfer-Encoding must not affect
  // the request or the connection loop.
  let trailer = http.str_to_bytes("POST /api/echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n7\r\n{\"a\":1}\r\n0\r\nX-Pulse-Quit: 1\r\nContent-Length: 999\r\nTransfer-Encoding: chunked\r\n\r\n");
  let tr = http.parse_request(&trailer);
  f = f + check("trailer body decoded", tr.ok && body_str(tr) == "{\"a\":1}", "ok=" + tr.ok.to_str() + " body=" + body_str(tr));
  f = f + check("trailer quit not a request header", http.header_get(&tr, "x-pulse-quit") == "", "x-pulse-quit='" + http.header_get(&tr, "x-pulse-quit") + "'");
  f = f + check("trailer CL not a request header", http.header_get(&tr, "content-length") == "", "content-length='" + http.header_get(&tr, "content-length") + "'");
  f = f + check("trailer TE not a request header", header_count(tr, "transfer-encoding") == 1, "te_headers=" + header_count(tr, "transfer-encoding").to_str());

  // --- body cap boundary ---------------------------------------------------
  let cl_cap = http.str_to_bytes("POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 2000000\r\n\r\n");
  f = f + check("declared body over cap rejected", !http.parse_request(&cl_cap).ok, "accepted");

  if f == 0 {
    io.println("framing-tests: GREEN");
  } else {
    io.println("framing-tests: RED failures=" + f.to_str());
  }
  return f;
}
