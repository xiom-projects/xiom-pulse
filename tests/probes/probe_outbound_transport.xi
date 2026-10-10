// probe_outbound_transport -- evidence-only REAL-libcurl check of the
// PULSE outbound seam. Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of the standard fleet: the probe calls the xiom.http client,
// which needs the 0.1.5 consumer recipe at build time:
//   xiom --run <this> --c-source <installed>\bridge\xiom_http_shims.c ^
//        --link curl --link-path <scratch-with-curl.lib>
// Run it through the twin runners instead:
//   scripts\outbound_transport_probe.ps1   (Windows)
//   bash scripts/outbound_transport_probe.sh   (Linux/WSL)
// The runner starts a PULSE server on PULSE_TRANSPORT_TEST_PORT and the
// probe fetches http://127.0.0.1:<port>/health through libcurl --
// guard first (loopback blocked), then the PULSE_HTTP_ALLOWLIST opt-in.
module pulse_probe_outbound_transport

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.pulse.outbound_transport;

var g_fails: Int = 0;

fn expect(name: Str, ok: Bool) {
  if ok {
    io.println("[PASS] " + name);
  } else {
    io.println("[FAIL] " + name);
    g_fails = g_fails + 1;
  }
}

pub fn main() -> Int {
  let port = env.var_or("PULSE_TRANSPORT_TEST_PORT", "18130");
  let url = "http://127.0.0.1:" + port + "/health";

  // Guard first: loopback is refused without the operator allowlist.
  env.remove_var("PULSE_HTTP_ALLOWLIST");
  let blocked = outbound_transport.outbound_get(url);
  expect("guard blocks loopback", !blocked.ok && string.str_contains(blocked.error, "blocked_by_ssrf_guard"));

  // Operator opt-in: the real client fetches the running PULSE server.
  env.set_var("PULSE_HTTP_ALLOWLIST", "127.0.0.1");
  let got = outbound_transport.outbound_get(url);
  expect("real GET ok", got.ok);
  expect("real GET status 200", got.ok && got.status == 200);
  expect("real GET body", got.ok && string.str_contains(got.body, "\"status\":\"ok\""));
  env.remove_var("PULSE_HTTP_ALLOWLIST");

  if g_fails == 0 {
    io.println("[PASS] probe_outbound_transport");
    return 0;
  }
  io.println("[FAIL] probe_outbound_transport fails=" + g_fails.to_str());
  return g_fails;
}
