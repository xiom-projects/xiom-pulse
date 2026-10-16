// probe -- xiom.template 0.2.0 consumer-verify (PULSE side)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Consumer-verify for the registry artifact xiom.template 0.2.0
// (eco-v0.1.186, sha256 bedd03a905f760e16f5425a1c666fb94fa16d23db77b9d7d120cc3bbc7c80580),
// requested by the packages lane (REL-20261016-1111-packages; top-tier
// item 1 -- templates/escaping). Consumes the INSTALLED registry artifact
// (no vendored copy): v0.1 placeholder surface + v0.2 block surface
// (sections, loops, inverted sections, dotted paths, auto-escaping).
// Realistic-page KATs first (a 404 page and a docs nav), exact expected
// bytes hand-computed from the SPEC. Exit code = failures (0 = green).
//
// Run (pinned v0.64.5; from this directory):
//   $env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new-20261015-2240\bin\xiom.exe"
//   $env:XIOM_STDLIB = "$env:LOCALAPPDATA\xiom-pins\stdlib-092dfa0c"
//   xiom --run probe.xi
module template_verify

use xiom.io;
use xiom.string.compare;
use xiom.template;
use xiom.template.blocks;

// BUG 17 discipline: every Str equality goes through str_compare.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  return streq(r.value, want);
}

fn err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

