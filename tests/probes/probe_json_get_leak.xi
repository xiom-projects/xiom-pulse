// XIOM PULSE -- isolate the bttger /insert memory growth.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module probe_json_get_leak

use xiom.io;
use xiom.serialize.json;

const BODY: Str = "{\"name\":\"Sightseeing\",\"addresses\":[{\"street\":\"Breite Strasse\",\"number\":89,\"city\":\"Lubeck\"},{\"street\":\"Breite Strasse\",\"number\":89,\"city\":\"Lubeck\"}],\"oldTown\":true}";

fn build() -> Str {
  let pv = json.json_parse(BODY);
  if !pv.is_ok { return ""; }
  var b = json.json_object_builder_new();
  let name = json.json_get(pv.value, "name");
  if name.is_some { b.put("name", name.value); }
  let addresses = json.json_get(pv.value, "addresses");
  if addresses.is_some { b.put("addresses", addresses.value); }
  let old_town = json.json_get(pv.value, "oldTown");
  if old_town.is_some { b.put("oldTown", old_town.value); }
  b.put("id", json.json_number(300.0));
  b.put("createdAt", json.json_string("2026-10-22T15:00:00Z"));
  return json.json_stringify(b.build());
}

pub fn main() -> Int {
  var i: Int = 0;
  while i < 2000 {
    let s = build();
    if s.len() == 0 { io.println("build failed"); return 1; }
    if i % 200 == 0 { io.println("iter=" + i.to_str() + " bytes=" + s.len().to_str()); io.flush_stdout(); }
    i = i + 1;
  }
  io.println("probe-json-get-leak: done");
  return 0;
}
