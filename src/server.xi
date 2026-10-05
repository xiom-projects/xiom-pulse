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
// Build: .\scripts\build.ps1 src\server.xi -Name pulse_server
// Quit:  send any request with header `X-Pulse-Quit: 1`
module xiom.pulse.server

use xiom.net.socket;
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
use xiom.pulse.session;
use xiom.jwt;
use xiom.string.slice;
use xiom.pulse.store;

const MAX_BODY: Int = 1048576;
const CONTENT_JSON: Str = "application/json; charset=utf-8";
const CONTENT_TEXT: Str = "text/plain; charset=utf-8";

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

fn json_body_str(body: Str, key: Str) -> Str {
  let pv = json.json_parse(body);
  if pv.is_err { return ""; }
  let opt = json.json_get(pv.value, key);
  if opt.is_none { return ""; }
  let v = opt.value;
  if json.json_type(v) != "string" { return ""; }
  match v {
    JsonValue.String(s) => { return s; },
    _ => { return ""; },
  }
}

fn json_ok_field(key: Str, value: Str) -> Str {
  let v = json.json_set(json.json_object_new(), key, json.json_string(value));
  return json.json_stringify(v);
}

/// handle_route dispatches a matched route to a HandlerOut.
/// Complexity: O(body).
pub fn handle_route(m: RouteMatch, req: &PulseRequest, body: Str) -> HandlerOut {
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
    v = json.json_set(v, "version", json.json_string("0.1.0"));
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
    let user = json_body_str(body, "user");
    if user.len() == 0 {
      return out_json(400, envelope.error_body("invalid_request", "body must be {\"user\":\"...\"}"));
    }
    let ttl = config.cfg_session_ttl_secs();
    let sid = session.session_create(user, ttl);
    var v = json.json_set(json.json_object_new(), "user", json.json_string(user));
    v = json.json_set(v, "sid", json.json_string(sid));
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Set-Cookie", session.session_cookie_header(sid, ttl)));
    return HandlerOut{ status: 200; content_type: CONTENT_JSON; headers: hs; body: json.json_stringify(v); body_bytes: Vec[UInt8].new(); };
  }
  if m.route_id == 5 {
    let cookie_header = http.header_get(req, "cookie");
    let sid = session.session_id_from_cookie(cookie_header);
    if sid.len() == 0 {
      return out_json(401, envelope.error_body("unauthorized", "no session"));
    }
    let user = session.session_get(sid);
    if user.len() == 0 {
      return out_json(401, envelope.error_body("unauthorized", "invalid or expired session"));
    }
    return out_json(200, json_ok_field("user", user));
  }
  if m.route_id == 6 {
    let cookie_header = http.header_get(req, "cookie");
    let sid = session.session_id_from_cookie(cookie_header);
    if sid.len() > 0 { session.session_drop(sid); }
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("Set-Cookie", session.session_expired_cookie_header()));
    return HandlerOut{ status: 200; content_type: CONTENT_JSON; headers: hs; body: envelope.ok_bool(true); body_bytes: Vec[UInt8].new(); };
  }
  if m.route_id == 7 {
    let user = json_body_str(body, "user");
    if user.len() == 0 {
      return out_json(400, envelope.error_body("invalid_request", "body must be {\"user\":\"...\"}"));
    }
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
    let token = json_body_str(body, "token");
    if token.len() == 0 {
      return out_json(400, envelope.error_body("invalid_request", "body must be {\"token\":\"...\"}"));
    }
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
    return out_text(200, metrics.metrics_render());
  }
  if m.route_id == 10 {
    if m.param_values.len() == 0 {
      return out_json(404, envelope.error_body("not_found", "missing item id"));
    }
    return out_json(200, json_ok_field("item", m.param_values[0]));
  }
  if m.route_id == 11 {
    let pv = json.json_parse(body);
    if pv.is_err || json.json_type(pv.value) != "object" {
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
    let path = config.cfg_store_path();
    let recs = store.store_last(path, 10);
    let arr = store.store_join_array(&recs);
    let out_body = "{\"count\":" + store.store_count(path).to_str() + ",\"events\":" + arr + "}";
    return out_json(200, out_body);
  }
  if m.route_id == 14 {
    if !icon_loaded {
      return out_json(404, envelope.error_body("not_found", "icon not loaded"));
    }
    return HandlerOut{ status: 200; content_type: "image/x-icon"; headers: Vec[(Str, Str)].new(); body: ""; body_bytes: icon_bytes; };
  }
  if m.route_id == 15 {
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
          var want: Int = he + 4 + content_length_of(&raw, he);
          let cap: Int = he + 4 + MAX_BODY;
          if want > cap { want = cap; }
          if raw.len() >= want { done = true; }
        }
      }
    }
    rounds = rounds + 1;
  }
  return raw;
}

