// XIOM PULSE -- shared HTML escaping helper (site surface, P0 safety).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One escape function for handlers that build HTML by hand. Template users
// get the same mapping from xiom.template's auto-escape path; both escape
// & < > " ' so text and quoted attribute values are safe. The function is
// byte-wise and copies every other byte verbatim, so UTF-8 passes through
// unchanged. It is NOT a sanitiser: it does not strip tags or decode
// entities, and raw output ({{{...}}} in templates) must only receive
// trusted, already-safe fragments.

module xiom.pulse.html

use xiom.string.builder;

/// html_escape escapes &, <, >, " and ' as HTML entities. Use it for any
/// untrusted value interpolated into HTML text or a quoted attribute.
/// Complexity: O(n). Pure.
pub fn html_escape(s: Str) -> Str {
  var sb = builder.sb_new();
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b == 38u8 {
      builder.sb_push_str(&mut sb, "&amp;");
    } elif b == 60u8 {
      builder.sb_push_str(&mut sb, "&lt;");
    } elif b == 62u8 {
      builder.sb_push_str(&mut sb, "&gt;");
    } elif b == 34u8 {
      builder.sb_push_str(&mut sb, "&quot;");
    } elif b == 39u8 {
      builder.sb_push_str(&mut sb, "&#39;");
    } else {
      builder.sb_push_byte(&mut sb, b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}
