// XIOM PULSE -- HTTP/1.1 server loop, routing and app-skeleton wiring.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Single-threaded sequential-accept server (pin: no select/threads/timeouts).
// Reads go through the raw fd socket API because C-PULSE-01 disables one-arg
// `.read(...)` methods. TLS is terminated by the front proxy.
//
// Step 2 features: router, uniform error envelope, config, structured access
// log, metrics endpoint, audit trail, cookie sessions, JWT HS256.
//
// Build: .\scripts\build.ps1 src\server.xi -Name pulse_app
// Quit:  send any request with header `X-Pulse-Quit: 1`
//
// Module name note (2026-10-08): renamed from xiom.pulse.server to
// xiom.pulse.app -- a module whose last segment is `server` shadows the
// stdlib alias `server` (xiom.net.server) in every compilation that
// includes it, which broke src/http.xi's stdlib parser import.
module xiom.pulse.app

use xiom.net.socket;
use xiom.net;
use xiom.io;
use xiom.time;
use xiom.string;
use xiom.convert;
use xiom.serialize.json;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.envelope;
use xiom.pulse.config;
use xiom.pulse.metrics;
use xiom.pulse.sessions;
use xiom.jwt;
use xiom.string.slice;
use xiom.pulse.store;
use xiom.pulse.ratelimit;
use xiom.pulse.cors;
use xiom.pulse.validate;
use xiom.pulse.schema;
use xiom.pulse.reqctx;
use xiom.convert.parse;
use xiom.static;
use xiom.env;
use xiom.pulse.audit;

const MAX_BODY: Int = 1048576;
const CONTENT_JSON: Str = "application/json; charset=utf-8";
const CONTENT_TEXT: Str = "text/plain; charset=utf-8";
// Keep in sync with src/pulse.xi pulse_version(). Not imported here: the
// `pulse` alias resolves to the xiom.pulse.* family namespace inside this
// compilation (same shadowing class as C-PULSE-12), so the alias call
// cannot be used from a xiom.pulse.* module.
const APP_VERSION: Str = "0.1.0";

var req_counter: Int = 0;
var icon_bytes: Vec[UInt8] = Vec[UInt8].new();
var icon_loaded: Bool = false;

fn next_rid() -> Str {
  req_counter = req_counter + 1;
  return "r-" + req_counter.to_str();
}

/// load_icon reads the app icon (ICO) into memory for /favicon.ico.
/// Complexity: O(size).
pub fn load_icon(path: Str) -> Bool {
  let r = io.read_file_bytes(path);
  if r.is_err {
    icon_loaded = false;
    return false;
  }
  icon_bytes = r.value;
  icon_loaded = icon_bytes.len() > 0;
  return icon_loaded;
}

/// HandlerOut - one dispatched response. When `body_bytes` is non-empty the
/// response is sent as raw bytes (icons/assets); otherwise `body` is text.
pub type HandlerOut = {
  status: Int;
  content_type: Str;
  headers: Vec[(Str, Str)];
  body: Str;
  body_bytes: Vec[UInt8];
}

fn out_json(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_JSON; headers: Vec[(Str, Str)].new(); body: body; body_bytes: Vec[UInt8].new(); };
}

fn out_text(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_TEXT; headers: Vec[(Str, Str)].new(); body: body; body_bytes: Vec[UInt8].new(); };
}

fn out_html(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: "text/html; charset=utf-8"; headers: Vec[(Str, Str)].new(); body: body; body_bytes: Vec[UInt8].new(); };
}

fn json_ok_field(key: Str, value: Str) -> Str {
  let v = json.json_set(json.json_object_new(), key, json.json_string(value));
  return json.json_stringify(v);
}

