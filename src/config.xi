// XIOM PULSE -- runtime configuration from environment.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All settings are env-overridable with safe defaults so the test scripts
// can run several instances (PULSE_PORT) and keep evidence in probe-logs.
module xiom.pulse.station.config

use xiom.env;
use xiom.io;
use xiom.convert;
use xiom.serialize.json;
use xiom.string;
use xiom.pulse.ratelimit;

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

/// cfg_rate_routes returns the per-route policy spec
/// (PULSE_RATE_ROUTES: `METHOD PATH=RATE[/BURST],...`; "" = off).
/// Complexity: O(1). Pure.
pub fn cfg_rate_routes() -> Str {
  return env.var_or("PULSE_RATE_ROUTES", "");
}

/// cfg_upload_dir returns the multipart upload directory
/// (PULSE_UPLOAD_DIR, default "uploads"). Complexity: O(1). Pure.
pub fn cfg_upload_dir() -> Str {
  return env.var_or("PULSE_UPLOAD_DIR", "uploads");
}

/// cfg_upload_max_bytes returns the per-part upload cap
/// (PULSE_UPLOAD_MAX_BYTES, default 1048576). Complexity: O(1). Pure.
pub fn cfg_upload_max_bytes() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_UPLOAD_MAX_BYTES", "1048576"), 1048576);
}

/// cfg_upload_max_parts returns the per-request part cap
/// (PULSE_UPLOAD_MAX_PARTS, default 8, clamped 1..64).
/// Complexity: O(1). Pure.
pub fn cfg_upload_max_parts() -> Int {
  var n: Int = cfg_parse_uint(env.var_or("PULSE_UPLOAD_MAX_PARTS", "8"), 8);
  if n < 1 { n = 1; }
  if n > 64 { n = 64; }
  return n;
}

/// cfg_upload_max_header_bytes returns the per-part header-block cap
/// (PULSE_UPLOAD_MAX_HEADER_BYTES, default 8192; 0/invalid falls back to
/// the default, values above 1 MiB are clamped). Exceeding it is a 413.
/// Complexity: O(1). Pure.
pub fn cfg_upload_max_header_bytes() -> Int {
  var n: Int = cfg_parse_uint(env.var_or("PULSE_UPLOAD_MAX_HEADER_BYTES", "8192"), 8192);
  if n < 1 { n = 8192; }
  if n > 1048576 { n = 1048576; }
  return n;
}

/// cfg_upload_allowed_exts returns the upload extension allowlist
/// (PULSE_UPLOAD_ALLOWED_EXTS, comma-separated; the LAST suffix is
/// matched lower-cased). Unknown extensions are rejected.
/// Complexity: O(1). Pure.
pub fn cfg_upload_allowed_exts() -> Str {
  return env.var_or("PULSE_UPLOAD_ALLOWED_EXTS", "txt,md,csv,json,png,jpg,jpeg,gif,webp,pdf,zip");
}

/// cfg_upload_allowed_mimes returns the upload media-type allowlist
/// (PULSE_UPLOAD_ALLOWED_MIMES, comma-separated; parameters are ignored).
/// Unknown/absent media types are rejected. Complexity: O(1). Pure.
pub fn cfg_upload_allowed_mimes() -> Str {
  return env.var_or("PULSE_UPLOAD_ALLOWED_MIMES", "text/plain,text/markdown,text/csv,application/json,image/png,image/jpeg,image/gif,image/webp,application/pdf,application/zip");
}

/// cfg_site_dir returns the static-site root (PULSE_SITE_DIR, "" = off).
/// When set, unmatched GET/HEAD requests and /assets/* serve from this
/// tree (clean URLs, index resolution, custom 404). Complexity: O(1).
pub fn cfg_site_dir() -> Str {
  return env.var_or("PULSE_SITE_DIR", "");
}

/// cfg_site_max_age returns the site Cache-Control max-age seconds
/// (PULSE_SITE_MAX_AGE, default 3600). Complexity: O(1). Pure.
pub fn cfg_site_max_age() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_SITE_MAX_AGE", "3600"), 3600);
}

/// cfg_read_timeout returns the full-request read deadline in ms
/// (PULSE_READ_TIMEOUT, default 30000; 0 = no deadline, dev only).
/// Complexity: O(1). Pure.
pub fn cfg_read_timeout() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_READ_TIMEOUT", "30000"), 30000);
}