pub fn main() -> Int {
  var f: Int = 0;

  // -- v0.1 placeholder surface (unchanged in 0.2.0) --------------------

  // 1. Single/multi-key substitution with spaced braces.
  var k1 = Vec[Str].new();
  k1.push("name");
  k1.push("role");
  var v1 = Vec[Str].new();
  v1.push("Ada");
  v1.push("engineer");
  let r1 = template_render("Hello, {{ name }} -- {{role}}!", &k1, &v1);
  f = f + check("v0.1 placeholder render (spaced braces)", ok_is(r1, "Hello, Ada -- engineer!"));

  // 2. Strict missing key: exact Err text.
  var ke = Vec[Str].new();
  var ve = Vec[Str].new();
  let r2 = template_render("Hi {{missing}}!", &ke, &ve);
  f = f + check("v0.1 strict missing key Err", err_is(r2, "template: missing key: missing"));

  // 3. Lenient twin drops the placeholder, keeps the rest.
  let r3 = template_render_lenient("Hi {{missing}}!", &ke, &ve);
  f = f + check("v0.1 lenient missing key drops placeholder", streq(r3, "Hi !"));

  // -- block surface: realistic pages, escape on ------------------------

  var d = template_data_new();

  // 4. 404 error page KAT: user-supplied text escapes exactly.
  template_data_set_str(&mut d, "title", "Not Found");
  template_data_set_str(&mut d, "message", "5 < 6 & \"quoted\" 'x'");
  template_data_set_str(&mut d, "path", "/missing<script>");
  let page404 = "<h1>{{title}}</h1><p>{{message}}</p><code>{{path}}</code>";
  let r4 = template_render_blocks(page404, &d, true);
  f = f + check("404 page KAT: escaped user text", ok_is(r4, "<h1>Not Found</h1><p>5 &lt; 6 &amp; &quot;quoted&quot; &#39;x&#39;</p><code>/missing&lt;script&gt;</code>"));

  // 5. Docs nav: loop over items, {{.}} is the item, parent context for
  //    the non-dot key ({{unit}} resolves against the parent).
  var nav = Vec[Str].new();
  nav.push("intro");
  nav.push("install");
  nav.push("api");
  template_data_set_list(&mut d, "nav", &nav);
  template_data_set_str(&mut d, "unit", "docs");
  let navtmpl = "<ul>{{#nav}}<li><a href=\"/{{unit}}/{{.}}\">{{.}}</a></li>{{/nav}}</ul>";
  let r5 = template_render_blocks(navtmpl, &d, true);
  f = f + check("docs nav loop: item + parent context", ok_is(r5, "<ul><li><a href=\"/docs/intro\">intro</a></li><li><a href=\"/docs/install\">install</a></li><li><a href=\"/docs/api\">api</a></li></ul>"));

  // 6. Inverted sections: existing-but-empty (strict) and missing (lenient).
  var none = Vec[Str].new();
  template_data_set_list(&mut d, "empty", &none);
  let r6 = template_render_blocks("{{^empty}}<p>no results</p>{{/empty}}", &d, true);
  var ok6 = ok_is(r6, "<p>no results</p>");
  let r6l = template_render_blocks_lenient("{{^gone}}<p>fallback</p>{{/gone}}", &d, true);
  if !streq(r6l, "<p>fallback</p>") {
    ok6 = false;
  }
  f = f + check("inverted sections (empty strict, missing lenient)", ok6);

  // 7. Raw forms stay raw in escape mode; plain form escapes.
  template_data_set_str(&mut d, "html", "<b>B</b> & \"q\"");
  let r7 = template_render_blocks("{{{html}}}|{{&html}}|{{html}}", &d, true);
  f = f + check("raw {{{ }}} / {{& }} vs escaped {{ }}", ok_is(r7, "<b>B</b> & \"q\"|<b>B</b> & \"q\"|&lt;b&gt;B&lt;/b&gt; &amp; &quot;q&quot;"));

  // 8. escape_html=false renders every value verbatim.
  let r8 = template_render_blocks("{{html}}", &d, false);
  f = f + check("escape_html=false is verbatim", ok_is(r8, "<b>B</b> & \"q\""));

  // 9. Bool sections: true renders once, false skips.
  template_data_set_bool(&mut d, "flag", true);
  template_data_set_bool(&mut d, "off", false);
  let r9 = template_render_blocks("{{#flag}}on{{/flag}}{{#off}}off{{/off}}", &d, true);
  f = f + check("bool sections truthy/falsy", ok_is(r9, "on"));

  // 10. Dotted paths + context stack through a dotted group.
  template_data_set_str(&mut d, "user.name", "Ada");
  template_data_set_str(&mut d, "user.address.city", "Athens");
  let r10 = template_render_blocks("{{#user}}{{name}}@{{address.city}}{{/user}}", &d, true);
  f = f + check("dotted paths + context stack", ok_is(r10, "Ada@Athens"));

  // -- strict error texts with byte offsets -----------------------------

  // 11. Unknown key, unterminated section, mismatched close: exact Errs.
  template_data_set_bool(&mut d, "open", true);
  let e1 = template_render_blocks("AB{{missing}}CD", &d, true);
  var ok11 = err_is(e1, "template: unknown key: missing at byte 2");
  let e2 = template_render_blocks("x{{#open}}y", &d, true);
  if !err_is(e2, "template: unterminated section 'open' at byte 1") {
    ok11 = false;
  }
  let e3 = template_render_blocks("{{#flag}}{{/nav}}", &d, true);
  if !err_is(e3, "template: mismatched close 'nav' at byte 9 (expected 'flag')") {
    ok11 = false;
  }
  f = f + check("strict error texts + byte offsets", ok11);

  // 12. Lenient never fails: unknown dropped, unterminated completed.
  let l1 = template_render_blocks_lenient("A{{missing}}B", &d, true);
  var ok12 = streq(l1, "AB");
  let l2 = template_render_blocks_lenient("x{{#flag}}y", &d, true);
  if !streq(l2, "xy") {
    ok12 = false;
  }
  f = f + check("lenient: unknown dropped, unterminated completed", ok12);

  // 13. Data accessors + kind constants.
  var kd: Int = template_data_kind(&d, "title");
  var kb: Int = template_data_kind(&d, "flag");
  var kl: Int = template_data_kind(&d, "nav");
  var ok13 = kd == TEMPLATE_VALUE_STR;
  if kb != TEMPLATE_VALUE_BOOL {
    ok13 = false;
  }
  if kl != TEMPLATE_VALUE_LIST {
    ok13 = false;
  }
  if template_data_kind(&d, "nope") != -1 {
    ok13 = false;
  }
  if !template_data_has(&d, "title") {
    ok13 = false;
  }
  if template_data_has(&d, "user") {
    ok13 = false;
  }
  f = f + check("data accessors + kind constants", ok13);

  // 14. UTF-8 passes through byte-exact (loops + escape mode).
  var us = Vec[Str].new();
  us.push("é");
  us.push("✓");
  us.push("日本");
  template_data_set_list(&mut d, "us", &us);
  template_data_set_str(&mut d, "w", "café");
  let r14 = template_render_blocks("{{w}}|{{#us}}{{.}},{{/us}}", &d, true);
  f = f + check("UTF-8 byte-exact passthrough", ok_is(r14, "café|é,✓,日本,"));

  // 15. Empty template = Ok "" on both surfaces.
  let r15a = template_render_blocks("", &d, true);
  var ok15 = ok_is(r15a, "");
  let r15b = template_render("", &ke, &ve);
  if !ok_is(r15b, "") {
    ok15 = false;
  }
  f = f + check("empty template renders empty (blocks + v0.1)", ok15);

  io.println("template-verify: FAILS=" + f.to_str());
  return f;
}
