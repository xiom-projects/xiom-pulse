// probe_outbound_guard -- SSRF guard decisions for the outbound seam.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure half of the 0.2 outbound client (xiom.pulse.outbound): no libcurl
// link needed, runs in the standard fleet. Covers scheme policy, host
// extraction, the localhost suffix family, every inet_aton IPv4 bypass
// form, IPv6 loopback/ULA/link-local/v4-mapped, the PULSE_HTTP_ALLOWLIST
// switch and the response-size cap knob. Exit code = failure count.
//
// Run: .\scripts\run.ps1 tests\probes\probe_outbound_guard.xi
module pulse_probe_outbound_guard

use xiom.io;
use xiom.env;
use xiom.pulse.outbound;

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
  // --- scheme policy --------------------------------------------------------
  expect("http allowed", outbound.outbound_verdict("http://example.com/a").allowed);
  expect("https allowed", outbound.outbound_verdict("https://example.com/").allowed);
  expect("uppercase scheme allowed", outbound.outbound_verdict("HTTPS://example.com/").allowed);
  expect("ftp refused", outbound.outbound_verdict("ftp://example.com/").reason == "scheme_not_allowed");
  expect("file refused", outbound.outbound_verdict("file:///etc/passwd").reason == "scheme_not_allowed");
  expect("gopher refused", outbound.outbound_verdict("gopher://example.com/").reason == "scheme_not_allowed");
  expect("no-scheme refused", !outbound.outbound_verdict("example.com/x").allowed);

  // --- host extraction ------------------------------------------------------
  expect("host lowercased", outbound.outbound_verdict("https://API.Example.COM:8443/x").host == "api.example.com");
  expect("trailing dot normalized", outbound.outbound_verdict("http://example.com./x").host == "example.com");
  expect("userinfo refused", outbound.outbound_verdict("http://user@example.com/").reason == "userinfo_not_allowed");

  // --- local names ----------------------------------------------------------
  expect("localhost refused", outbound.outbound_verdict("http://localhost/x").reason == "private_host");
  expect("localhost port refused", outbound.outbound_verdict("http://localhost:8080/x").reason == "private_host");
  expect("sub.localhost refused", !outbound.outbound_verdict("http://a.localhost/x").allowed);
  expect("dot local refused", !outbound.outbound_verdict("http://printer.local/x").allowed);
  expect("dot internal refused", !outbound.outbound_verdict("http://metadata.google.internal/").allowed);
  expect("home.arpa refused", !outbound.outbound_verdict("http://router.home.arpa/").allowed);

  // --- IPv4 bypass forms (loopback) -----------------------------------------
  expect("127.0.0.1 refused", outbound.outbound_verdict("http://127.0.0.1/").reason == "private_address");
  expect("127.1 refused", outbound.outbound_verdict("http://127.1/").reason == "private_address");
  expect("decimal 2130706433 refused", outbound.outbound_verdict("http://2130706433/").reason == "private_address");
  expect("octal 0177.0.0.1 refused", outbound.outbound_verdict("http://0177.0.0.1/").reason == "private_address");
  expect("hex 0x7f.1 refused", outbound.outbound_verdict("http://0x7f.1/").reason == "private_address");

  // --- IPv4 private ranges --------------------------------------------------
  expect("10/8 refused", !outbound.outbound_verdict("http://10.1.2.3/").allowed);
  expect("172.16/12 refused", !outbound.outbound_verdict("http://172.20.0.1/").allowed);
  expect("192.168/16 refused", !outbound.outbound_verdict("http://192.168.1.1/").allowed);
  expect("CGNAT refused", !outbound.outbound_verdict("http://100.64.0.1/").allowed);
  expect("link-local refused", !outbound.outbound_verdict("http://169.254.169.254/latest/meta-data/").allowed);
  expect("wildcard refused", !outbound.outbound_verdict("http://0.0.0.0/").allowed);
  expect("multicast refused", !outbound.outbound_verdict("http://224.0.0.1/").allowed);
  expect("public ip allowed", outbound.outbound_verdict("http://93.184.216.34/").allowed);

  // --- IPv6 -----------------------------------------------------------------
  expect("v6 loopback refused", outbound.outbound_verdict("http://[::1]/").reason == "private_address");
  expect("v6 unspecified refused", !outbound.outbound_verdict("http://[::]/").allowed);
  expect("v6 ula refused", !outbound.outbound_verdict("http://[fd00::1]/").allowed);
  expect("v6 link-local refused", !outbound.outbound_verdict("http://[fe80::1]/").allowed);
  expect("v4-mapped loopback refused", !outbound.outbound_verdict("http://[::ffff:127.0.0.1]/").allowed);
  expect("bracketless v6 malformed", !outbound.outbound_verdict("http://2001:db8::1/").allowed);

  // --- allowlist mode (operator opt-in, wins over the blocklist) ------------
  env.set_var("PULSE_HTTP_ALLOWLIST", "api.example.com, 10.0.0.5");
  expect("allowlist exact", outbound.outbound_verdict("https://api.example.com/x").allowed);
  expect("allowlist subdomain", outbound.outbound_verdict("https://v2.api.example.com/x").allowed);
  expect("allowlist private opt-in", outbound.outbound_verdict("http://10.0.0.5/x").allowed);
  expect("allowlist blocks others", outbound.outbound_verdict("https://evil.test/x").reason == "not_in_allowlist");
  env.remove_var("PULSE_HTTP_ALLOWLIST");

  // --- response-size cap ----------------------------------------------------
  expect("max bytes default", outbound.outbound_max_bytes() == 262144);
  env.set_var("PULSE_HTTP_MAX_BYTES", "1024");
  expect("max bytes env", outbound.outbound_max_bytes() == 1024);
  env.set_var("PULSE_HTTP_MAX_BYTES", "junk");
  expect("max bytes junk fallback", outbound.outbound_max_bytes() == 262144);
  env.remove_var("PULSE_HTTP_MAX_BYTES");

  if g_fails == 0 {
    io.println("[PASS] probe_outbound_guard");
    return 0;
  }
  io.println("[FAIL] probe_outbound_guard fails=" + g_fails.to_str());
  return g_fails;
}