/// cfg_write_timeout returns the response write deadline in ms
/// (PULSE_WRITE_TIMEOUT, default 30000; 0 = no deadline, dev only).
/// Complexity: O(1). Pure.
pub fn cfg_write_timeout() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_WRITE_TIMEOUT", "30000"), 30000);
}

/// cfg_idle_timeout returns the keep-alive idle deadline in ms
/// (PULSE_IDLE_TIMEOUT, default 5000; honored from keep-alive Phase B).
/// Complexity: O(1). Pure.
pub fn cfg_idle_timeout() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_IDLE_TIMEOUT", "5000"), 5000);
}

/// cfg_sql_dsn: PULSE_SQL_DSN (no default; SQL commands require it).
/// Complexity: O(1). Pure.
pub fn cfg_sql_dsn() -> Str {
  return env.var_or("PULSE_SQL_DSN", "");
}

/// cfg_sql_backup_manifest: PULSE_SQL_BACKUP_MANIFEST (no default) --
/// the last SQL backup manifest; `migrate up` refuses without a covering
/// one unless --no-backup-check.
/// Complexity: O(1). Pure.
pub fn cfg_sql_backup_manifest() -> Str {
  return env.var_or("PULSE_SQL_BACKUP_MANIFEST", "");
}

/// cfg_migrations_dir: PULSE_MIGRATIONS_DIR (default "migrations").
/// Complexity: O(1). Pure.
pub fn cfg_migrations_dir() -> Str {
  return env.var_or("PULSE_MIGRATIONS_DIR", "migrations");
}

/// cfg_migration_stale_secs: PULSE_MIGRATION_STALE_SECS (default 900) --
/// heartbeat age after which `migrate up` auto-breaks a crashed lock.
/// Complexity: O(1). Pure.
pub fn cfg_migration_stale_secs() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_MIGRATION_STALE_SECS", "900"), 900);
}

/// cfg_reuseport is true when PULSE_REUSEPORT=1 (default off). POSIX only;
/// Windows has no SO_REUSEPORT equivalent, so the bind falls back to the
/// N-ports baseline. Complexity: O(1). Pure.
pub fn cfg_reuseport() -> Bool {
  return env.var_or("PULSE_REUSEPORT", "0") == "1";
}

/// cfg_worker_id returns the worker label (PULSE_WORKER_ID, default 0) used
/// in startup logs and per-worker paths/metrics. Complexity: O(1). Pure.
pub fn cfg_worker_id() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_WORKER_ID", "0"), 0);
}

/// cfg_workers returns the supervisor child count (PULSE_WORKERS, default
/// 1). Values outside 1-64 fall back to 1 (the single-process path).
/// Complexity: O(1). Pure.
pub fn cfg_workers() -> Int {
  let n = cfg_parse_uint(env.var_or("PULSE_WORKERS", "1"), 1);
  if n < 1 || n > 64 { return 1; }
  return n;
}

/// cfg_worker_child is true when this process was spawned by the
/// supervisor (PULSE_WORKER_CHILD=1). Complexity: O(1). Pure.
pub fn cfg_worker_child() -> Bool {
  return env.var_or("PULSE_WORKER_CHILD", "0") == "1";
}

/// cfg_control_port returns the loopback control port (PULSE_CONTROL_PORT,
/// default 0 = disabled). Invalid or out-of-range values return 0.
/// Complexity: O(1). Pure.
pub fn cfg_control_port() -> Int {
  let p = cfg_parse_uint(env.var_or("PULSE_CONTROL_PORT", "0"), 0);
  if p < 1 || p > 65535 { return 0; }
  return p;
}

/// cfg_supervisor_control_port returns the supervisor's own loopback control
/// port (PULSE_SUPERVISOR_CONTROL_PORT, default 0 = derive from the child
/// control base as base - 1). Complexity: O(1). Pure.
pub fn cfg_supervisor_control_port() -> Int {
  let p = cfg_parse_uint(env.var_or("PULSE_SUPERVISOR_CONTROL_PORT", "0"), 0);
  if p < 1 || p > 65535 { return 0; }
  return p;
}

