// XIOM PULSE -- deterministic cookie/auth fuzz harness (WP2 assurance).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Seeds a PCG generator and drives the cookie/auth surface with curated
// cases plus random header values:
//   * xiom.cookie.cookie_parse_request -> cookie_serialize_request,
//   * xiom.cookie.cookie_parse_set -> cookie_serialize_set,
//   * xiom.pulse.sessions session/csrf helpers.
//
// Header contract: random inputs are single header VALUES, so the generator
// never emits CR, LF or NUL. Any raw CR/LF/NUL in a serialized header is
// therefore serializer-introduced and a finding. A curated CRLF request
// Cookie value exercises the parser's own behaviour: if the parser preserves
// the CRLF, the harness reports it as a finding (it does not fix the parser).
//
// Tunables (env): FUZZ_COOKIE_SEED (default 1592594004),
// FUZZ_COOKIE_ITERS (20000), FUZZ_COOKIE_ALLOW_CRLF (0 = strict). Setting
// FUZZ_COOKIE_ALLOW_CRLF=1 records the known CRLF-preservation finding in
// known_crlf instead of failing, mirroring FUZZ_STRICT_NUL in fuzz_parsers.
// Exit code 0 = green, 1 = failures.
//
// Run: scripts\fuzz_cookie.ps1   (or build + out\fuzz_cookie.exe)

module fuzz_cookie

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert.parse;
use xiom.rand.pcg;
use xiom.cookie;
use xiom.pulse.sessions;

// Cap printed findings so a broad failure does not flood the log.
var logged: Int = 0;

fn fail(where: Str, detail: Str) -> Int {
  if logged < 20 {
    io.println("[FUZZ-FAIL] " + where + ": " + detail);
    logged = logged + 1;
  }
  return 1;
}

fn rint(r: &mut pcg.Pcg, lo: Int, hi: Int) -> Int {
  if hi <= lo { return lo; }
  return lo + pcg.pcg_next_bounded(r, hi - lo);
}

fn hex_char(n: Int) -> UInt8 {
  if n < 10 { return ((48 + n) as UInt8); }
  return ((87 + n) as UInt8);
}

