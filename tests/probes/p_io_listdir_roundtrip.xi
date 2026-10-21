// p_io_listdir_roundtrip.xi -- portable witness for the macOS first-byte
// list_dir/read_file report. Copy of stdlib
// tools/probes/p_io_listdir_roundtrip.xi (0bf5984) for the macOS CI witness.
// REL-20261021-0918-pulse was closed as duplicate of C-PULSE-17 /
// REL-20261010-1609-stdlib (compiler inline Result.value[i] concat), so a
// pass here means list_dir itself is fine and the migrations failure is the
// compiler/vector-copy path.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module p_io_listdir_roundtrip

use xiom.io;

fn main() -> Int {
  let dir = "__probe_listdir_roundtrip";
  let name = "20260101000002_seed.sql";
  let path = dir + "/" + name;
  let _ = remove_file(path);
  let _ = create_dir_all(dir);
  match write_file(path, "x") {
    Ok(_) => {},
    Err(_) => { return 1; },
  };

  let listing = list_dir(dir);
  if listing.is_err { let _ = remove_file(path); return 2; }
  var found = false;
  var i = 0;
  while i < listing.value.len() {
    if listing.value[i] == name { found = true; }
    i = i + 1;
  };
  if found == false {
    // Print the raw entries for the macOS CI log.
    i = 0;
    while i < listing.value.len() {
      io.println("entry[" + i.to_str() + "] len=" + listing.value[i].len().to_str() + " name=" + listing.value[i]);
      i = i + 1;
    };
    let _ = remove_file(path);
    return 3;
  }

  let body = read_file(path);
  let _ = remove_file(path);
  if body.is_err { return 4; }
  if body.value != "x" { return 5; }
  return 0;
}
