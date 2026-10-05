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
use xiom.pulse.jwt_hs;

const MAX_BODY: Int = 1048576;
const CONTENT_JSON: Str = "application/json; charset=utf-8";
const CONTENT_TEXT: Str = "text/plain; charset=utf-8";

var req_counter: Int = 0;

fn next_rid() -> Str {
  req_counter = req_counter + 1;
  return "r-" + req_counter.to_str();
}

/// HandlerOut - one dispatched response.
pub type HandlerOut = {
  status: Int;
  content_type: Str;
  headers: Vec[(Str, Str)];
  body: Str;
}

fn out_json(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_JSON; headers: Vec[(Str, Str)].new(); body: body; };
}

fn out_text(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_TEXT; headers: Vec[(Str, Str)].new(); body: body; };
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
    return HandlerOut{ status: 405; content_type: CONTENT_JSON; headers: hs; body: envelope.error_body("method_not_allowed", "method not allowed"); };
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
    return HandlerOut{ status: 200; content_type: CONTENT_JSON; headers: hs; body: json.json_stringify(v); };
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
    return HandlerOut{ status: 200; content_type: CONTENT_JSON; headers: hs; body: envelope.ok_bool(true); };
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
    let token = jwt_hs.hs256_sign(json.json_stringify(pv), config.cfg_jwt_secret());
    return out_json(200, json_ok_field("token", token));
  }
  if m.route_id == 8 {
    let token = json_body_str(body, "token");
    if token.len() == 0 {
      return out_json(400, envelope.error_body("invalid_request", "body must be {\"token\":\"...\"}"));
    }
    let now = time.unix_timestamp();
    if !jwt_hs.hs256_verify_now(token, config.cfg_jwt_secret(), now) {
      return out_json(401, envelope.error_body("invalid_token", "signature or expiry check failed"));
    }
    return out_json(200, envelope.ok_bool(true));
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
        let w = socket.socket_send(client, &resp);
        if w.is_err { io.println("pulse: send failed (400)"); io.flush_stdout(); }
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
        let resp = http.build_response_full(out.status, out.content_type, &out.headers, out.body);
        let w = socket.socket_send(client, &resp);
        if w.is_err {
          io.println("pulse: send failed");
          io.flush_stdout();
        }
        socket.socket_close(client);
        served = served + 1;
        metrics.metrics_record(out.status, out.body.len());
        access_log(rid, req.method, req.target, out.status, out.body.len());
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
