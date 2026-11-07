// XIOM PULSE -- password credential tests (PBKDF2 record + JSONL store).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Functional cases use 1000 iterations for speed. Exactly one 600,000
// iteration derivation is performed at the end to report production timing;
// it is NOT a second 600k verify.
module users_test

use xiom.io;
use xiom.string;
use xiom.convert;
use xiom.time;
use xiom.pulse.users;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn flip_hex(s: Str) -> Str {
  if s.len() == 0 { return s; }
  let first = string.str_slice(s, 0, 1);
  var repl = "0";
  if first == "0" { repl = "1"; }
  return repl + string.str_slice(s, 1, s.len());
}

pub fn main() -> Int {
  var failures: Int = 0;
  let dir = "probe-logs/users-test-" + convert.int_to_string(time.unix_timestamp())
    + "-" + convert.int_to_string(time.monotonic_ms());
  let _cd = io.create_dir_all(dir);
  let path = dir + "/pulse-users.jsonl";
  let pw = "correct horse battery staple";

  // --- hash / verify / parse -------------------------------------------------
  let h1 = users.password_hash(pw, 1000);
  failures = failures + check("hash ok", h1.is_ok);
  var enc: Str = "";
  if h1.is_ok { enc = h1.value; }
  let p1 = users.password_parse(enc);
  failures = failures + check("parse ok", p1.is_ok);
  var salt_hex: Str = "";
  var hash_hex: Str = "";
  if p1.is_ok {
    salt_hex = p1.value.salt_hex;
    hash_hex = p1.value.hash_hex;
    failures = failures + check("algorithm tag", p1.value.alg == "pbkdf2-sha256");
    failures = failures + check("iterations parsed", p1.value.iterations == 1000);
    failures = failures + check("salt is 16 bytes", salt_hex.len() == 32);
    failures = failures + check("key is 32 bytes", hash_hex.len() == 64);
  }
  let v1 = users.password_verify(pw, enc);
  failures = failures + check("verify ok", v1.ok);
  failures = failures + check("low iterations flag rehash", v1.needs_rehash);
  failures = failures + check("empty password false", !users.password_verify("", enc).ok);
  failures = failures + check("wrong password false", !users.password_verify("wrong password", enc).ok);
  failures = failures + check("unknown user false", !users.users_verify(path, pw, pw).ok);

  // --- salt uniqueness -------------------------------------------------------
  var salts: Vec[Str] = Vec[Str].new();
  var si: Int = 0;
  while si < 8 {
    let h = users.password_hash(pw, 1000);
    if h.is_ok {
      let p = users.password_parse(h.value);
      if p.is_ok { salts.push(p.value.salt_hex); }
    }
    si = si + 1;
  }
  failures = failures + check("salt sample count", salts.len() == 8);
  var distinct: Bool = true;
  var a: Int = 0;
  while a < salts.len() {
    var b: Int = a + 1;
    while b < salts.len() {
      if salts[a] == salts[b] { distinct = false; }
      b = b + 1;
    }
    a = a + 1;
  }
  failures = failures + check("salt uniqueness", distinct);

  // --- tamper ----------------------------------------------------------------
  let flip_hash = users.password_encode(1000, salt_hex, flip_hex(hash_hex));
  var flip_hash_s: Str = "";
  if flip_hash.is_ok { flip_hash_s = flip_hash.value; }
  failures = failures + check("tampered hash false", !users.password_verify(pw, flip_hash_s).ok);
  let flip_salt = users.password_encode(1000, flip_hex(salt_hex), hash_hex);
  var flip_salt_s: Str = "";
  if flip_salt.is_ok { flip_salt_s = flip_salt.value; }
  failures = failures + check("tampered salt false", !users.password_verify(pw, flip_salt_s).ok);
  let flip_iter_s = string.str_replace_all(enc, "$1000$", "$1001$");
  failures = failures + check("tampered iterations false", !users.password_verify(pw, flip_iter_s).ok);
  failures = failures + check("truncated record false", !users.password_verify(pw, string.str_slice(enc, 0, enc.len() - 1)).ok);

  // --- unknown algorithm / malformed ----------------------------------------
  let unknown = "pbkdf2-sha1$1000$" + salt_hex + "$" + hash_hex;
  failures = failures + check("unknown algorithm parse err", users.password_parse(unknown).is_err);
  failures = failures + check("unknown algorithm verify false", !users.password_verify(pw, unknown).ok);

  var malformed: Vec[Str] = Vec[Str].new();
  malformed.push("");
  malformed.push("pbkdf2-sha256$0$" + salt_hex + "$" + hash_hex);
  malformed.push("pbkdf2-sha256$01000$" + salt_hex + "$" + hash_hex);
  malformed.push("pbkdf2-sha256$abc$" + salt_hex + "$" + hash_hex);
  malformed.push("pbkdf2-sha256$-1$" + salt_hex + "$" + hash_hex);
  malformed.push("pbkdf2-sha256$1000$" + salt_hex);
  malformed.push("pbkdf2-sha256$1000$" + salt_hex + "$" + hash_hex + "$extra");
  malformed.push("pbkdf2-sha256$1000$" + string.str_repeat("A", 32) + "$" + hash_hex);
  malformed.push("pbkdf2-sha256$1000$" + salt_hex + "$" + string.str_repeat("g", 64));
  malformed.push("pbkdf2-sha256$999999999999$" + salt_hex + "$" + hash_hex);
  let m_bad = "pbkdf2-sha256$1000$" + salt_hex + "$" + hash_hex;
  failures = failures + check("valid control parses", users.password_parse(m_bad).is_ok);
  var mi: Int = 0;
  while mi < malformed.len() {
    let mr = users.password_parse(malformed[mi]);
    failures = failures + check("malformed reject " + convert.int_to_string(mi), mr.is_err);
    failures = failures + check("malformed verify false " + convert.int_to_string(mi), !users.password_verify(pw, malformed[mi]).ok);
    mi = mi + 1;
  }

  // --- iteration floor (parse-only; no KDF) ---------------------------------
  let at_floor = users.password_encode(600000, salt_hex, hash_hex);
  if at_floor.is_ok {
    failures = failures + check("floor not rehash", !users.password_needs_rehash(at_floor.value));
  } else {
    failures = failures + check("floor encode ok", false);
  }
  let below_floor = users.password_encode(599999, salt_hex, hash_hex);
  if below_floor.is_ok {
    failures = failures + check("below floor needs rehash", users.password_needs_rehash(below_floor.value));
  } else {
    failures = failures + check("below floor encode ok", false);
  }
  let tiny = users.password_encode(1, salt_hex, hash_hex);
  if tiny.is_ok {
    failures = failures + check("1 iteration needs rehash", users.password_needs_rehash(tiny.value));
  }
  failures = failures + check("malformed needs rehash", users.password_needs_rehash("bad"));
  failures = failures + check("encode rejects zero", users.password_encode(0, salt_hex, hash_hex).is_err);
  failures = failures + check("encode rejects too many iterations", users.password_encode(10000001, salt_hex, hash_hex).is_err);
  failures = failures + check("hash rejects too many iterations", users.password_hash(pw, 10000001).is_err);

  // --- oversize password -----------------------------------------------------
  let maxpw = string.str_repeat("x", 1024);
  let overpw = string.str_repeat("x", 1025);
  failures = failures + check("1024-byte password accepted", users.password_hash(maxpw, 1000).is_ok);
  failures = failures + check("1025-byte hash rejected", users.password_hash(overpw, 1000).is_err);
  failures = failures + check("1025-byte verify false", !users.password_verify(overpw, enc).ok);

  // --- JSONL store -----------------------------------------------------------
  let cr = users.users_create(path, "alice", pw, 1000);
  failures = failures + check("store create", cr.is_ok);
  let ld = users.users_load(path);
  failures = failures + check("store load ok", ld.ok);
  failures = failures + check("store one record", ld.ok && ld.records.len() == 1);
  let sv = users.users_verify(path, "alice", pw);
  failures = failures + check("store verify", sv.ok);
  failures = failures + check("store flags rehash", sv.needs_rehash);
  failures = failures + check("store wrong password", !users.users_verify(path, "alice", "nope").ok);
  failures = failures + check("store unknown user", !users.users_verify(path, "bob", pw).ok);
  let raw = io.read_file(path);
  failures = failures + check("store readable", raw.is_ok);
  if raw.is_ok {
    failures = failures + check("no plaintext in store", !string.str_contains(raw.value, pw));
    failures = failures + check("versioned credential present", string.str_contains(raw.value, "pbkdf2-sha256$1000$"));
  }
  failures = failures + check("duplicate create rejected", users.users_create(path, "alice", pw, 1000).is_err);

  var one_line: Str = "";
  let lines = io.read_file_lines(path);
  if lines.is_ok && lines.value.len() > 0 { one_line = lines.value[0]; }
  let dup_path = dir + "/dupes.jsonl";
  let _dw = io.write_file(dup_path, one_line + "\n" + one_line + "\n");
  failures = failures + check("duplicate records rejected", !users.users_load(dup_path).ok);

  let bad_path = dir + "/bad.jsonl";
  let _bw = io.write_file(bad_path, "{\"kind\":\"user\"}\n");
  failures = failures + check("malformed record rejected", !users.users_load(bad_path).ok);

  let torn_path = dir + "/torn.jsonl";
  let _tw = io.write_file(torn_path, one_line + "\n{\"kind\":\"user\"");
  failures = failures + check("torn record rejected", !users.users_load(torn_path).ok);

  let v2_path = dir + "/v2.jsonl";
  let v2_content = string.str_replace_all(one_line, "\"v\":1", "\"v\":2");
  let _v2w = io.write_file(v2_path, v2_content + "\n");
  failures = failures + check("unknown record version rejected", !users.users_load(v2_path).ok);

  let alg_path = dir + "/alg.jsonl";
  let alg_content = string.str_replace_all(one_line, "pbkdf2-sha256$", "pbkdf2-sha1$");
  let _algw = io.write_file(alg_path, alg_content + "\n");
  failures = failures + check("unknown store algorithm rejected", !users.users_load(alg_path).ok);

  let disabled_path = dir + "/disabled.jsonl";
  var disabled_content: Str = one_line + "\n";
  if raw.is_ok {
    disabled_content = string.str_replace_all(raw.value, "\"status\":\"active\"", "\"status\":\"disabled\"");
  }
  let _dpw = io.write_file(disabled_path, disabled_content);
  failures = failures + check("disabled store loads", users.users_load(disabled_path).ok);
  failures = failures + check("disabled user verify false", !users.users_verify(disabled_path, "alice", pw).ok);

  // --- rehash ----------------------------------------------------------------
  let rr = users.users_rehash(path, "alice", pw, 2000);
  failures = failures + check("rehash ok", rr.is_ok);
  if rr.is_ok { failures = failures + check("rehash happened", rr.value); }
  let ld2 = users.users_load(path);
  failures = failures + check("rehash keeps one record", ld2.ok && ld2.records.len() == 1);
  if ld2.ok && ld2.records.len() == 1 {
    let p2 = users.password_parse(ld2.records[0].cred);
    failures = failures + check("rehash parse", p2.is_ok);
    if p2.is_ok {
      failures = failures + check("rehash iterations", p2.value.iterations == 2000);
      failures = failures + check("rehash fresh salt", p2.value.salt_hex != salt_hex);
    }
  }
  failures = failures + check("rehash verify", users.users_verify(path, "alice", pw).ok);
  let rr2 = users.users_rehash(path, "alice", pw, 2000);
  failures = failures + check("rehash noop at target", rr2.is_ok && !rr2.value);
  failures = failures + check("rehash wrong password err", users.users_rehash(path, "alice", "wrong", 3000).is_err);
  failures = failures + check("rehash unknown user err", users.users_rehash(path, "bob", pw, 3000).is_err);

  // --- one production-cost 600k derivation ----------------------------------
  let t0 = time.monotonic_ms();
  let prod = users.password_hash(pw, 600000);
  let t1 = time.monotonic_ms();
  let elapsed = t1 - t0;
  failures = failures + check("600k hash ok", prod.is_ok);
  io.println("TIMING: pbkdf2-sha256 600000 iterations = " + convert.int_to_string(elapsed) + " ms");
  if prod.is_ok {
    let pp = users.password_parse(prod.value);
    failures = failures + check("600k parse ok", pp.is_ok);
    if pp.is_ok {
      failures = failures + check("600k iterations", pp.value.iterations == 600000);
      failures = failures + check("600k at floor", !users.password_needs_rehash(prod.value));
    }
  }

  if failures == 0 {
    io.println("pulse-users: GREEN");
  } else {
    io.println("pulse-users: FAILED=" + convert.int_to_string(failures));
  }
  return failures;
}
