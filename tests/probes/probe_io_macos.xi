// XIOM PULSE -- macOS io name/read diagnostic (non-gating witness probe).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The macOS x64 migrations witness reads `20260101000002_seed.sql` back as
// `0260101000002_seed.sql`. This probe writes a long and a short name,
// lists the directory, prints each entry and length, and reads both paths
// back. Run it on macOS from CI; the output goes to the stdlib finding.
module probe_io_macos

use xiom.io;
use xiom.convert.time as ctime;

fn bstr(v: Bool) -> Str {
  if v { return "true"; }
  return "false";
}

fn dump(dir: Str) {
  let r = io.list_dir(dir);
  io.println("list_ok=" + bstr(r.is_ok));
  if !r.is_ok { return; }
  io.println("entries=" + r.value.len().to_str());
  var i: Int = 0;
  while i < r.value.len() {
    let e = r.value[i];
    io.println("entry[" + i.to_str() + "] len=" + e.len().to_str() + " name=[" + e + "]");
    i = i + 1;
  }
}

pub fn main() -> Int {
  let dir = "probe-logs/io-probe-" + ctime.timestamp_now().to_str();
  let _ = io.create_dir_all(dir);
  let long_name = "20260101000002_seed.sql";
  let short_name = "a.sql";
  let long_path = dir + "/" + long_name;
  let short_path = dir + "/" + short_name;

  let wl = io.write_file(long_path, "LONG");
  let ws = io.write_file(short_path, "SHORT");
  io.println("dir=" + dir);
  io.println("long_path=[" + long_path + "]");
  io.println("long_write=" + bstr(wl.is_ok) + " long_exists=" + bstr(io.file_exists(long_path)));
  io.println("short_path=[" + short_path + "]");
  io.println("short_write=" + bstr(ws.is_ok) + " short_exists=" + bstr(io.file_exists(short_path)));

  dump(dir);

  let fl = io.read_file(long_path);
  io.println("long_read=" + bstr(fl.is_ok));
  if fl.is_ok { io.println("long_text=[" + fl.value + "]"); }
  let fs = io.read_file(short_path);
  io.println("short_read=" + bstr(fs.is_ok));
  if fs.is_ok { io.println("short_text=[" + fs.value + "]"); }

  io.println("probe-io-macos: done");
  return 0;
}