/// serve_static_file serves one file from `dir` via registry xiom.static
/// (ETag/Last-Modified/Cache-Control, 304 on If-None-Match, 206/416 on
/// Range, traversal guard); a 404 becomes the JSON error envelope.
/// Complexity: O(file).
fn serve_static_file(dir: Str, rel: Str, req: &PulseRequest, max_age: Int) -> HandlerOut {
  let pol = StaticPolicy{ max_age: max_age; immutable: false; must_revalidate: false; no_store: false; };
  let sr = static_serve(dir, rel, http.header_get(req, "if-none-match"), http.header_get(req, "range"), false, &pol);
  if sr.status == 404 {
    return out_json(404, envelope.error_body("not_found", "asset not found"));
  }
  var ct: Str = "application/octet-stream";
  var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var hi: Int = 0;
  while hi < sr.headers.len() {
    let h = sr.headers[hi];
    if h.name == "Content-Type" {
      ct = h.value;
    } else {
      hs.push((h.name, h.value));
    }
    hi = hi + 1;
  }
  return HandlerOut{ status: sr.status; content_type: ct; headers: hs; body: ""; body_bytes: sr.body; };
}

/// dispatch_one routes one request: `/assets/<path>` is served from
/// PULSE_ASSETS_DIR (showcase sites), everything else goes through the
/// router + handle_route. GET and HEAD only; other methods fall through.
/// Complexity: O(request).
fn dispatch_one(eff_method: Str, req: &PulseRequest, body_str: Str) -> HandlerOut {
  if eff_method == "GET" && string.str_starts_with(req.target, "/assets/") {
    let parts = router.split_target(req.target);
    let rel = string.str_slice(parts.0, 8, parts.0.len());
    return serve_static_file(config.cfg_assets_dir(), rel, req, 3600);
  }
  let m = router.route_match(eff_method, req.target);
  return handle_route(m, &req, body_str);
}

