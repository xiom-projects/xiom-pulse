// XIOM PULSE -- audit-trail rotation (single generation, no compression).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The audit trail grows one line per mutating request; rotation keeps a
// bound on disk use without a log daemon. Policy: when the file exceeds
// `max_bytes`, replace `<path>.1` and rename the active file to it; the
// next audit append recreates the active file.
module xiom.pulse.audit

use xiom.io;

/// audit_rotate_if_needed rotates PATH to PATH.1 when it exceeds MAX_BYTES.
/// `max_bytes <= 0` disables rotation; a missing file (or an unreadable
/// size) is a no-op. Returns false only when a rotation step failed (the
/// caller should still try the append).
/// Complexity: O(1) stat + O(1) rename.
pub fn audit_rotate_if_needed(path: Str, max_bytes: Int) -> Bool {
  if max_bytes <= 0 { return true; }
  if !io.file_exists(path) { return true; }
  let sz = io.file_size(path);
  if sz.is_none { return true; }
  if sz.value <= max_bytes { return true; }
  let backup = path + ".1";
  if io.file_exists(backup) {
    let rr = io.remove_file(backup);
    if rr.is_err { return false; }
  }
  let rn = io.rename(path, backup);
  if rn.is_err { return false; }
  return true;
}
