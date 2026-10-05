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

/// cfg_parse_uint parses a non-negative decimal, or returns fallback.
/// Complexity: O(n). Pure.
fn cfg_parse_uint(s: Str, fallback: Int) -> Int {
  if s.len() == 0 { return fallback; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return fallback; }
    v = v * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return v;
}

/// cfg_rate_limit returns the global requests/second cap
/// (PULSE_RATE_LIMIT, 0 = disabled).
/// Complexity: O(1). Pure.
pub fn cfg_rate_limit() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_RATE_LIMIT", "0"), 0);
}

/// cfg_rate_burst returns the token-bucket capacity
/// (PULSE_RATE_BURST, 0 = same as the rate).
/// Complexity: O(1). Pure.
pub fn cfg_rate_burst() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_RATE_BURST", "0"), 0);
}

/// cfg_cors_origin returns the allowed CORS origin ("" = CORS off).
/// Complexity: O(1). Pure.
pub fn cfg_cors_origin() -> Str {
  return env.var_or("PULSE_CORS_ORIGIN", "");
}

/// cfg_csrf_enabled is false when PULSE_CSRF=0 (enabled by default).
/// Complexity: O(1). Pure.
pub fn cfg_csrf_enabled() -> Bool {
  return env.var_or("PULSE_CSRF", "1") != "0";
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

/// cfg_store_path returns the JSONL event store path
/// (PULSE_STORE_PATH, default "pulse-events.jsonl").
/// Complexity: O(1). Pure.
pub fn cfg_store_path() -> Str {
  return env.var_or("PULSE_STORE_PATH", "pulse-events.jsonl");
}

/// cfg_icon_path returns the app icon path (PULSE_ICON_PATH, default
/// "resources/img/pulse-ico.ico").
/// Complexity: O(1). Pure.
pub fn cfg_icon_path() -> Str {
  return env.var_or("PULSE_ICON_PATH", "resources/img/pulse-ico.ico");
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
