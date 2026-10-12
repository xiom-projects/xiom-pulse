// XIOM PULSE witness -- kv backend startup hang under v0.64.4
// (toolchain trigger; both stdlib pins). Run from an empty workdir:
//   xiom --run docs/repro/kv-hang-0644/witness.xi
// Expected pre-regression (v0.64.3): prints open/put/get/close + "done",
// exit 0. Under v0.64.4: hangs (watchdog) with no output or partial.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module kv_min_probe;

use xiom.io;
use xiom.kv;

fn main() -> Int {
  let _cd = io.create_dir_all("kv-probe-store");
  io.println("open");
  let r = kv.kv_open("kv-probe-store", "probe", 4096);
  if r.is_err {
    io.println("open err: " + r.error);
    return 1;
  }
  var s = r.value;
  io.println("put");
  let p = kv.kv_put(&mut s, "k1", "v1");
  if p.is_err {
    io.println("put err: " + p.error);
    return 1;
  }
  io.println("get");
  let g = kv.kv_get(&s, "k1");
  if g.is_err {
    io.println("get err: " + g.error);
    return 1;
  }
  io.println("count=" + kv.kv_count(&s).to_str());
  kv.kv_close(&mut s);
  io.println("done");
  return 0;
}