/// send_all writes the whole buffer, chunking and looping over partial
/// sends (raw `socket_send` may accept fewer bytes than requested -- hit
/// when serving the 270 KB favicon). Returns false on error/short write.
/// Complexity: O(n) syscalls.
fn send_all(fd: Int, data: &Vec[UInt8]) -> Bool {
  var off: Int = 0;
  var guard: Int = 0;
  while off < data.len() && guard < 4096 {
    let remaining: Int = data.len() - off;
    var chunk_len: Int = remaining;
    if chunk_len > 32768 { chunk_len = 32768; }
    var chunk: Vec[UInt8] = Vec[UInt8].new();
    var i: Int = off;
    while i < off + chunk_len {
      chunk.push(data[i]);
      i = i + 1;
    }
    let w = socket.socket_send(fd, &chunk);
    if w.is_err { return false; }
    let n = w.value;
    if n <= 0 { return false; }
    off = off + n;
    guard = guard + 1;
  }
  return off >= data.len();
}

fn access_log(rid: Str, method: Str, target: Str, status: Int, bytes: Int) {
  if !config.cfg_log_enabled() { return; }
  let line = "{\"ts\":" + time.unix_timestamp().to_str() + ",\"rid\":\"" + rid + "\",\"method\":\"" + method + "\",\"target\":\"" + target + "\",\"status\":" + status.to_str() + ",\"bytes\":" + bytes.to_str() + "}";
  io.println(line);
  io.flush_stdout();
}

fn audit_event(rid: Str, method: Str, target: Str, status: Int) {
  let line = time.unix_timestamp().to_str() + " " + rid + " " + method + " " + target + " " + status.to_str();
  let r = io.append_line(config.cfg_audit_path(), line);
  if r.is_err {
    io.println("pulse: audit append failed");
    io.flush_stdout();
  }
}

pub fn main() -> Int {
  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("pulse: socket create failed");
    io.flush_stdout();
    return 1;
  }
  let fd = sr.value;
  let port = config.cfg_port();

  let br = socket.socket_bind(fd, "127.0.0.1", port);
  if br.is_err {
    io.println("pulse: bind 127.0.0.1:" + port.to_str() + " failed");
    io.flush_stdout();
    return 1;
  }
  let lr = socket.socket_listen(fd, 128);
  if lr.is_err {
    io.println("pulse: listen failed");
    io.flush_stdout();
    return 1;
  }
  io.println("pulse: listening on 127.0.0.1:" + port.to_str());
  io.flush_stdout();

  let store_ok = store.store_init(config.cfg_store_path());
  if !store_ok {
    io.println("pulse: store init failed for " + config.cfg_store_path());
    io.flush_stdout();
  }

  let icon_ok = load_icon(config.cfg_icon_path());
  if !icon_ok {
    io.println("pulse: icon not loaded from " + config.cfg_icon_path());
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
    let raw = read_request(client);

    if raw.len() == 0 {
      socket.socket_close(client);
    } else {
      let rid = next_rid();
      let req = http.parse_request(&raw);
      if !req.ok {
        var no_headers: Vec[(Str, Str)] = Vec[(Str, Str)].new();
        let resp = http.build_response_full(400, CONTENT_JSON, &no_headers, envelope.error_body("bad_request", "bad request"));
        let w_ok = send_all(client, &resp);
        if !w_ok { io.println("pulse: send failed (400)"); io.flush_stdout(); }
        socket.socket_close(client);
        metrics.metrics_record(400, resp.len());
        access_log(rid, "?", "-", 400, resp.len());
      } else if http.header_get(&req, "x-pulse-quit") == "1" {
        socket.socket_close(client);
        running = false;
      } else {
        let body_str = http.bytes_to_str(&req.body, 0, req.body.len());
        let m = router.route_match(req.method, req.target);
        let out = handle_route(m, &req, body_str);
        var resp: Vec[UInt8] = Vec[UInt8].new();
        var payload_len: Int = out.body.len();
        if out.body_bytes.len() > 0 {
          resp = http.build_response_bytes(out.status, out.content_type, &out.headers, &out.body_bytes);
          payload_len = out.body_bytes.len();
        } else {
          resp = http.build_response_full(out.status, out.content_type, &out.headers, out.body);
        }
        let w_ok = send_all(client, &resp);
        if !w_ok {
          io.println("pulse: send failed");
          io.flush_stdout();
        }
        socket.socket_close(client);
        served = served + 1;
        metrics.metrics_record(out.status, payload_len);
        access_log(rid, req.method, req.target, out.status, payload_len);
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
