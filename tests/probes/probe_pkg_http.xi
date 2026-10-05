// probe_pkg_http -- registry-package consumption check: xiom.http v0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Consumes the installed registry package (no vendoring): parser + status.
// Run: .\scripts\run.ps1 tests\probes\probe_pkg_http.xi
module pulse_probe_pkg_http

// NOTE: xiom.http.parser v0.1.0 references HttpRequest/HttpMethod/HttpHeaders
// and method_from_str from xiom.http.types WITHOUT `use xiom.http.types;`.
// A consumer must load that module explicitly (see C-PULSE-03 in SESSION.md).
use xiom.http.types;
use xiom.http.parser;
use xiom.http.status;
use xiom.io;

fn main() -> Int {
  var fails: Int = 0;

  let input: Str = "POST /api/echo HTTP/1.1\r\nHost: example\r\nContent-Length: 7\r\n\r\n{\"a\":1}";
  let pr = http_parse_request(input);
  if pr.is_err {
    match pr {
      Err(e) => { io.println("pkg-http parse err: " + e.message + " pos=" + e.position.to_str()); },
      Ok(_) => {},
    }
    io.println("[FAIL] pkg-http parse");
    return 1;
  }
  let req = pr.value;
  io.println("pkg-http path=" + req.path + " bodylen=" + req.body.len().to_str());

  if req.path != "/api/echo" { fails = fails + 1; }
  if req.body.len() != 7 { fails = fails + 1; }
  if http_status_text(404) != "Not Found" { fails = fails + 1; }
  if !http_is_success(200) { fails = fails + 1; }
  if !http_is_client_error(404) { fails = fails + 1; }

  if fails == 0 {
    io.println("[PASS] pkg-http");
    return 0;
  }
  io.println("[FAIL] pkg-http fails=" + fails.to_str());
  return fails;
}
