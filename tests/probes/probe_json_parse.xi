// XIOM PULSE -- isolate JSON parse/stringify retention from the builder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Builds the bttger /serialize/big document once, then loops
// json_parse -> json_stringify on the resulting string. Run under a cap:
//   PULSE_MAX_RSS_MB=512 ./scripts/capped_app.sh ./out/probe_json_parse
// If this completes, the retained memory is the json_set/json_array_push
// builder (not the parser/stringifier).
module probe_json_parse

use xiom.io;
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
  let s = sample();
  io.println("sample bytes=" + s.len().to_str());
  var i: Int = 0;
  while i < 2000 {
    let pv = json.json_parse(s);
    if !pv.is_ok { io.println("parse failed"); return 1; }
    let out = json.json_stringify(pv.value);
    if out.len() == 0 { io.println("stringify failed"); return 1; }
    if i % 500 == 0 {
      io.println("iter=" + i.to_str() + " out=" + out.len().to_str());
      io.flush_stdout();
    }
    i = i + 1;
  }
  io.println("probe-json-parse: done 2000 iterations");
  return 0;
}