/// handle_route dispatches a matched route to a HandlerOut.
/// Complexity: O(body).
pub fn handle_route(m: PulseRoute, req: &PulseRequest, body: Str) -> HandlerOut {
  // Transfer-Encoding policy (chunked support since 2026-10-08):
  //   * `chunked` alone -> decoded body reaches the route;
  //   * `chunked` + Content-Length -> 400: ambiguous framing is the classic
  //     CL.TE smuggling shape and is refused outright;
  //   * any other coding -> 501 (unsupported transfer-coding, RFC 9110).
  let te_hdr = http.header_get(req, "transfer-encoding");
  if te_hdr.len() > 0 {
    if !http.te_is_chunked(te_hdr) {
      return out_json(501, envelope.error_body("unsupported_transfer_encoding", "Transfer-Encoding is not supported"));
    }
    if http.header_get(req, "content-length").len() > 0 {
      return out_json(400, envelope.error_body("bad_request", "Transfer-Encoding with Content-Length is ambiguous"));
    }
  }
  if m.kind == 0 {
    return out_json(404, envelope.error_body("not_found", "not found"));
  }
  if m.kind == 2 {
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Allow", m.allow));
    return HandlerOut{ status: 405; content_type: CONTENT_JSON; headers: hs; body: envelope.error_body("method_not_allowed", "method not allowed"); body_bytes: Vec[UInt8].new(); };
  }

  if m.route_id == 1 {
    return out_json(200, json_ok_field("status", "ok"));
  }
  if m.route_id == 2 {
    var v = json.json_set(json.json_object_new(), "name", json.json_string("xiom-pulse"));
    v = json.json_set(v, "version", json.json_string(APP_VERSION));
    v = json.json_set(v, "commit", json.json_string(env.var_or("PULSE_BUILD_COMMIT", "unknown")));
    v = json.json_set(v, "build", json.json_string(env.var_or("PULSE_BUILD_DATE", "unknown")));
    return out_json(200, json.json_stringify(v));
  }
  if m.route_id == 3 {
    let parsed = json.json_parse(body);
    if parsed.is_err {
      return out_json(400, envelope.error_body("invalid_json", "invalid json"));
    }
    let v = json.json_set(json.json_object_new(), "echo", parsed.value);
    return out_json(200, json.json_stringify(v));
  }
  if m.route_id == 4 {
    var rules = schema.schema_rules_new();
    schema.schema_string(&mut rules, "user", true, 1, 64);
    let vr = schema.schema_validate(&rules, body);
    if !vr.ok {
      return out_json(400, envelope.error_body("invalid_request", vr.message));
    }
    let user = schema.schema_str_value(body, "user");
    let ttl = config.cfg_session_ttl_secs();
    let sid = sessions.session_create(user, ttl);
    let csrf = sessions.csrf_new_token();
    var v = json.json_set(json.json_object_new(), "user", json.json_string(user));
    v = json.json_set(v, "sid", json.json_string(sid));
    v = json.json_set(v, "csrf", json.json_string(csrf));
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Set-Cookie", sessions.session_cookie_header(sid, ttl)));
    hs.push(("Set-Cookie", sessions.csrf_cookie_header(csrf)));
    return HandlerOut{ status: 200; content_type: CONTENT_JSON; headers: hs; body: json.json_stringify(v); body_bytes: Vec[UInt8].new(); };
  }
  if m.route_id == 5 {
    let cookie_header = http.header_get(req, "cookie");
    let sid = sessions.session_id_from_cookie(cookie_header);
    if sid.len() == 0 {
      return out_json(401, envelope.error_body("unauthorized", "no session"));
    }
    let user = sessions.session_get(sid);
    if user.len() == 0 {
      return out_json(401, envelope.error_body("unauthorized", "invalid or expired session"));
    }
    return out_json(200, json_ok_field("user", user));
  }
  if m.route_id == 6 {
    let cookie_header = http.header_get(req, "cookie");
    let sid = sessions.session_id_from_cookie(cookie_header);
    if sid.len() > 0 { sessions.session_drop(sid); }
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Set-Cookie", sessions.session_expired_cookie_header()));
    return HandlerOut{ status: 200; content_type: CONTENT_JSON; headers: hs; body: envelope.ok_bool(true); body_bytes: Vec[UInt8].new(); };
  }
  if m.route_id == 7 {
    var rules = schema.schema_rules_new();
    schema.schema_string(&mut rules, "user", true, 1, 64);
    let vr = schema.schema_validate(&rules, body);
    if !vr.ok {
      return out_json(400, envelope.error_body("invalid_request", vr.message));
    }
    let user = schema.schema_str_value(body, "user");
    let now = time.unix_timestamp();
    var pv = json.json_set(json.json_object_new(), "sub", json.json_string(user));
    pv = json.json_set(pv, "iat", json.json_number(convert.int_to_float(now)));
    pv = json.json_set(pv, "exp", json.json_number(convert.int_to_float(now + 3600)));
    let secret_bytes = slice.str_bytes(config.cfg_jwt_secret());
    let tr = jwt.jwt_sign_hs256(json.json_stringify(pv), &secret_bytes);
    if tr.is_err {
      return out_json(500, envelope.error_body("token_error", "signing failed"));
    }
    let token = tr.value;
    return out_json(200, json_ok_field("token", token));
  }
  if m.route_id == 8 {
    var rules = schema.schema_rules_new();
    schema.schema_string(&mut rules, "token", true, 1, 4096);
    let vr = schema.schema_validate(&rules, body);
    if !vr.ok {
      return out_json(400, envelope.error_body("invalid_request", vr.message));
    }
    let token = schema.schema_str_value(body, "token");
    let now = time.unix_timestamp();
    let secret_bytes = slice.str_bytes(config.cfg_jwt_secret());
    let vr = jwt.jwt_verify_hs256(token, &secret_bytes, now);
    if vr.is_err {
      return out_json(401, envelope.error_body("invalid_token", "signature or expiry check failed"));
    }
    let payload = vr.value;
    let out_body = "{\"ok\":true,\"payload\":" + payload + "}";
    return out_json(200, out_body);
  }
  if m.route_id == 9 {
    let base = metrics.metrics_render();
    let sc = store.store_count(config.cfg_store_path());
    let extra = "# HELP pulse_store_records Valid event records.\n# TYPE pulse_store_records gauge\npulse_store_records " + sc.to_str() + "\n# HELP pulse_app_info Build info.\n# TYPE pulse_app_info gauge\npulse_app_info{version=\"0.1.0\"} 1\n";
    return out_text(200, base + extra);
  }
  if m.route_id == 10 {
    if m.param_values.len() == 0 {
      return out_json(404, envelope.error_body("not_found", "missing item id"));
    }
    return out_json(200, json_ok_field("item", m.param_values[0]));
  }
  if m.route_id == 11 {
    if !validate.is_json_object(body) {
      return out_json(400, envelope.error_body("invalid_json", "body must be a JSON object"));
    }
    let path = config.cfg_store_path();
    if !store.store_append_event(path, body) {
      return out_json(500, envelope.error_body("store_error", "append failed"));
    }
    var v = json.json_set(json.json_object_new(), "stored", json.json_bool(true));
    v = json.json_set(v, "count", json.json_number(convert.int_to_float(store.store_count(path))));
    return out_json(200, json.json_stringify(v));
  }
  if m.route_id == 12 {
    let n = store.store_count(config.cfg_store_path());
    let out_body = "{\"count\":" + n.to_str() + "}";
    return out_json(200, out_body);
  }
  if m.route_id == 13 {
    var limit: Int = 10;
    var kind_filter: Str = "";
    var qi: Int = 0;
    while qi < m.query_names.len() {
      let qn = m.query_names[qi];
      if qn == "limit" {
        let qv = m.query_values[qi];
        if qv.len() > 0 {
          let pr = parse_int(qv);
          if pr.is_ok {
            limit = pr.value;
          }
        }
      }
      if qn == "kind" {
        let qk = m.query_values[qi];
        if qk.len() > 0 && qk.len() <= 32 {
          kind_filter = qk;
        }
      }
      qi = qi + 1;
    }
    if limit < 1 { limit = 1; }
    if limit > 100 { limit = 100; }
    let path = config.cfg_store_path();
    var recs: Vec[Str] = Vec[Str].new();
    if kind_filter.len() > 0 {
      recs = store.store_last_kind(path, kind_filter, limit);
    } else {
      recs = store.store_last(path, limit);
    }
    let arr = store.store_join_array(&recs);
    let out_body = "{\"count\":" + store.store_count(path).to_str() + ",\"events\":" + arr + "}";
    return out_json(200, out_body);
  }
  if m.route_id == 16 {
    let path = config.cfg_store_path();
    if !store.store_compact(path) {
      return out_json(500, envelope.error_body("store_error", "compact failed"));
    }
    return out_json(200, envelope.ok_bool(true));
  }
  if m.route_id == 14 {
    // Static assets via registry xiom.static 0.1.0: ETag/Last-Modified/
    // Cache-Control, If-None-Match -> 304, Range -> 206/416, traversal guard.
    // NOTE: static_serve takes the path AFTER the leading "/"; a leading
    // slash is rejected as "absolute".
    let parts = router.split_target(req.target);
    var rel: Str = parts.0;
    if rel.len() > 0 && rel.byte_at(0) == 47u8 {
      rel = string.str_slice(rel, 1, rel.len());
    }
    // The URL /favicon.ico serves the app icon file (config sets its
    // directory via PULSE_STATIC_DIR; the file name is the repo default).
    if rel == "favicon.ico" {
      rel = "pulse-ico.ico";
    }
    return serve_static_file(config.cfg_static_dir(), rel, req, 86400);
  }
  if m.route_id == 15 {
    // Optional per-site landing content: PULSE_LANDING_PATH serves an HTML
    // file (read per request; low-traffic showcase sites), else the
    // built-in placeholder page.
    let lp = config.cfg_landing_path();
    if lp.len() > 0 {
      let rf = io.read_file(lp);
      if rf.is_ok {
        return out_html(200, rf.value);
      }
      io.println("pulse: landing file unreadable: " + lp);
      io.flush_stdout();
    }
    let page: Str = "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>XIOM PULSE</title>\n<link rel=\"icon\" href=\"/favicon.ico\">\n</head>\n<body>\n<h1>XIOM PULSE</h1>\n<p>Plaintext HTTP/1.1 service on XIOM. Try /health, /api/version, /api/events, /metrics.</p>\n</body>\n</html>\n";
    return out_html(200, page);
  }
  return out_json(404, envelope.error_body("not_found", "not found"));
}

