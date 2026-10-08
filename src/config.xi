// XIOM PULSE -- runtime configuration from environment.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All settings are env-overridable with safe defaults so the test scripts
// can run several instances (PULSE_PORT) and keep evidence in probe-logs.
module xiom.pulse.config

use xiom.env;
use xiom.io;
use xiom.convert;
use xiom.serialize.json;

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

/// cfg_config_path returns PULSE_CONFIG ("" = no file).
/// Complexity: O(1). Pure.
pub fn cfg_config_path() -> Str {
  return env.var_or("PULSE_CONFIG", "");
}

fn cfg_apply_str(obj: JsonValue, key: Str, env_name: Str) {
  let opt = json.json_get(obj, key);
  if opt.is_none { return; }
  let v = opt.value;
  match v {
    JsonValue.String(s) => {
      let sv = s;
      env.set_var_if_absent(env_name, sv);
    },
    JsonValue.Number(f) => {
      env.set_var_if_absent(env_name, convert.float_to_int(f).to_str());
    },
    JsonValue.Bool(b) => {
      if b {
        env.set_var_if_absent(env_name, "1");
      } else {
        env.set_var_if_absent(env_name, "0");
      }
    },
    _ => {},
  }
}

/// cfg_load_file loads PULSE_CONFIG (a JSON object) into the environment
/// without overriding already-set variables. Returns false when a
/// configured file is unreadable or not a JSON object.
/// Complexity: O(file).
pub fn cfg_load_file() -> Bool {
  let path = cfg_config_path();
  if path.len() == 0 { return true; }
  let rf = io.read_file(path);
  if rf.is_err { return false; }
  let pv = json.json_parse(rf.value);
  if pv.is_err { return false; }
  if json.json_type(pv.value) != "object" { return false; }
  let obj = pv.value;
  cfg_apply_str(obj, "port", "PULSE_PORT");
  cfg_apply_str(obj, "bind", "PULSE_BIND");
  cfg_apply_str(obj, "log", "PULSE_LOG");
  cfg_apply_str(obj, "store_path", "PULSE_STORE_PATH");
  cfg_apply_str(obj, "audit_path", "PULSE_AUDIT_PATH");
  cfg_apply_str(obj, "audit_max_bytes", "PULSE_AUDIT_MAX_BYTES");
  cfg_apply_str(obj, "jwt_secret", "PULSE_JWT_SECRET");
  cfg_apply_str(obj, "session_ttl", "PULSE_SESSION_TTL");
  cfg_apply_str(obj, "icon_path", "PULSE_ICON_PATH");
  cfg_apply_str(obj, "static_dir", "PULSE_STATIC_DIR");
  cfg_apply_str(obj, "assets_dir", "PULSE_ASSETS_DIR");
  cfg_apply_str(obj, "landing_path", "PULSE_LANDING_PATH");
  cfg_apply_str(obj, "rate_limit", "PULSE_RATE_LIMIT");
  cfg_apply_str(obj, "rate_burst", "PULSE_RATE_BURST");
  cfg_apply_str(obj, "cors_origin", "PULSE_CORS_ORIGIN");
  cfg_apply_str(obj, "csrf", "PULSE_CSRF");
  return true;
}

/// cfg_port returns the listen port (PULSE_PORT, default 8080).
/// Complexity: O(1). Pure.
pub fn cfg_port() -> Int {
  return cfg_parse_port(env.var_or("PULSE_PORT", "8080"));
}

/// cfg_bind returns the listen address (PULSE_BIND, default "127.0.0.1").
/// Keep the loopback default for host deployments behind a proxy (ops
/// requirement: the public surface stays 443-only); containers and the
/// benchmark harness may set 0.0.0.0 because the container network is the
/// isolation boundary there.
/// Complexity: O(1). Pure.
pub fn cfg_bind() -> Str {
  return env.var_or("PULSE_BIND", "127.0.0.1");
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

/// cfg_audit_max_bytes returns the audit-log rotation threshold in bytes
/// (PULSE_AUDIT_MAX_BYTES, default 5000000; 0 disables rotation).
/// Complexity: O(n). Pure.
pub fn cfg_audit_max_bytes() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_AUDIT_MAX_BYTES", "5000000"), 5000000);
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

/// cfg_static_dir returns the static-assets root served by the /favicon.ico
/// route (PULSE_STATIC_DIR, default "resources/img").
/// Complexity: O(1). Pure.
pub fn cfg_static_dir() -> Str {
  return env.var_or("PULSE_STATIC_DIR", "resources/img");
}

/// cfg_assets_dir returns the root served under /assets/ for showcase
/// sites (PULSE_ASSETS_DIR, default "resources/public").
/// Complexity: O(1). Pure.
pub fn cfg_assets_dir() -> Str {
  return env.var_or("PULSE_ASSETS_DIR", "resources/public");
}

/// cfg_landing_path returns an optional HTML file served at "/"
/// (PULSE_LANDING_PATH, default "" = the built-in placeholder page).
/// Complexity: O(1). Pure.
pub fn cfg_landing_path() -> Str {
  return env.var_or("PULSE_LANDING_PATH", "");
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
