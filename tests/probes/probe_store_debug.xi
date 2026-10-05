// probe_store_debug -- inspect raw JSONL lines written by the store module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_store_debug

use xiom.io;
use xiom.pulse.store;

fn main() -> Int {
  let sp = "pulse-store-debug.jsonl";
  let _rm = io.remove_file(sp);
  io.println("init=" + store.store_init(sp).to_str());
  io.println("append=" + store.store_append_event(sp, "{\"a\":1}").to_str());
  let lines = io.read_file_lines(sp);
  if lines.is_ok {
    let ls = lines.value;
    var i: Int = 0;
    while i < ls.len() {
      io.println("line[" + i.to_str() + "]=[" + ls[i] + "]");
      i = i + 1;
    }
  } else {
    io.println("read failed");
  }
  io.println("count=" + store.store_count(sp).to_str());
  let _rm2 = io.remove_file(sp);
  return 0;
}