/// read_request buffers one request per connection until headers and the
/// Content-Length body are complete. Complexity: O(n) syscalls.
fn read_request(client: Int) -> Vec[UInt8] {
  var raw: Vec[UInt8] = Vec[UInt8].new();
  var done: Bool = false;
  var rounds: Int = 0;
  var sent100: Bool = false;
  while !done && rounds < 1024 {
    let rr = socket.socket_recv(client, 65536);
    if rr.is_err {
      done = true;
    } else {
      let chunk = rr.value;
      if chunk.len() == 0 {
        done = true;
      } else {
        var i: Int = 0;
        while i < chunk.len() {
          raw.push(chunk[i]);
          i = i + 1;
        }
        let he = find_header_end(&raw);
        if he >= 0 {
          // Expect: 100-continue -- answer the interim before waiting for
          // the body (curl waits 1s and stalls large POSTs otherwise).
          if !sent100 {
            let preq = http.parse_request(&raw);
            if http.expects_continue(&preq) {
              let interim: Vec[UInt8] = http.str_to_bytes("HTTP/1.1 100 Continue\r\n\r\n");
              let _w = send_all(client, &interim);
              sent100 = true;
            }
          }
          let te = http.transfer_encoding_of(&raw, he);
          if te.len() > 0 {
            if http.te_is_chunked(te) {
              // Wait for the terminating zero chunk (or malformed framing);
              // the raw cap leaves a 16 KiB budget for chunk metadata.
              let tcap: Int = he + 4 + MAX_BODY + 16384;
              let st = http.chunked_state(&raw, he);
              if st != 0 || raw.len() >= tcap { done = true; }
            } else {
              // Unsupported coding: the body (if any) is not ours to read;
              // the route layer answers 501 after this head.
              done = true;
            }
          } else {
            var want: Int = he + 4 + content_length_of(&raw, he);
            let cap: Int = he + 4 + MAX_BODY;
            if want > cap { want = cap; }
            if raw.len() >= want { done = true; }
          }
        } else if header_overflow(&raw) {
          done = true;
        }
      }
    }
    rounds = rounds + 1;
  }
  return raw;
}

