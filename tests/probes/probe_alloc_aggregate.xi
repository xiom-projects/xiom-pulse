// XIOM PULSE -- allocation-lifetime bisect: Map vs Vec vs Str vs JSON.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Each iteration allocates and drops one aggregate of the selected kind.
// Run under a peak-RSS sampler:
//   out\probe_alloc_aggregate.exe map
//   out\probe_alloc_aggregate.exe vec
//   out\probe_alloc_aggregate.exe str
//   out\probe_alloc_aggregate.exe obj
// A linear peak with the iteration count means the runtime retains freed
// aggregate memory (the REL-20261020-1704 / m375 class); a plateau means
// only a high-water mark is kept.
module probe_alloc_aggregate

use xiom.io;
use xiom.env;
use xiom.serialize.json;
use xiom.collections;
use xiom.convert.parse;

pub fn main() -> Int {
  let argv = env.args();
  var mode: Str = "map";
  if argv.len() > 1 { mode = argv[1]; }
  var n: Int = 20000;
  var iter: Int = 0;
  let nr = parse_int(env.var_or("PROBE_ITERS", "20000"));
  if nr.is_ok { n = nr.value; }
  var acc: Int = 0;
  while iter < n {
    if mode == "map" {
      var m: Map[Str, Int] = Map[Str, Int].new();
      m.insert("a", iter);
      m.insert("b", iter + 1);
      m.insert("c", iter + 2);
      acc = acc + m.len();
    } elif mode == "vec" {
      var v: Vec[Int] = Vec[Int].new();
      var j: Int = 0;
      while j < 8 {
        v.push(j);
        j = j + 1;
      }
      acc = acc + v.len();
    } elif mode == "str" {
      let s = "abcdefghij" + iter.to_str();
      acc = acc + s.len();
    } elif mode == "obj" {
      var b = json.json_object_builder_new();
      b.put("a", json.json_number(1.0));
      let s = json.json_stringify(b.build());
      acc = acc + s.len();
    } elif mode == "type" {
      // JsonValue passed by value to a trivial accessor: isolates the
      // by-value aggregate copy from the stringify builder.
      var b = json.json_object_builder_new();
      b.put("a", json.json_number(1.0));
      let t = json.json_type(b.build());
      acc = acc + t.len();
    } elif mode == "get" {
      var b = json.json_object_builder_new();
      b.put("a", json.json_number(1.0));
      let g = json.json_get(b.build(), "a");
      if g.is_some { acc = acc + 1; }
    } elif mode == "parse" {
      let pv = json.json_parse("{\"a\":1}");
      if pv.is_ok { acc = acc + 1; }
    } else {
      io.println("unknown mode: " + mode);
      return 2;
    }
    iter = iter + 1;
  }
  io.println("done mode=" + mode + " acc=" + acc.to_str());
  return 0;
}
