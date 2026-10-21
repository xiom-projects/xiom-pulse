// XIOM PULSE -- verify the in-place JSON builders against the leak report.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Requires the stdlib builder API from commit 526fd96 (not in the
// stdlib-tag-v0.64.8 pin yet). Build with:
//   $env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
//   scripts/build.ps1 tests\probes\probe_json_builder_leak.xi -Name probe_json_builder_leak
// Run under the RSS cap; 500 iterations should complete, 2000 exposes the
// residual aggregate/drop retention reported by the stdlib lane.
module probe_json_builder_leak

use xiom.io;
use xiom.serialize.json;

fn big_json() -> Str {
  var pubs = json.json_array_builder_new();
  var i: Int = 0;
  while i < 50 {
    var p = json.json_object_builder_new();
    p.put("year", json.json_number((1821 + i) as Float64));
    p.put("related", json.json_bool(true));
    p.put("description", json.json_string("Some discovery in " + (1821 + i).to_str()));
    pubs.push(p.build());
    i = i + 1;
  }
  var root = json.json_object_builder_new();
  root.put("family", json.json_string("Elephantidae"));
  root.put("publications", pubs.build());
  return json.json_stringify(root.build());
}

pub fn main() -> Int {
  var i: Int = 0;
  while i < 2000 {
    let s = big_json();
    if i % 200 == 0 {
      io.println("iter=" + i.to_str() + " bytes=" + s.len().to_str());
      io.flush_stdout();
    }
    i = i + 1;
  }
  io.println("probe-json-builder-leak: done 2000 iterations");
  return 0;
}
