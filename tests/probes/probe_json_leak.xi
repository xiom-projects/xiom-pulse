// XIOM PULSE -- JSON builder memory probe (owner RSS-cap follow-up).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Reproduces the bttger /serialize/big allocation shape without HTTP:
// 50 publication objects, each added with json_array_push, then nested
// with json_set. Run under scripts/capped_app.sh with a low cap:
//   PULSE_MAX_RSS_MB=512 ./scripts/capped_app.sh ./out/probe_json_leak
// If the wrapper kills it, the JSON builder path is retaining memory.
module probe_json_leak

use xiom.io;
use xiom.serialize.json;

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

pub fn main() -> Int {
  var i: Int = 0;
  while i < 2000 {
    let s = big_json();
    if i % 100 == 0 {
      io.println("iter=" + i.to_str() + " bytes=" + s.len().to_str());
      io.flush_stdout();
    }
    i = i + 1;
  }
  io.println("probe-json-leak: done 2000 iterations");
  return 0;
}
