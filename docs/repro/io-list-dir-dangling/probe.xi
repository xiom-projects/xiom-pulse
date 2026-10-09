// probe_io_list_dir -- C-PULSE-17: are xiom.io.list_dir results usable
// beyond the first use? Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Observed on v0.64.2 (Windows lane stdlib AND Linux pinned 4dd8844,
// 2026-10-10): entries compare equal RIGHT AFTER the call, but their
// bytes are backed by a buffer that later allocations overwrite --
// concatenating/printing a listed name yields decimal pointer-looking
// garbage (`[2352927702944]`), and retained entries are unreliable for
// follow-up calls (PULSE test cleanup removing listed names silently
// left files behind; see the multipart wrap notes).
//
// Parts: names (immediate equality), print (concat after the call),
// remove (file removal via the listed name). Exit 0 only when all three
// are correct; 1 = defect reproduced.
//
// Run: .\scripts\run.ps1 docs\repro\io-list-dir-dangling\probe.xi
module probe_io_list_dir

use xiom.io;
use xiom.string;

pub fn main() -> Int {
  let dir = "docs/repro/io-list-dir-dangling/.tmp-lsd";
  let _mk = io.create_dir(dir);
  let _w1 = io.write_file(io.join_paths(dir, "aa.txt"), "one");
  let _w2 = io.write_file(io.join_paths(dir, "bb.txt"), "two");
  let ld = io.list_dir(dir);
  if ld.is_err {
    io.println("[FAIL] list_dir error");
    return 1;
  }
  // Part A: immediate equality (no allocations in between).
  var names_ok: Bool = ld.value.len() == 2;
  if names_ok {
    if !(ld.value[0] == "aa.txt" || ld.value[0] == "bb.txt") { names_ok = false; }
    if !(ld.value[1] == "aa.txt" || ld.value[1] == "bb.txt") { names_ok = false; }
  }
  // Part B: print/concat a listed name (allocates; may clobber).
  var shown: Str = "";
  if ld.value.len() > 0 {
    shown = "[" + ld.value[0] + "]";
  }
  var print_ok: Bool = string.str_contains(shown, "aa.txt") || string.str_contains(shown, "bb.txt");
  // Part C: remove a file via the listed name.
  var rm_ok: Bool = false;
  if ld.value.len() > 0 {
    let rm = io.remove_file(io.join_paths(dir, ld.value[0]));
    rm_ok = rm.is_ok;
  }
  // Remove the other file by known name so reruns start clean.
  let _rc = io.remove_file(io.join_paths(dir, "aa.txt"));
  let _rd = io.remove_file(io.join_paths(dir, "bb.txt"));
  io.println("names_ok=" + names_ok.to_str() + " print_ok=" + print_ok.to_str() + " rm_ok=" + rm_ok.to_str());
  io.println("shown=[" + shown + "]");
  if names_ok && print_ok && rm_ok {
    io.println("[PASS] list_dir results usable");
    return 0;
  }
  io.println("[BUG] list_dir results not usable beyond first use (C-PULSE-17)");
  return 1;
}