/// cfg_control_token returns the control-plane bearer token
/// (PULSE_CONTROL_TOKEN). Empty disables the control port (fail closed).
/// Complexity: O(1). Pure.
pub fn cfg_control_token() -> Str {
  return env.var_or("PULSE_CONTROL_TOKEN", "");
}

/// cfg_drain_timeout_ms returns the drain deadline
/// (PULSE_DRAIN_TIMEOUT_MS, default 10000; non-positive falls back).
/// Complexity: O(1). Pure.
pub fn cfg_drain_timeout_ms() -> Int {
  let ms = cfg_parse_uint(env.var_or("PULSE_DRAIN_TIMEOUT_MS", "10000"), 10000);
  if ms < 1 { return 10000; }
  return ms;
}

/// cfg_legacy_loop: PULSE_LEGACY_LOOP (default "0") -- "1" keeps the
/// product accept loop for the Phase B rollback window; the default uses
/// the Beacon serve_with_ctx loop + stateful hooks.
/// Complexity: O(1). Pure.
pub fn cfg_legacy_loop() -> Bool {
  return env.var_or("PULSE_LEGACY_LOOP", "0") == "1";
}

/// cfg_keepalive is false when PULSE_KEEPALIVE=0 (connection reuse is on
/// by default once Phase B landed; 0 restores close-per-request).
/// Complexity: O(1). Pure.
pub fn cfg_keepalive() -> Bool {
  return env.var_or("PULSE_KEEPALIVE", "1") != "0";
}

/// cfg_store_sync: PULSE_STORE_SYNC (default "1") -- fsync the store append
/// before acknowledging it (durability Phase A, DESIGN-STORE-DURABILITY P1).
/// "0" is the documented healing-only mode (crash-safe reopen, not durable).
/// Complexity: O(1). Pure.
pub fn cfg_store_sync() -> Bool {
  return env.var_or("PULSE_STORE_SYNC", "1") != "0";
}

