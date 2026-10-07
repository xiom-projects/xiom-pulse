// probe_pkg_middleware -- registry-package consumption check:
// xiom.http.middleware 0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: scripts/run.sh tests\probes\probe_pkg_middleware.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_middleware

use xiom.http.middleware;
use xiom.string;
use xiom.io;

pub fn main() -> Int {
  var fails: Int = 0;

  // --- request ids ---------------------------------------------------------
  let ridr = middleware_request_id_new();
  if ridr.is_err {
    io.println("[FAIL] request id generation");
    fails = fails + 1;
  } else {
    let rid = ridr.value;
    if rid.len() != 32 {
      io.println("[FAIL] request id length");
      fails = fails + 1;
    }
    if !middleware_request_id_valid(rid) {
      io.println("[FAIL] request id valid");
      fails = fails + 1;
    } else {
      io.println("[PASS] request id");
    }
  }
  if middleware_request_id_valid("") {
    io.println("[FAIL] empty id must be invalid");
    fails = fails + 1;
  } else {
    io.println("[PASS] empty id invalid");
  }
  if middleware_request_id_valid("0123456789abcdef0123456789ABCDEF") {
    io.println("[FAIL] uppercase hex must be invalid");
    fails = fails + 1;
  } else {
    io.println("[PASS] uppercase hex invalid");
  }

  // --- CSRF ----------------------------------------------------------------
  let tr = middleware_csrf_token_new();
  if tr.is_err {
    io.println("[FAIL] csrf token generation");
    fails = fails + 1;
  } else {
    let tok = tr.value;
    if !middleware_csrf_valid(tok, tok) {
      io.println("[FAIL] csrf self-valid");
      fails = fails + 1;
    } else {
      io.println("[PASS] csrf self-valid");
    }
    if middleware_csrf_valid(tok, "x") {
      io.println("[FAIL] csrf mismatch accepted");
      fails = fails + 1;
    } else {
      io.println("[PASS] csrf mismatch rejected");
    }
    if middleware_csrf_valid("", tok) {
      io.println("[FAIL] empty csrf accepted");
      fails = fails + 1;
    } else {
      io.println("[PASS] empty csrf rejected");
    }
  }

  // --- CORS ----------------------------------------------------------------
  let hs = middleware_cors_headers("*", "GET, POST", "Content-Type", 600);
  if hs.len() != 4 {
    io.println("[FAIL] cors header count");
    fails = fails + 1;
  } else {
    io.println("[PASS] cors header count=4");
  }
  if hs.len() > 0 && !string.str_contains(hs[0], "Access-Control-Allow-Origin: *") {
    io.println("[FAIL] cors origin line");
    fails = fails + 1;
  } else {
    io.println("[PASS] cors origin line");
  }
  let hs0 = middleware_cors_headers("", "", "", 0);
  if hs0.len() != 0 {
    io.println("[FAIL] cors empty inputs must emit nothing");
    fails = fails + 1;
  } else {
    io.println("[PASS] cors empty inputs");
  }

  // --- access log line -----------------------------------------------------
  let line = middleware_access_log_line("abc", "GET", "/health", 200, 3, 15);
  if line != "request_id=abc method=GET path=/health status=200 duration_ms=3 bytes=15" {
    io.println("[FAIL] access log line: " + line);
    fails = fails + 1;
  } else {
    io.println("[PASS] access log line");
  }

  // --- error body ----------------------------------------------------------
  let eb = middleware_error_body(404, "nope");
  if !string.str_contains(eb, "\"message\":\"nope\"") {
    io.println("[FAIL] error body: " + eb);
    fails = fails + 1;
  } else {
    io.println("[PASS] error body");
  }
  let ct = middleware_error_content_type();
  if ct != "application/json" {
    io.println("[FAIL] error content type");
    fails = fails + 1;
  } else {
    io.println("[PASS] error content type");
  }

  if fails == 0 {
    io.println("[PASS] pkg-middleware");
    return 0;
  }
  io.println("[FAIL] pkg-middleware fails=" + fails.to_str());
  return fails;
}
