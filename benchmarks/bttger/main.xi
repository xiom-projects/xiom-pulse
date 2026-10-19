// XIOM PULSE -- bttger web-framework-benchmarks contract server.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Six-endpoint interface from E:\repos\web-framework-benchmarks
// (OPEN_API_DEFINITION.yaml). This is a benchmark harness app, NOT part of
// the product server: it deliberately implements only the contract routes.
// Build: scripts/build.ps1 benchmarks\bttger\main.xi -Name bench_bttger
// Run:   PULSE_PORT=8080 out\bench_bttger.exe
module bench_bttger

use xiom.pulse.app;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.serialize.json;
use xiom.time;
use xiom.string;

fn param_value(m: &PulseRoute, name: Str) -> Str {
  var i: Int = 0;
  while i < m.param_names.len() {
    if m.param_names[i] == name { return m.param_values[i]; }
    i = i + 1;
  }
  return "";
}

fn query_value(m: &PulseRoute, name: Str) -> Str {
  var i: Int = 0;
  while i < m.query_names.len() {
    if m.query_names[i] == name { return m.query_values[i]; }
    i = i + 1;
  }
  return "";
}

/// big_json builds the large typed response per request (the contract asks
/// for on-demand iteration, not a pre-initialized object). Complexity:
/// O(50).
fn big_json() -> Str {
  var pubs = json.json_array_new();
  var i: Int = 0;
  while i < 50 {
    var p = json.json_object_new();
    p = json.json_set(p, "year", json.json_number((1821 + i) as Float64));
    p = json.json_set(p, "related", json.json_bool(true));
    p = json.json_set(p, "description", json.json_string("Some discovery in " + (1821 + i).to_str()));
    pubs = json.json_array_push(pubs, p);
    i = i + 1;
  }
  var born = json.json_object_new();
  born = json.json_set(born, "year", json.json_number(1800.0));
  born = json.json_set(born, "month", json.json_string("February"));
  born = json.json_set(born, "day", json.json_number(12.0));
  born = json.json_set(born, "city", json.json_string("Walsall"));
  born = json.json_set(born, "country", json.json_string("England"));
  var died = json.json_object_new();
  died = json.json_set(died, "year", json.json_number(1875.0));
  died = json.json_set(died, "month", json.json_string("March"));
  died = json.json_set(died, "day", json.json_number(7.0));
  died = json.json_set(died, "city", json.json_string("London"));
  died = json.json_set(died, "country", json.json_string("England"));
  var classifier = json.json_object_new();
  classifier = json.json_set(classifier, "name", json.json_string("John Edward Gray"));
  classifier = json.json_set(classifier, "born", born);
  classifier = json.json_set(classifier, "died", died);
  classifier = json.json_set(classifier, "publications", pubs);
  var sc = json.json_object_new();
  sc = json.json_set(sc, "kingdom", json.json_string("Animalia"));
  sc = json.json_set(sc, "phylum", json.json_string("Chordata"));
  sc = json.json_set(sc, "class", json.json_string("Mammalia"));
  sc = json.json_set(sc, "order", json.json_string("Proboscidea"));
  sc = json.json_set(sc, "superfamily", json.json_string("Elephantoidea"));
  sc = json.json_set(sc, "classifier", classifier);
  var root = json.json_object_new();
  root = json.json_set(root, "family", json.json_string("Elephantidae"));
  root = json.json_set(root, "scientificClassification", sc);
  return json.json_stringify(root);
}

fn now_iso() -> Str {
  let human = time.format_timestamp(time.unix_timestamp());
  return string.str_replace_all(human, " ", "T") + "Z";
}

fn query_result(req: &PulseRequest, m: &PulseRoute) -> HandlerOut {
  let ok = param_value(m, "userId") == "300" &&
           param_value(m, "offset") == "10" &&
           query_value(m, "model") == "Dozer" &&
           query_value(m, "factor") == "ATX" &&
           query_value(m, "length") == "800" &&
           query_value(m, "width") == "800" &&
           query_value(m, "allow") == "true" &&
           http.header_get(req, "x-api-key") == "zb478fb3" &&
           http.header_get(req, "x-session-id") == "jhg723bf";
  if !ok {
    return app.out_json(400, "{\"message\":\"check your query arguments again\"}");
  }
  return app.out_json(200, "{\"id\":6000,\"foundAt\":\"" + now_iso() + "\"}");
}

fn insert_object(body: Str) -> HandlerOut {
  let pv = json.json_parse(body);
  if !pv.is_ok {
    return app.out_json(400, "{\"message\":\"invalid json\"}");
  }
  var v = json.json_set(pv.value, "id", json.json_number(300.0));
  v = json.json_set(v, "createdAt", json.json_string(now_iso()));
  return app.out_json(201, json.json_stringify(v));
}

fn fib(n: Int) -> Int {
  if n <= 1 { return 1; }
  return fib(n - 1) + fib(n - 2);
}

fn handle(req: &PulseRequest, m: &PulseRoute, body: Str) -> HandlerOut {
  if m.route_id == 1 { return app.out_json(200, "{\"message\":\"Hello, World!\"}"); }
  if m.route_id == 2 { return app.out_json(200, big_json()); }
  if m.route_id == 3 { return app.out_text(200, "Hello, World!"); }
  if m.route_id == 4 { return query_result(req, m); }
  if m.route_id == 5 { return insert_object(body); }
  if m.route_id == 6 { return app.out_json(200, "{\"fibonacci\":" + fib(27).to_str() + "}"); }
  return app.out_json(404, "{\"message\":\"not found\"}");
}

pub fn main() -> Int {
  let _ = app.register("GET", "/serialize");
  let _ = app.register("GET", "/serialize/big");
  let _ = app.register("GET", "/plain/text");
  let _ = app.register("GET", "/query/:userId/tools/:offset");
  let _ = app.register("POST", "/insert");
  let _ = app.register("GET", "/calculate");
  return app.serve(handle);
}