/// cfg_audit_sync: PULSE_AUDIT_SYNC (default "1") -- fsync the audit append
/// before returning from the mutating request path (security-relevant).
/// Complexity: O(1). Pure.
pub fn cfg_audit_sync() -> Bool {
  return env.var_or("PULSE_AUDIT_SYNC", "1") != "0";
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
  cfg_apply_str(obj, "reuseport", "PULSE_REUSEPORT");
  cfg_apply_str(obj, "worker_id", "PULSE_WORKER_ID");
  cfg_apply_str(obj, "workers", "PULSE_WORKERS");
  cfg_apply_str(obj, "worker_child", "PULSE_WORKER_CHILD");
  cfg_apply_str(obj, "control_port", "PULSE_CONTROL_PORT");
  cfg_apply_str(obj, "supervisor_control_port", "PULSE_SUPERVISOR_CONTROL_PORT");
  cfg_apply_str(obj, "control_token", "PULSE_CONTROL_TOKEN");
  cfg_apply_str(obj, "drain_timeout_ms", "PULSE_DRAIN_TIMEOUT_MS");
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
  cfg_apply_str(obj, "rate_routes", "PULSE_RATE_ROUTES");
  cfg_apply_str(obj, "cors_origin", "PULSE_CORS_ORIGIN");
  cfg_apply_str(obj, "csrf", "PULSE_CSRF");
  cfg_apply_str(obj, "store_backend", "PULSE_STORE_BACKEND");
  cfg_apply_str(obj, "kv_dir", "PULSE_KV_DIR");
  cfg_apply_str(obj, "kv_prefix", "PULSE_KV_PREFIX");
  cfg_apply_str(obj, "upload_dir", "PULSE_UPLOAD_DIR");
  cfg_apply_str(obj, "upload_max_bytes", "PULSE_UPLOAD_MAX_BYTES");
  cfg_apply_str(obj, "upload_max_parts", "PULSE_UPLOAD_MAX_PARTS");
  cfg_apply_str(obj, "upload_max_header_bytes", "PULSE_UPLOAD_MAX_HEADER_BYTES");
  cfg_apply_str(obj, "upload_allowed_exts", "PULSE_UPLOAD_ALLOWED_EXTS");
  cfg_apply_str(obj, "upload_allowed_mimes", "PULSE_UPLOAD_ALLOWED_MIMES");
  cfg_apply_str(obj, "http_allowlist", "PULSE_HTTP_ALLOWLIST");
  cfg_apply_str(obj, "http_max_bytes", "PULSE_HTTP_MAX_BYTES");
  cfg_apply_str(obj, "site_dir", "PULSE_SITE_DIR");
  cfg_apply_str(obj, "site_max_age", "PULSE_SITE_MAX_AGE");
  cfg_apply_str(obj, "csp", "PULSE_CSP");
  cfg_apply_str(obj, "game_path", "PULSE_GAME_PATH");
  cfg_apply_str(obj, "game_config_path", "PULSE_GAME_CONFIG_PATH");
  cfg_apply_str(obj, "game_heartbeat_secs", "PULSE_GAME_HEARTBEAT_SECS");
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

/// cfg_store_backend returns the event-store backend: "jsonl" (default)
/// or "kv" (xiom.kv; PULSE_STORE_BACKEND, plus PULSE_KV_DIR /
/// PULSE_KV_PREFIX).
/// Complexity: O(1). Pure.
pub fn cfg_store_backend() -> Str {
  return env.var_or("PULSE_STORE_BACKEND", "jsonl");
}

/// cfg_jwt_secret returns the HS256 secret. The default is a DEV value;
/// set PULSE_JWT_SECRET in any real deployment.
/// Complexity: O(1). Pure.
pub fn cfg_jwt_secret() -> Str {
  return env.var_or("PULSE_JWT_SECRET", "dev-secret-change-me");
}

/// cfg_ws_auth returns the configured stream-route auth policy as written
/// (PULSE_WS_AUTH, default "off"); station.wsauth normalizes it and fails
/// closed on unknown values. Complexity: O(1). Pure.
pub fn cfg_ws_auth() -> Str {
  return env.var_or("PULSE_WS_AUTH", "off");
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

/// cfg_openapi_path returns the served OpenAPI document path
/// (PULSE_OPENAPI_PATH, default "resources/openapi.json").
/// Complexity: O(1). Pure.
pub fn cfg_openapi_path() -> Str {
  return env.var_or("PULSE_OPENAPI_PATH", "resources/openapi.json");
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

/// cfg_csp returns the Content-Security-Policy header value to send
/// (PULSE_CSP, default "" = no CSP header: site mode serves pre-built
/// trees whose inline scripts a strict default policy would break; set a
/// policy string to enable it, e.g. "default-src 'self'").
/// Complexity: O(1). Pure.
pub fn cfg_csp() -> Str {
  return env.var_or("PULSE_CSP", "");
}

/// cfg_game_path returns the game control-plane record file
/// (PULSE_GAME_PATH, default "pulse-game.jsonl"). Complexity: O(1).
pub fn cfg_game_path() -> Str {
  return env.var_or("PULSE_GAME_PATH", "pulse-game.jsonl");
}

/// cfg_game_config_path returns the game config document path
/// (PULSE_GAME_CONFIG_PATH, default "pulse-game-config.json").
/// Complexity: O(1). Pure.
pub fn cfg_game_config_path() -> Str {
  return env.var_or("PULSE_GAME_CONFIG_PATH", "pulse-game-config.json");
}

/// cfg_game_heartbeat_secs returns the advertised heartbeat cadence
/// (PULSE_GAME_HEARTBEAT_SECS, default 15). Complexity: O(1). Pure.
pub fn cfg_game_heartbeat_secs() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_GAME_HEARTBEAT_SECS", "15"), 15);
}

/// cfg_game_admin_token returns the ops token gating
/// /api/game/admin/command (PULSE_GAME_ADMIN_TOKEN, default "" =
/// admin disabled). Complexity: O(1). Pure.
pub fn cfg_game_admin_token() -> Str {
  return env.var_or("PULSE_GAME_ADMIN_TOKEN", "");
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

/// cfg_digit_value parses a decimal uint with an overflow guard; -1 when
/// empty, non-numeric, or too large. Complexity: O(n). Pure.
fn cfg_digit_value(s: Str) -> Int {
  if s.len() == 0 { return -1; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return -1; }
    v = v * 10 + ((b as Int) - 48);
    if v > 100000000 { return -1; }
    i = i + 1;
  }
  return v;
}

/// cfg_digits_at is true when s[start..] is non-empty and all ASCII
/// digits. Complexity: O(n). Pure.
fn cfg_digits_at(s: Str, start: Int) -> Bool {
  if start >= s.len() { return false; }
  var i: Int = start;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return false; }
    i = i + 1;
  }
  return true;
}