/// send_all writes the whole buffer through the stdlib TcpStream.write_all
/// (stdlib hardening 2026-10-07): 64 KiB staging chunks with retries over
/// partial sends -- replaces PULSE's hand-rolled chunk loop (the 270 KB
/// favicon was the original partial-send repro). Returns false on error.
/// Complexity: O(n) syscalls.
fn send_all(fd: Int, data: &Vec[UInt8]) -> Bool {
  var ts = TcpStream{ fd: fd; };
  let r = ts.write_all(data);
  return r.is_ok;
}

fn access_log(rid: Str, method: Str, target: Str, status: Int, bytes: Int, dur_ms: Int) {
  if !config.cfg_log_enabled() { return; }
  let line = "{\"ts\":" + time.unix_timestamp().to_str() + ",\"rid\":\"" + rid + "\",\"method\":\"" + method + "\",\"target\":\"" + target + "\",\"status\":" + status.to_str() + ",\"bytes\":" + bytes.to_str() + ",\"dur_ms\":" + dur_ms.to_str() + "}";
  io.println(line);
  io.flush_stdout();
}

fn audit_event(rid: Str, method: Str, target: Str, status: Int) {
  let path = config.cfg_audit_path();
  let _rot = audit.audit_rotate_if_needed(path, config.cfg_audit_max_bytes());
  let line = time.unix_timestamp().to_str() + " " + rid + " " + method + " " + target + " " + status.to_str();
  let r = io.append_line(path, line);
  if r.is_err {
    io.println("pulse: audit append failed");
    io.flush_stdout();
  }
}

fn is_mutating(method: Str) -> Bool {
  return method == "POST" || method == "PUT" || method == "DELETE" || method == "PATCH";
}

/// with_date appends the Date header (RFC 1123 / IMF-fixdate) right after
/// the status line; assembled here at the app layer, reusing the static
/// package's formatter. Complexity: O(n).
fn with_date(resp: Vec[UInt8]) -> Vec[UInt8] {
  return http.with_header_line(&resp, "Date: " + static.static_http_date(time.unix_timestamp()));
}