/// dump_str renders up to 256 bytes as printable ASCII or \xNN so a fuzz
/// finding can be replayed. Complexity: O(n). Pure.
fn dump_str(s: Str) -> Str {
  var sb = builder.sb_new();
  var i: Int = 0;
  while i < s.len() && i < 256 {
    let b = s.byte_at(i);
    if b >= 32u8 && b <= 126u8 && b != 92u8 {
      builder.sb_push_byte(&mut sb, b);
    } else {
      builder.sb_push_str(&mut sb, "\\x");
      builder.sb_push_byte(&mut sb, hex_char((b as Int) / 16));
      builder.sb_push_byte(&mut sb, hex_char((b as Int) % 16));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// has_ctl reports raw CR, LF or NUL. Complexity: O(n). Pure.
fn has_ctl(s: Str) -> Bool {
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b == 13u8 || b == 10u8 || b == 0u8 { return true; }
    i = i + 1;
  }
  return false;
}

/// has_crlf reports raw CR or LF. Complexity: O(n). Pure.
fn has_crlf(s: Str) -> Bool {
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b == 13u8 || b == 10u8 { return true; }
    i = i + 1;
  }
  return false;
}

fn is_hex_lower_byte(b: UInt8) -> Bool {
  if b >= 48u8 && b <= 57u8 { return true; }
  if b >= 97u8 && b <= 102u8 { return true; }
  return false;
}

fn is_lower_hex(s: Str) -> Bool {
  var i: Int = 0;
  while i < s.len() {
    if !is_hex_lower_byte(s.byte_at(i)) { return false; }
    i = i + 1;
  }
  return true;
}

fn name_alphabet() -> Str {
  return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-";
}

// Values may contain '=' (the first '=' splits the pair) but never ';'
// because ';' is the pair separator. No CR/LF/NUL.
fn value_alphabet() -> Str {
  return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 =,.%+-_:/@[]{}<>?!#$&*^|";
}

// Cookie-alphabet adds ';' and '=' so the raw-random mode exercises the
// request parser's pair splitter too.
fn cookie_alphabet() -> Str {
  return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 =;,.%+-_:/@[]{}<>?!#$&*^|";
}

fn path_alphabet() -> Str {
  return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /.-_";
}

fn attr_alphabet() -> Str {
  return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 =.-_";
}

fn random_text(r: &mut pcg.Pcg, alphabet: Str, lo: Int, hi: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  let n = rint(r, lo, hi);
  let alen = alphabet.len();
  var i: Int = 0;
  while i < n {
    out.push(alphabet.byte_at(rint(r, 0, alen)));
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// random_cookie builds a single Cookie header value: mostly structured
/// "name=value" segments (so duplicates, empty names, empty values and
/// missing '=' are all reachable) with an occasional fully random line.
/// It never emits CR, LF or NUL. Complexity: O(n). Pure.
fn random_cookie(r: &mut pcg.Pcg) -> Str {
  if rint(r, 0, 5) == 0 {
    return random_text(r, cookie_alphabet(), 0, 193);
  }
  var sb = builder.sb_new();
  let pairs = rint(r, 0, 9);
  var i: Int = 0;
  while i < pairs {
    if i > 0 { builder.sb_push_str(&mut sb, "; "); }
    let nm = random_text(r, name_alphabet(), 0, 10);
    builder.sb_push_str(&mut sb, nm);
    if rint(r, 0, 6) != 0 {
      builder.sb_push_str(&mut sb, "=");
      builder.sb_push_str(&mut sb, random_text(r, value_alphabet(), 0, 20));
    }
    if rint(r, 0, 4) == 0 { builder.sb_push_str(&mut sb, "  "); }
    i = i + 1;
  }
  if pairs == 0 && rint(r, 0, 2) == 0 {
    builder.sb_push_str(&mut sb, random_text(r, cookie_alphabet(), 0, 32));
  }
  return builder.sb_to_str(&sb);
}

/// random_set_cookie builds a single Set-Cookie header value. The first pair
/// is malformed on purpose sometimes; attributes cover the recognised names
/// plus unknown junk. It never emits CR, LF or NUL. Complexity: O(n). Pure.
fn random_set_cookie(r: &mut pcg.Pcg) -> Str {
  var sb = builder.sb_new();
  if rint(r, 0, 8) == 0 {
    if rint(r, 0, 2) == 0 {
      builder.sb_push_str(&mut sb, random_text(r, name_alphabet(), 0, 8));
    } else {
      builder.sb_push_str(&mut sb, "=");
      builder.sb_push_str(&mut sb, random_text(r, value_alphabet(), 0, 12));
    }
  } else {
    builder.sb_push_str(&mut sb, random_text(r, name_alphabet(), 1, 10));
    builder.sb_push_str(&mut sb, "=");
    builder.sb_push_str(&mut sb, random_text(r, value_alphabet(), 0, 24));
  }
  let attrs = rint(r, 0, 6);
  var i: Int = 0;
  while i < attrs {
    builder.sb_push_str(&mut sb, "; ");
    let pick = rint(r, 0, 10);
    if pick == 0 {
      builder.sb_push_str(&mut sb, "Path=");
      builder.sb_push_str(&mut sb, random_text(r, path_alphabet(), 0, 12));
    } elif pick == 1 {
      builder.sb_push_str(&mut sb, "Domain=");
      builder.sb_push_str(&mut sb, random_text(r, path_alphabet(), 0, 12));
    } elif pick == 2 {
      builder.sb_push_str(&mut sb, "Max-Age=");
      builder.sb_push_str(&mut sb, random_text(r, "0123456789+-", 0, 12));
    } elif pick == 3 {
      builder.sb_push_str(&mut sb, "Secure");
    } elif pick == 4 {
      builder.sb_push_str(&mut sb, "HttpOnly");
    } elif pick == 5 {
      builder.sb_push_str(&mut sb, "SameSite=");
      builder.sb_push_str(&mut sb, random_text(r, "StrictLaxNone", 0, 8));
    } else {
      builder.sb_push_str(&mut sb, random_text(r, attr_alphabet(), 0, 12));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// The "~~" prefix is outside the cookie alphabets above, so a random cookie
// value can never equal this token; csrf_matches must therefore be false.
fn random_csrf_token(r: &mut pcg.Pcg) -> Str {
  return "~~" + random_text(r, "abcdefghijklmnopqrstuvwxyz0123456789", 1, 33);
}

fn known_set_error(e: Str) -> Bool {
  return compare.str_compare(e, "cookie: missing name=value pair") == 0 ||
         compare.str_compare(e, "cookie: empty cookie name") == 0;
}

/// curated_request checks the documented round-trip, an overlong/odd line
/// (must not trap) and the CRLF injection attempt. Returns (failures,
/// known_crlf); known_crlf is non-zero only when the parser preserved CRLF and
/// the caller opted to track it instead of failing.
fn curated_request(allow_crlf: Bool) -> (Int, Int) {
  var f: Int = 0;
  var known_crlf: Int = 0;

  let rt_in = "sid=abc; theme=dark";
  let rt_jar = cookie.cookie_parse_request(rt_in);
  let rt_out = cookie.cookie_serialize_request(&rt_jar);
  if compare.str_compare(rt_out, rt_in) != 0 {
    f = f + fail("cookie request round-trip", "in=" + dump_str(rt_in) + " out=" + dump_str(rt_out));
  }
  let sid_opt = cookie.cookie_get(&rt_jar, "sid");
  if sid_opt.is_none {
    f = f + fail("cookie request round-trip missing sid", dump_str(rt_in));
  } else {
    let sid_val: Str = sid_opt.value;
    if compare.str_compare(sid_val, "abc") != 0 {
      f = f + fail("cookie request round-trip sid value", "got=" + dump_str(sid_val));
    }
  }

  let overlong = "x=" + string.str_repeat("A", 4096) + "; ;=; y=odd value; dup=1; dup=2; trailing=";
  let oj = cookie.cookie_parse_request(overlong);
  let oo = cookie.cookie_serialize_request(&oj);
  if has_ctl(oo) {
    f = f + fail("cookie overlong serialization emitted CR/LF/NUL", dump_str(oo));
  }
  if cookie.cookie_count(&oj) < 2 {
    f = f + fail("cookie overlong jar lost entries", "count=" + cookie.cookie_count(&oj).to_str());
  }
  let dup_opt = cookie.cookie_get(&oj, "dup");
  if dup_opt.is_none {
    f = f + fail("cookie overlong missing dup", dump_str(overlong));
  } else {
    let dup_val: Str = dup_opt.value;
    if compare.str_compare(dup_val, "1") != 0 {
      f = f + fail("cookie duplicate first-occurrence-wins", "got=" + dump_str(dup_val));
    }
  }

  let inj_in = "sid=abc\r\nX-Injected: 1; theme=dark";
  let inj_jar = cookie.cookie_parse_request(inj_in);
  let inj_out = cookie.cookie_serialize_request(&inj_jar);
  if has_crlf(inj_out) {
    if allow_crlf {
      known_crlf = known_crlf + 1;
    } else {
      f = f + fail("cookie request CRLF preserved (header injection)", "in=" + dump_str(inj_in) + " out=" + dump_str(inj_out));
    }
  }
  return (f, known_crlf);
}

fn curated_set() -> Int {
  var f: Int = 0;
  let ok_line = "sid=abc; Path=/; Domain=example.com; Max-Age=3600; Secure; HttpOnly; SameSite=Lax";
  let r = cookie.cookie_parse_set(ok_line);
  if !r.is_ok {
    f = f + fail("cookie set curated parse", r.error);
  } else {
    let c = r.value;
    let out = cookie.cookie_serialize_set(&c);
    if has_ctl(out) {
      f = f + fail("cookie set curated serialization emitted CR/LF/NUL", dump_str(out));
    }
    if c.max_age != 3600 { f = f + fail("cookie set max-age", c.max_age.to_str()); }
    if !c.secure || !c.http_only { f = f + fail("cookie set flags", "secure=" + c.secure.to_str() + " http_only=" + c.http_only.to_str()); }
    if compare.str_compare(c.same_site, "Lax") != 0 { f = f + fail("cookie set samesite", dump_str(c.same_site)); }
    if !string.str_contains(out, "Max-Age=3600") || !string.str_contains(out, "SameSite=Lax") {
      f = f + fail("cookie set serialization shape", dump_str(out));
    }
  }
  let bad1 = cookie.cookie_parse_set("noequals");
  if bad1.is_ok {
    f = f + fail("cookie set missing pair accepted", "noequals");
  } else if !known_set_error(bad1.error) {
    f = f + fail("cookie set unknown error", bad1.error);
  }
  let bad2 = cookie.cookie_parse_set("=v");
  if bad2.is_ok {
    f = f + fail("cookie set empty name accepted", "=v");
  } else if !known_set_error(bad2.error) {
    f = f + fail("cookie set unknown error", bad2.error);
  }
  let bad3 = cookie.cookie_parse_set("sid=abc; Max-Age=notint");
  if !bad3.is_ok {
    f = f + fail("cookie set malformed max-age rejected", bad3.error);
  } else {
    let c3 = bad3.value;
    if c3.max_age != -1 {
      f = f + fail("cookie set malformed max-age applied", c3.max_age.to_str());
    }
  }
  return f;
}

fn curated_session() -> Int {
  var f: Int = 0;
  sessions.session_reset();
  let sid = sessions.session_id_from_cookie("a=1; sid=SESSION; b=2");
  if compare.str_compare(sid, "SESSION") != 0 {
    f = f + fail("session id from cookie", dump_str(sid));
  }
  if compare.str_compare(sessions.session_get(sid), "") != 0 {
    f = f + fail("session get fabricated a user", "sid=" + dump_str(sid));
  }
  if sessions.session_count() != 0 {
    f = f + fail("session get created a session", "count=" + sessions.session_count().to_str());
  }
  let tok = sessions.csrf_new_token();
  if tok.len() != 32 {
    f = f + fail("csrf token length", tok.len().to_str());
  } else if !is_lower_hex(tok) {
    f = f + fail("csrf token not lowercase hex", dump_str(tok));
  }
  if !sessions.csrf_matches("sid=x; csrf=" + tok + "; a=1", tok) {
    f = f + fail("csrf curated match rejected", dump_str(tok));
  }
  if sessions.csrf_matches("sid=x; csrf=" + tok, "wrong") {
    f = f + fail("csrf curated mismatch accepted", dump_str(tok));
  }
  sessions.session_reset();
  return f;
}

/// fuzz_surface runs the random request/set-cookie/session/csrf checks.
/// Returns (failures, request_iters, set_ok, set_err, session_iters,
/// csrf_iters). Complexity: O(iters * input size). Side effects: none beyond
/// the lazily-created session store (no sessions are created).
fn fuzz_surface(r: &mut pcg.Pcg, n: Int) -> (Int, Int, Int, Int, Int, Int) {
  var f: Int = 0;
  var req_iters: Int = 0;
  var set_ok: Int = 0;
  var set_err: Int = 0;
  var session_iters: Int = 0;
  var csrf_iters: Int = 0;
  sessions.session_reset();
  var i: Int = 0;
  while i < n {
    let line = random_cookie(r);
    let jar = cookie.cookie_parse_request(line);
    let out = cookie.cookie_serialize_request(&jar);
    if has_ctl(out) {
      f = f + fail("request serialization emitted CR/LF/NUL", "iter=" + i.to_str() + " in=" + dump_str(line) + " out=" + dump_str(out));
    }
    if jar.names.len() != jar.values.len() {
      f = f + fail("request jar vectors out of step", "iter=" + i.to_str() + " names=" + jar.names.len().to_str() + " values=" + jar.values.len().to_str());
    }
    if cookie.cookie_count(&jar) > line.len() {
      f = f + fail("request count exceeds input length", "iter=" + i.to_str());
    }
    req_iters = req_iters + 1;

    let set_line = random_set_cookie(r);
    let sr = cookie.cookie_parse_set(set_line);
    if sr.is_ok {
      let c = sr.value;
      let set_out = cookie.cookie_serialize_set(&c);
      if has_ctl(set_out) {
        f = f + fail("set-cookie serialization emitted CR/LF/NUL", "iter=" + i.to_str() + " in=" + dump_str(set_line) + " out=" + dump_str(set_out));
      }
      if c.name.len() == 0 {
        f = f + fail("set-cookie Ok with empty name", "iter=" + i.to_str() + " in=" + dump_str(set_line));
      }
      if set_line.len() < 2 {
        f = f + fail("set-cookie Ok on short line", "iter=" + i.to_str() + " in=" + dump_str(set_line));
      }
      set_ok = set_ok + 1;
    } else {
      if sr.error.len() == 0 || !known_set_error(sr.error) {
        f = f + fail("set-cookie unknown error", "iter=" + i.to_str() + " err=" + sr.error + " in=" + dump_str(set_line));
      }
      set_err = set_err + 1;
    }

    let sid = sessions.session_id_from_cookie(line);
    let user = sessions.session_get(sid);
    if compare.str_compare(user, "") != 0 {
      f = f + fail("session get fabricated a user for random id", "iter=" + i.to_str() + " sid=" + dump_str(sid));
    }
    session_iters = session_iters + 1;

    let tok = random_csrf_token(r);
    if sessions.csrf_matches(line, tok) {
      f = f + fail("csrf_matches(random, random) true", "iter=" + i.to_str() + " line=" + dump_str(line) + " tok=" + dump_str(tok));
    }
    csrf_iters = csrf_iters + 1;

    i = i + 1;
  }
  if sessions.session_count() != 0 {
    f = f + fail("session_get created a session", "count=" + sessions.session_count().to_str());
  }
  return (f, req_iters, set_ok, set_err, session_iters, csrf_iters);
}

fn env_int(name: Str, fallback: Int) -> Int {
  let p = parse_int(env.var_or(name, ""));
  if p.is_ok { return p.value; }
  return fallback;
}

pub fn main() -> Int {
  let seed = env_int("FUZZ_COOKIE_SEED", 1592594004);
  let n = env_int("FUZZ_COOKIE_ITERS", 20000);
  let allow_crlf = env_int("FUZZ_COOKIE_ALLOW_CRLF", 0) != 0;
  var r = pcg.pcg_from_seed(seed as UInt64);
  var f: Int = 0;
  let cr = curated_request(allow_crlf);
  f = f + cr.0;
  let known_crlf = cr.1;
  f = f + curated_set();
  f = f + curated_session();
  let res = fuzz_surface(&mut r, n);
  f = f + res.0;
  let counts = "seed=" + seed.to_str() + " iters=" + n.to_str() +
               " request=" + res.1.to_str() + " set_ok=" + res.2.to_str() +
               " set_err=" + res.3.to_str() + " session=" + res.4.to_str() +
               " csrf=" + res.5.to_str() + " known_crlf=" + known_crlf.to_str();
  if f == 0 {
    io.println("fuzz_cookie: GREEN " + counts);
    return 0;
  }
  io.println("fuzz_cookie: RED failures=" + f.to_str() + " " + counts);
  return 1;
}