/// cfg_bind_has_port is true for `host:port` and `[v6]:port` shapes, i.e.
/// PULSE_BIND values that embed a port (bare IPv6 literals like `::1` are
/// not flagged). Complexity: O(n). Pure.
fn cfg_bind_has_port(s: Str) -> Bool {
  if s.len() == 0 { return false; }
  if s.byte_at(0) == 91u8 {
    var i: Int = 0;
    while i + 1 < s.len() {
      if s.byte_at(i) == 93u8 && s.byte_at(i + 1) == 58u8 {
        return cfg_digits_at(s, i + 2);
      }
      i = i + 1;
    }
    return false;
  }
  var colons: Int = 0;
  var colon_at: Int = -1;
  var j: Int = 0;
  while j < s.len() {
    if s.byte_at(j) == 58u8 {
      colons = colons + 1;
      colon_at = j;
    }
    j = j + 1;
  }
  if colons == 1 {
    return cfg_digits_at(s, colon_at + 1);
  }
  return false;
}

/// cfg_ext_token_valid is true for one 1-8 char ASCII alnum extension
/// token (an optional leading dot is accepted). Complexity: O(n). Pure.
fn cfg_ext_token_valid(tok: Str) -> Bool {
  var t = string.str_lower(string.str_trim(tok));
  if t.len() == 0 { return false; }
  var i: Int = 0;
  if t.byte_at(0) == 46u8 { i = 1; }
  var n: Int = 0;
  while i < t.len() {
    let b = t.byte_at(i);
    let alnum = (b >= 48u8 && b <= 57u8) || (b >= 97u8 && b <= 122u8);
    if !alnum { return false; }
    n = n + 1;
    i = i + 1;
  }
  return n >= 1 && n <= 8;
}

/// cfg_mime_token_valid is true for a `type/subtype` media-type token with
/// no whitespace/parameters. Complexity: O(n). Pure.
fn cfg_mime_token_valid(tok: Str) -> Bool {
  let t = string.str_trim(tok);
  if t.len() == 0 { return false; }
  let slash = string.str_index_of(t, "/");
  if slash.is_none { return false; }
  let sl = slash.value;
  if sl == 0 || sl + 1 >= t.len() { return false; }
  var i: Int = 0;
  while i < t.len() {
    let b = t.byte_at(i);
    if b == 32u8 || b == 9u8 || b == 59u8 { return false; }
    i = i + 1;
  }
  return string.str_index_of(string.str_slice(t, sl + 1, t.len()), "/").is_none;
}

fn cfg_csv_bad_token(csv: Str, is_ext: Bool) -> Str {
  let items = string.str_split(csv, ",");
  var i: Int = 0;
  while i < items.len() {
    let tok = string.str_trim(items[i]);
    var ok: Bool = false;
    if is_ext {
      ok = cfg_ext_token_valid(tok);
    } else {
      ok = cfg_mime_token_valid(tok);
    }
    if !ok { return tok; }
    i = i + 1;
  }
  return "";
}

