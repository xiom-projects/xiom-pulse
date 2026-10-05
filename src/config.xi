// XIOM PULSE -- runtime configuration from environment.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All settings are env-overridable with safe defaults so the test scripts
// can run several instances (PULSE_PORT) and keep evidence in probe-logs.
module xiom.pulse.config

use xiom.env;

/// cfg_parse_port parses a decimal port, falling back to 8080.
/// Complexity: O(n). Pure.
fn cfg_parse_port(s: Str) -> Int {
  if s.len() == 0 { return 8080; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return 8080; }
    v = v * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  if v <= 0 || v > 65535 { return 8080; }
  return v;
}

/// cfg_port returns the listen port (PULSE_PORT, default 8080).
/// Complexity: O(1). Pure.
pub fn cfg_port() -> Int {
  return cfg_parse_port(env.var_or("PULSE_PORT", "8080"));
}

/// cfg_log_enabled is false when PULSE_LOG=0.
/// Complexity: O(1). Pure.
pub fn cfg_log_enabled() -> Bool {
  return env.var_or("PULSE_LOG", "1") != "0";
}

/// cfg_audit_path returns the audit log path (PULSE_AUDIT_PATH,
/// default "pulse-audit.log").
/// Complexity: O(1). Pure.
pub fn cfg_audit_path() -> Str {
  return env.var_or("PULSE_AUDIT_PATH", "pulse-audit.log");
}

/// cfg_jwt_secret returns the HS256 secret. The default is a DEV value;
/// set PULSE_JWT_SECRET in any real deployment.
/// Complexity: O(1). Pure.
pub fn cfg_jwt_secret() -> Str {
  return env.var_or("PULSE_JWT_SECRET", "dev-secret-change-me");
}

/// cfg_session_ttl_secs returns the session lifetime (PULSE_SESSION_TTL,
/// default 3600 seconds).
/// Complexity: O(n). Pure.
pub fn cfg_session_ttl_secs() -> Int {
  let s = env.var_or("PULSE_SESSION_TTL", "3600");
  if s.len() == 0 { return 3600; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return 3600; }
    v = v * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  if v <= 0 { return 3600; }
  return v;
}
