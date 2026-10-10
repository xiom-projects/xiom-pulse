// probe_pkg_http -- registry-package consumption check: xiom.http.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// **GREEN again on v0.64.1 (2026-10-08):** the 0.1.1 package violated
// v0.64.1's extern-unsafe enforcement (67 T001s in its catalog body);
// 0.1.2 (eco-v0.1.103) wraps its internals in unsafe blocks, so this
// probe compiles and passes again and xiom.http is re-added to
// xiom.toml/package.xi (C-PULSE-13 stays routed to the compiler/installer
// lane; it was never a package defect).
//
// 2026-10-10 (later): pinned at **0.1.5** (eco-v0.1.125) -- ships the
// curl-free `bridge/xiom_http_shims.c` + the verified consumer recipe, so
// the REAL client is live: `scripts/outbound_transport_probe.{ps1,sh}`
// builds `probe_outbound_transport.xi` with
// `--c-source <installed>\bridge\xiom_http_shims.c --link curl
// --link-path <scratch>` and proves guard-block -> allowlist -> real GET
// 200 against a local PULSE server (GREEN on Windows + Linux; curl-for-win
// 8.22.0 / system libcurl). PULSE's guard half stays in
// `xiom.pulse.outbound` (`probe_outbound_guard` in the fleet); the libcurl
// seam is `src/outbound_transport.xi`.
//
// Consumes the installed registry package (no vendoring): parser + status.
// Run: .\scripts\run.ps1 tests\probes\probe_pkg_http.xi
module pulse_probe_pkg_http

// xiom.http v0.1.1 (hotfix): parser.xi now imports xiom.http.types itself
// and uses explicit deref for its cursor, so a consumer importing only
// xiom.http.parser compiles and parses. (The C-PULSE-04 compiler issue was
// the underlying cause; the package workaround landed in 0.1.1.)
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