/// cfg_validate returns human-readable warnings for set-but-invalid
/// values (invalid values silently fall back to defaults, so surface them
/// once at startup and in --check-config). Empty vector = all good.
/// Complexity: O(settings). Pure.
pub fn cfg_validate() -> Vec[Str] {
  var w: Vec[Str] = Vec[Str].new();

  let port = env.var_or("PULSE_PORT", "");
  if port.len() > 0 {
    let pv = cfg_digit_value(port);
    if pv < 1 || pv > 65535 {
      w.push("PULSE_PORT=\"" + port + "\" is not a valid port (1-65535); using 8080");
    }
  }

  let bind = env.var_or("PULSE_BIND", "");
  if bind.len() > 0 && cfg_bind_has_port(bind) {
    w.push("PULSE_BIND=\"" + bind + "\" looks like address:port; set PULSE_BIND to the address only and put the port in PULSE_PORT");
  }

  let rl = env.var_or("PULSE_RATE_LIMIT", "");
  if rl.len() > 0 && cfg_digit_value(rl) < 0 {
    w.push("PULSE_RATE_LIMIT=\"" + rl + "\" is not a non-negative integer; using 0");
  }
  let rb = env.var_or("PULSE_RATE_BURST", "");
  if rb.len() > 0 && cfg_digit_value(rb) < 0 {
    w.push("PULSE_RATE_BURST=\"" + rb + "\" is not a non-negative integer; using 0");
  }
  let rr = env.var_or("PULSE_RATE_ROUTES", "");
  if rr.len() > 0 {
    let rre = ratelimit.route_rates_spec_error(rr);
    if rre.len() > 0 { w.push("PULSE_RATE_ROUTES: " + rre); }
  }
  let amb = env.var_or("PULSE_AUDIT_MAX_BYTES", "");
  if amb.len() > 0 && cfg_digit_value(amb) < 0 {
    w.push("PULSE_AUDIT_MAX_BYTES=\"" + amb + "\" is not a non-negative integer; using 5000000");
  }
  let ttl = env.var_or("PULSE_SESSION_TTL", "");
  if ttl.len() > 0 {
    let tv = cfg_digit_value(ttl);
    if tv < 1 {
      w.push("PULSE_SESSION_TTL=\"" + ttl + "\" is not a positive integer; using 3600");
    }
  }

  let csrf = env.var_or("PULSE_CSRF", "");
  if csrf.len() > 0 && csrf != "0" && csrf != "1" {
    w.push("PULSE_CSRF=\"" + csrf + "\" is not 0 or 1; treating as enabled");
  }
  let logv = env.var_or("PULSE_LOG", "");
  if logv.len() > 0 && logv != "0" && logv != "1" {
    w.push("PULSE_LOG=\"" + logv + "\" is not 0 or 1; treating as enabled");
  }

  let backend = env.var_or("PULSE_STORE_BACKEND", "");
  if backend.len() > 0 && backend != "jsonl" && backend != "kv" {
    w.push("PULSE_STORE_BACKEND=\"" + backend + "\" is not jsonl or kv; using jsonl");
  }

  let rt = env.var_or("PULSE_READ_TIMEOUT", "");
  if rt.len() > 0 {
    let rv = cfg_digit_value(rt);
    if rv < 0 {
      w.push("PULSE_READ_TIMEOUT=\"" + rt + "\" is not a non-negative integer; using 30000");
    } else if rv == 0 {
      w.push("PULSE_READ_TIMEOUT=0 disables the read deadline (slowloris risk; dev only)");
    }
  }
  let wt = env.var_or("PULSE_WRITE_TIMEOUT", "");
  if wt.len() > 0 {
    let wv = cfg_digit_value(wt);
    if wv < 0 {
      w.push("PULSE_WRITE_TIMEOUT=\"" + wt + "\" is not a non-negative integer; using 30000");
    } else if wv == 0 {
      w.push("PULSE_WRITE_TIMEOUT=0 disables the write deadline (stalled-reader risk; dev only)");
    }
  }
  let ito = env.var_or("PULSE_IDLE_TIMEOUT", "");
  if ito.len() > 0 {
    let iv = cfg_digit_value(ito);
    if iv < 0 {
      w.push("PULSE_IDLE_TIMEOUT=\"" + ito + "\" is not a non-negative integer; using 5000");
    }
  }
  let ka = env.var_or("PULSE_KEEPALIVE", "");
  if ka.len() > 0 && ka != "0" && ka != "1" {
    w.push("PULSE_KEEPALIVE=\"" + ka + "\" is not 0 or 1; treating as enabled");
  }
  let wsa = env.var_or("PULSE_WS_AUTH", "");
  if wsa.len() > 0 {
    let wl = string.str_lower(string.str_trim(wsa));
    let known = wl == "off" || wl == "0" || wl == "false" || wl == "jwt" || wl == "bearer" || wl == "session" || wl == "cookie";
    if !known {
      w.push("PULSE_WS_AUTH=\"" + wsa + "\" is not off|jwt|session; stream routes will reject (fail closed)");
    } else if (wl == "jwt" || wl == "bearer") && env.var_or("PULSE_JWT_SECRET", "").len() == 0 {
      w.push("PULSE_WS_AUTH=jwt without PULSE_JWT_SECRET; stream routes will reject (the dev default secret is refused)");
    }
  }
  let ss = env.var_or("PULSE_STORE_SYNC", "");
  if ss == "0" {
    w.push("PULSE_STORE_SYNC=0: store appends are acknowledged without fsync (healing-only; a crash may lose the unsynced tail)");
  }
  let asy = env.var_or("PULSE_AUDIT_SYNC", "");
  if asy == "0" {
    w.push("PULSE_AUDIT_SYNC=0: audit appends are not fsynced before the response");
  }
  let rp = env.var_or("PULSE_REUSEPORT", "");
  if rp.len() > 0 && rp != "0" && rp != "1" {
    w.push("PULSE_REUSEPORT=\"" + rp + "\" is not 0 or 1; treating as disabled");
  }
  let wid = env.var_or("PULSE_WORKER_ID", "");
  if wid.len() > 0 && cfg_digit_value(wid) < 0 {
    w.push("PULSE_WORKER_ID=\"" + wid + "\" is not a non-negative integer; using 0");
  }
  let wkr = env.var_or("PULSE_WORKERS", "");
  if wkr.len() > 0 {
    let v = cfg_digit_value(wkr);
    if v < 1 || v > 64 {
      w.push("PULSE_WORKERS=\"" + wkr + "\" is outside 1-64; using 1");
    }
  }
  let wch = env.var_or("PULSE_WORKER_CHILD", "");
  if wch.len() > 0 && wch != "0" && wch != "1" {
    w.push("PULSE_WORKER_CHILD=\"" + wch + "\" is not 0 or 1; treating as 0");
  }
  let ctlp = env.var_or("PULSE_CONTROL_PORT", "");
  if ctlp.len() > 0 {
    let v = cfg_digit_value(ctlp);
    if v < 0 || v > 65535 {
      w.push("PULSE_CONTROL_PORT=\"" + ctlp + "\" is not a valid port (0-65535); control disabled");
    } else if v > 0 && env.var_or("PULSE_CONTROL_TOKEN", "").len() == 0 {
      w.push("PULSE_CONTROL_PORT is set without PULSE_CONTROL_TOKEN; control disabled (fail closed)");
    }
  }
  let drt = env.var_or("PULSE_DRAIN_TIMEOUT_MS", "");
  if drt.len() > 0 && cfg_digit_value(drt) < 1 {
    w.push("PULSE_DRAIN_TIMEOUT_MS=\"" + drt + "\" is not a positive integer; using 10000");
  }

  let umb = env.var_or("PULSE_UPLOAD_MAX_BYTES", "");
  if umb.len() > 0 && cfg_digit_value(umb) < 1 {
    w.push("PULSE_UPLOAD_MAX_BYTES=\"" + umb + "\" is not a positive integer; using 1048576");
  }
  let ump = env.var_or("PULSE_UPLOAD_MAX_PARTS", "");
  if ump.len() > 0 {
    let v = cfg_digit_value(ump);
    if v < 1 || v > 64 {
      w.push("PULSE_UPLOAD_MAX_PARTS=\"" + ump + "\" is outside 1-64; clamping");
    }
  }
  let umh = env.var_or("PULSE_UPLOAD_MAX_HEADER_BYTES", "");
  if umh.len() > 0 {
    let v = cfg_digit_value(umh);
    if v < 1 {
      w.push("PULSE_UPLOAD_MAX_HEADER_BYTES=\"" + umh + "\" is not a positive integer; using 8192");
    } else if v > 1048576 {
      w.push("PULSE_UPLOAD_MAX_HEADER_BYTES=\"" + umh + "\" exceeds 1 MiB; clamping");
    }
  }
  let uae = env.var_or("PULSE_UPLOAD_ALLOWED_EXTS", "");
  if uae.len() > 0 {
    let bad = cfg_csv_bad_token(uae, true);
    if bad.len() > 0 || string.str_split(uae, ",").len() == 0 {
      w.push("PULSE_UPLOAD_ALLOWED_EXTS contains invalid extension \"" + bad + "\"; entries must be 1-8 ASCII letters/digits");
    }
  }
  let uam = env.var_or("PULSE_UPLOAD_ALLOWED_MIMES", "");
  if uam.len() > 0 {
    let bad = cfg_csv_bad_token(uam, false);
    if bad.len() > 0 || string.str_split(uam, ",").len() == 0 {
      w.push("PULSE_UPLOAD_ALLOWED_MIMES contains invalid media type \"" + bad + "\"; entries must be type/subtype");
    }
  }

  return w;
}
