// XIOM PULSE -- HTTP/1.1 server loop and routing.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Single-threaded sequential-accept server on 127.0.0.1:8080 (the pinned
// runtime exposes no select/threads/timeouts). Reads go through the raw fd
// socket API because C-PULSE-01 disables one-arg `.read(...)` methods.
// TLS is terminated by the front proxy; this process speaks plaintext HTTP.
//
// Build: .\scripts\build.ps1 src\server.xi -Name pulse_server
// Quit:  send any request with header `X-Pulse-Quit: 1`
module xiom.pulse.server

use xiom.net.socket;
use xiom.io;
use xiom.env;
use xiom.serialize.json;
use xiom.pulse.http;

const MAX_BODY: Int = 1048576;

/// port_from_str parses a decimal port, falling back to 8080.
/// Complexity: O(n). Pure.
fn port_from_str(s: Str) -> Int {
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

/// server_port returns the listen port from PULSE_PORT, else 8080.
/// Complexity: O(1). Pure.
fn server_port() -> Int {
  return port_from_str(env.var_or("PULSE_PORT", "8080"));
}

fn error_json(msg: Str) -> Str {
  let v = json.json_set(json.json_object_new(), "error", json.json_string(msg));
  return json.json_stringify(v);
}

/// handle_route dispatches one parsed request to a status + JSON body.
/// Complexity: O(1) plus body parse. Pure.
pub fn handle_route(method: Str, target: Str, body: Str) -> RouteResult {
  if target == "/health" {
    if method != "GET" {
      return RouteResult{ status: 405; body: error_json("method not allowed"); };
    }
    let v = json.json_set(json.json_object_new(), "status", json.json_string("ok"));
    return RouteResult{ status: 200; body: json.json_stringify(v); };
  }
  if target == "/api/version" {
    if method != "GET" {
      return RouteResult{ status: 405; body: error_json("method not allowed"); };
    }
    var v = json.json_set(json.json_object_new(), "name", json.json_string("xiom-pulse"));
    v = json.json_set(v, "version", json.json_string("0.1.0"));
    return RouteResult{ status: 200; body: json.json_stringify(v); };
  }
  if target == "/api/echo" {
    if method != "POST" {
      return RouteResult{ status: 405; body: error_json("method not allowed"); };
    }
    let parsed = json.json_parse(body);
    if parsed.is_err {
      return RouteResult{ status: 400; body: error_json("invalid json"); };
    }
    let v = json.json_set(json.json_object_new(), "echo", parsed.value);
    return RouteResult{ status: 200; body: json.json_stringify(v); };
  }
  return RouteResult{ status: 404; body: error_json("not found"); };
}

/// read_request buffers one request per connection until its headers and
/// (Content-Length) body are complete. Complexity: O(n) syscalls.
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
          if want > cap {
            want = cap;
          }
          if raw.len() >= want {
            done = true;
          }
        }
      }
    }
    rounds = rounds + 1;
  }
  return raw;
}

pub fn main() -> Int {
  let sr = socket.socket_tcp();
  if sr.is_err {
    io.println("pulse: socket create failed");
    io.flush_stdout();
    return 1;
  }
  let fd = sr.value;
  let port = server_port();

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
      let req = http.parse_request(&raw);
      if !req.ok {
        let resp = http.build_response(400, error_json("bad request"));
        let w = socket.socket_send(client, &resp);
        if w.is_err {
          io.println("pulse: send failed (400)");
          io.flush_stdout();
        }
        socket.socket_close(client);
      } else if http.header_get(&req, "x-pulse-quit") == "1" {
        socket.socket_close(client);
        running = false;
      } else {
        let body_str = http.bytes_to_str(&req.body, 0, req.body.len());
        let result = handle_route(req.method, req.target, body_str);
        let resp = http.build_response(result.status, result.body);
        let w = socket.socket_send(client, &resp);
        if w.is_err {
          io.println("pulse: send failed");
          io.flush_stdout();
        }
        socket.socket_close(client);
        served = served + 1;
        io.println("pulse: " + req.method + " " + req.target + " -> " + result.status.to_str() + " blen=" + req.body.len().to_str());
        io.flush_stdout();
      }
    }
  }

  socket.socket_close(fd);
  io.println("pulse: shutdown served=" + served.to_str());
  io.flush_stdout();
  return 0;
}
