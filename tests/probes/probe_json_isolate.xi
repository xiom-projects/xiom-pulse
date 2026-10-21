// XIOM PULSE -- bisect the JSON retention (parse vs stringify vs plain Str).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Usage under the RSS cap:
//   PULSE_MAX_RSS_MB=256 ./scripts/capped_app.sh ./out/probe_json_isolate parse
//   PULSE_MAX_RSS_MB=256 ./scripts/capped_app.sh ./out/probe_json_isolate stringify
//   PULSE_MAX_RSS_MB=256 ./scripts/capped_app.sh ./out/probe_json_isolate string
module probe_json_isolate

use xiom.io;
use xiom.env;
use xiom.serialize.json;

fn sample() -> Str {
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
  var root = json.json_object_new();
  root = json.json_set(root, "family", json.json_string("Elephantidae"));
  root = json.json_set(root, "publications", pubs);
  return json.json_stringify(root);
}

pub fn main() -> Int {
  let argv = env.args();
  var mode: Str = "parse";
  if argv.len() > 1 { mode = argv[1]; }
  let s = sample();
  io.println("mode=" + mode + " sample=" + s.len().to_str());
  io.flush_stdout();
  if mode == "parse" {
    var i: Int = 0;
    while i < 5000 {
      let pv = json.json_parse(s);
      if !pv.is_ok { io.println("parse failed"); return 1; }
      if i % 500 == 0 { io.println("iter=" + i.to_str()); io.flush_stdout(); }
      i = i + 1;
    }
  } elif mode == "stringify" {
    let pv = json.json_parse(s);
    if !pv.is_ok { io.println("parse failed"); return 1; }
    var i: Int = 0;
    while i < 5000 {
      let out = json.json_stringify(pv.value);
      if out.len() == 0 { io.println("stringify failed"); return 1; }
      if i % 500 == 0 { io.println("iter=" + i.to_str()); io.flush_stdout(); }
      i = i + 1;
    }
  } elif mode == "string" {
    var i: Int = 0;
    while i < 2000000 {
      let out = "abcdefghij" + i.to_str();
      if out.len() < 10 { io.println("concat failed"); return 1; }
      if i % 200000 == 0 { io.println("iter=" + i.to_str()); io.flush_stdout(); }
      i = i + 1;
    }
  } else {
    io.println("unknown mode");
    return 2;
  }
  io.println("probe-json-isolate: done");
  return 0;
}