/// with_cors injects CORS headers into a built response when the request
/// origin is allowed. Complexity: O(n).
fn with_cors(resp: Vec[UInt8], req: &PulseRequest) -> Vec[UInt8] {
  let block = cors.cors_header_block(http.header_get(req, "origin"));
  if block.len() == 0 { return resp; }
  let he = find_header_end(&resp);
  if he < 0 { return resp; }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < he {
    out.push(resp[i]);
    i = i + 1;
  }
  // close the last existing header, add the CORS block, then the original
  // blank-line terminator (skip the 4-byte CRLFCRLF and re-add one CRLF).
  let sep = http.str_to_bytes("\r\n");
  var s: Int = 0;
  while s < sep.len() {
    out.push(sep[s]);
    s = s + 1;
  }
  let eb = http.str_to_bytes(block);
  var j: Int = 0;
  while j < eb.len() {
    out.push(eb[j]);
    j = j + 1;
  }
  // blank-line terminator between headers and body
  var t: Int = 0;
  while t < sep.len() {
    out.push(sep[t]);
    t = t + 1;
  }
  var k: Int = he + 4;
  while k < resp.len() {
    out.push(resp[k]);
    k = k + 1;
  }
  return out;
}

pub fn main() -> Int {
  // CLI: --version / --help. Build provenance is surfaced from the deploy
  // environment (PULSE_BUILD_COMMIT / PULSE_BUILD_DATE); compile-time
  // stamping needs a toolchain define flag (filed ask).
  let av = env.args();
  var ai: Int = 0;
  while ai < av.len() {
    let a = av[ai];
    if a == "--version" || a == "-V" {
      io.println("xiom-pulse " + APP_VERSION);
      io.println("commit: " + env.var_or("PULSE_BUILD_COMMIT", "unknown"));
      io.println("build:  " + env.var_or("PULSE_BUILD_DATE", "unknown"));
      return 0;
    }
    if a == "--help" || a == "-h" {
      io.println("xiom-pulse " + APP_VERSION + " -- plaintext HTTP/1.1 service");
      io.println("usage: pulse_app [--version] [--help] [--check-config]");
      io.println("env: PULSE_PORT PULSE_STORE_PATH PULSE_AUDIT_PATH PULSE_AUDIT_MAX_BYTES");
      io.println("     PULSE_JWT_SECRET PULSE_RATE_LIMIT PULSE_RATE_BURST PULSE_CORS_ORIGIN");
      io.println("     PULSE_CSRF PULSE_SESSION_TTL PULSE_STATIC_DIR PULSE_CONFIG");
      return 0;
    }
    if a == "--check-config" {
      // Pre-flight: load the config file (env wins) and dump effective
      // values without binding. Exit 1 only when a configured file is
      // unreadable/not a JSON object; the secret value is never printed.
      if !config.cfg_load_file() {
        io.println("config: load failed: " + config.cfg_config_path());
        return 1;
      }
      let cfgpath = config.cfg_config_path();
      if cfgpath.len() == 0 {
        io.println("config: no config file (env only)");
      } else {
        io.println("config: loaded " + cfgpath);
      }
      io.println("port=" + config.cfg_port().to_str());
      io.println("bind=" + config.cfg_bind());
      io.println("store=" + config.cfg_store_path());
      io.println("store_backend=" + config.cfg_store_backend());
      io.println("audit=" + config.cfg_audit_path());
      io.println("audit_max_bytes=" + config.cfg_audit_max_bytes().to_str());
      io.println("rate_limit=" + config.cfg_rate_limit().to_str() + " burst=" + config.cfg_rate_burst().to_str());
      io.println("cors=" + config.cfg_cors_origin());
      io.println("session_ttl=" + config.cfg_session_ttl_secs().to_str());
      io.println("static_dir=" + config.cfg_static_dir());
      io.println("assets_dir=" + config.cfg_assets_dir());
      io.println("landing_path=" + config.cfg_landing_path());
      let js = env.var_or("PULSE_JWT_SECRET", "");
      var secret_note: Str = "dev-default (set PULSE_JWT_SECRET for real deployments)";
      if js.len() > 0 { secret_note = "env"; }
      io.println("jwt_secret=" + secret_note);
      let warns = config.cfg_validate();
      var wi: Int = 0;
      while wi < warns.len() {
        io.println("warning: " + warns[wi]);
        wi = wi + 1;
      }
      return 0;
    }
    ai = ai + 1;
  }

  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("pulse: socket create failed");
    io.flush_stdout();
    return 1;
  }
  let fd = sr.value;
  if !config.cfg_load_file() {
    io.println("pulse: config load failed: " + config.cfg_config_path());
    io.flush_stdout();
  }
  let cfg_warns = config.cfg_validate();
  if cfg_warns.len() > 0 {
    var wj: Int = 0;
    while wj < cfg_warns.len() {
      io.println("pulse: warning: " + cfg_warns[wj]);
      wj = wj + 1;
    }
    io.flush_stdout();
  }
  let port = config.cfg_port();
  let bind_addr = config.cfg_bind();

  let br = socket.socket_bind(fd, bind_addr, port);
  if br.is_err {
    io.println("pulse: bind " + bind_addr + ":" + port.to_str() + " failed");
    io.flush_stdout();
    return 1;
  }
  let lr = socket.socket_listen(fd, 128);
  if lr.is_err {
    io.println("pulse: listen failed");
    io.flush_stdout();
    return 1;
  }
  io.println("pulse: listening on " + bind_addr + ":" + port.to_str());
  io.flush_stdout();
  metrics.metrics_mark_start(time.monotonic_ms());

  let store_ok = store.store_init(config.cfg_store_path());
  if !store_ok {
    io.println("pulse: store init failed for " + config.cfg_store_path());
    io.flush_stdout();
  }

  sessions.session_init(config.cfg_session_ttl_secs());

  let icon_ok = load_icon(config.cfg_icon_path());
  if !icon_ok {
    io.println("pulse: icon not loaded from " + config.cfg_icon_path());
    io.flush_stdout();
  }

  var limiter = ratelimit.limiter_new(config.cfg_rate_limit(), config.cfg_rate_burst());
  if limiter.enabled {
    io.println("pulse: rate limit " + limiter.per_sec.to_str() + " req/s (global)");
    io.flush_stdout();
  }
  let csrf_on = config.cfg_csrf_enabled();
  if csrf_on {
    io.println("pulse: csrf protection on (session requests)");
    io.flush_stdout();
  }

  var served: Int = 0;
  var running: Bool = true;
  while running {
    let ar = socket.socket_accept(fd);
    if ar.is_err {
      io.println("pulse: accept failed");
      io.flush_stdout();
      return 1;
    }
    let client = ar.value;
    let t0_ms = time.monotonic_ms();
    let raw = read_request(client);

    if raw.len() == 0 {
      socket.socket_close(client);
    } else {
      let rid = next_rid();
      reqctx.set_rid(rid);
      let req = http.parse_request(&raw);
      let cookie_header = http.header_get(&req, "cookie");
      if !req.ok {
        var status: Int = 400;
        var code: Str = "bad_request";
        if string.str_contains(req.error, "too large") {
          status = 413;
          code = "payload_too_large";
        }
        var no_headers: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        var resp = http.build_response_full(status, CONTENT_JSON, &no_headers, envelope.error_body(code, "bad request"));
        resp = with_date(with_cors(resp, &req));
        let w_ok = send_all(client, &resp);
        if !w_ok { io.println("pulse: send failed (" + status.to_str() + ")"); io.flush_stdout(); }
        socket.socket_close(client);
        let dur = time.monotonic_ms() - t0_ms;
        metrics.metrics_record(status, resp.len());
        metrics.metrics_record_duration(dur);
        access_log(rid, "?", "-", status, resp.len(), dur);
      } else if http.header_get(&req, "x-pulse-quit") == "1" {
        socket.socket_close(client);
        running = false;
      } else if req.method == "OPTIONS" && cors.cors_enabled() {
        var no_headers: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        var resp = http.build_response_full(204, CONTENT_TEXT, &no_headers, "");
        resp = with_date(with_cors(resp, &req));
        let w_ok = send_all(client, &resp);
        if !w_ok { io.println("pulse: send failed (204)"); io.flush_stdout(); }
        socket.socket_close(client);
        let dur = time.monotonic_ms() - t0_ms;
        metrics.metrics_record(204, 0);
        metrics.metrics_record_duration(dur);
        access_log(rid, req.method, req.target, 204, 0, dur);
      } else if csrf_on && is_mutating(req.method) && sessions.session_id_from_cookie(cookie_header).len() > 0 && !sessions.csrf_matches(cookie_header, http.header_get(&req, "x-csrf-token")) {
        var no_headers: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        let rbody = envelope.error_body("csrf", "missing or invalid CSRF token");
        var resp = http.build_response_full(403, CONTENT_JSON, &no_headers, rbody);
        resp = with_date(with_cors(resp, &req));
        let w_ok = send_all(client, &resp);
        if !w_ok { io.println("pulse: send failed (403)"); io.flush_stdout(); }
        socket.socket_close(client);
        let dur = time.monotonic_ms() - t0_ms;
        metrics.metrics_record(403, rbody.len());
        metrics.metrics_record_duration(dur);
        access_log(rid, req.method, req.target, 403, rbody.len(), dur);
      } else if !ratelimit.limiter_allow(&mut limiter, time.monotonic_ms()) {
        let now_ms = time.monotonic_ms();
        let retry_ms = ratelimit.limiter_retry_after_ms(&limiter, now_ms);
        var secs: Int = retry_ms / 1000;
        if secs < 1 { secs = 1; }
        var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        hs.push(("Retry-After", secs.to_str()));
        let rbody = envelope.error_body("rate_limited", "too many requests");
        var resp = http.build_response_full(429, CONTENT_JSON, &hs, rbody);
        resp = with_date(with_cors(resp, &req));
        let w_ok = send_all(client, &resp);
        if !w_ok { io.println("pulse: send failed (429)"); io.flush_stdout(); }
        socket.socket_close(client);
        let dur = time.monotonic_ms() - t0_ms;
        metrics.metrics_record(429, rbody.len());
        metrics.metrics_record_duration(dur);
        access_log(rid, req.method, req.target, 429, rbody.len(), dur);
      } else {
        let body_str = http.bytes_to_str(&req.body, 0, req.body.len());
        var eff_method: Str = req.method;
        if req.method == "HEAD" { eff_method = "GET"; }
        let out = dispatch_one(eff_method, &req, body_str);
        var resp: Vec[UInt8] = Vec[UInt8].new();
        var payload_len: Int = out.body.len();
        if out.body_bytes.len() > 0 {
          resp = http.build_response_bytes(out.status, out.content_type, &out.headers, &out.body_bytes);
          payload_len = out.body_bytes.len();
        } else {
          resp = http.build_response_full(out.status, out.content_type, &out.headers, out.body);
        }
        if req.method == "HEAD" {
          let he = find_header_end(&resp);
          if he >= 0 {
            var trimmed: Vec[UInt8] = Vec[UInt8].new();
            var ti: Int = 0;
            while ti < he + 4 {
              trimmed.push(resp[ti]);
              ti = ti + 1;
            }
            resp = trimmed;
          }
        }
        resp = with_date(with_cors(resp, &req));
        let w_ok = send_all(client, &resp);
        if !w_ok {
          io.println("pulse: send failed");
          io.flush_stdout();
        }
        socket.socket_close(client);
        served = served + 1;
        let dur = time.monotonic_ms() - t0_ms;
        metrics.metrics_record(out.status, payload_len);
        metrics.metrics_record_duration(dur);
        access_log(rid, req.method, req.target, out.status, payload_len, dur);
        if req.method != "GET" {
          audit_event(rid, req.method, req.target, out.status);
        }
      }
    }
  }

  socket.socket_close(fd);
  io.println("pulse: shutdown served=" + served.to_str());
  io.flush_stdout();
  return 0;
}
