// XIOM PULSE -- password credentials: PBKDF2-HMAC-SHA256 hashing and a
// JSONL credential store.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// SECRET FILE: the JSONL store written by this module (default name
// `pulse-users.jsonl`) is a SECRET. It contains per-user salts and password
// hashes and must be treated like a private key:
//   * never commit it, never put it in resources/, dist/, or a release
//     archive, and never attach it to a bug report;
//   * keep it mode 0600 on Unix (this module sets it after every write) and
//     on a restricted-ACL path on Windows;
//   * only the provisioning/admin path and the login verification path may
//     read it; it must not be served by the static file handler.
// The store never contains a plaintext password, a hint, a pepper, or a
// session id.
//
// Credential format (versioned, strict):
//   pbkdf2-sha256$<iterations>$<32 lowercase hex salt>$<64 lowercase hex key>
// Unknown algorithms, unknown record versions, uppercase/odd hex, zero or
// non-canonical iterations, and extra `$` fields all fail closed. Verification
// uses the in-tree RFC 2898 implementation
// (`xiom.crypto.hash.crypto_hash_pbkdf2_sha256`) and a constant-time compare
// (`xiom.crypto.mac.constant_time_eq`); it never compares hex strings with
// `==`.
//
// Storage layout: one JSON object per line, one line per user (duplicates are
// rejected by users_load). Rehash rewrites the file atomically (temp file +
// rename) so the one-record-per-user invariant holds; it is not an
// append-only history log.
module xiom.pulse.users

use xiom.string;
use xiom.string.slice;
use xiom.convert;
use xiom.encoding;
use xiom.crypto.hash;
use xiom.crypto.mac;
use xiom.crypto.rng_crypto;
use xiom.serialize.json;
use xiom.io;
use xiom.time;

const PASS_ALG: Str = "pbkdf2-sha256";
const PASS_RECORD_VERSION: Int = 1;
const PASS_SALT_BYTES: Int = 16;
const PASS_KEY_BYTES: Int = 32;
const PASS_DEFAULT_ITERATIONS: Int = 600000;
const PASS_MIN_ITERATIONS: Int = 600000;
const PASS_MAX_ITERATIONS: Int = 10000000;
const PASS_MAX_PASSWORD_BYTES: Int = 1024;
const PASS_MAX_USER_BYTES: Int = 64;

/// PasswordRecord -- the parsed, validated contents of a versioned
/// credential string.
pub type PasswordRecord = {
  alg: Str;
  iterations: Int;
  salt_hex: Str;
  hash_hex: Str;
}

/// VerifyResult -- ok, plus whether a successful verify used parameters
/// below the current policy floor and should be rehashed.
pub type VerifyResult = {
  ok: Bool;
  needs_rehash: Bool;
}

/// StoredUser -- one JSONL credential record.
pub type StoredUser = {
  user: Str;
  cred: Str;
  status: Str;
  created_at: Int;
  updated_at: Int;
}

/// UserLoad -- the complete, validated store or a fail-closed error.
pub type UserLoad = {
  ok: Bool;
  error: Str;
  records: Vec[StoredUser];
}

// --- constants / small helpers ---------------------------------------------

/// password_default_iterations returns the current PBKDF2 policy floor used
/// for new records. Complexity: O(1). Pure.
pub fn password_default_iterations() -> Int {
  return PASS_DEFAULT_ITERATIONS;
}

/// password_min_iterations returns the minimum acceptable iteration count;
/// lower records still verify but are flagged for rehash.
/// Complexity: O(1). Pure.
pub fn password_min_iterations() -> Int {
  return PASS_MIN_ITERATIONS;
}

fn _is_lower_hex(s: Str, want_len: Int) -> Bool {
  if s.len() != want_len { return false; }
  var i: Int = 0;
  while i < s.len() {
    let c = s.byte_at(i);
    let digit = c >= 48u8 && c <= 57u8;
    let lower = c >= 97u8 && c <= 102u8;
    if !digit && !lower { return false; }
    i = i + 1;
  }
  return true;
}

fn _parse_iterations(s: Str) -> Result[Int, Str] {
  if s.len() < 1 || s.len() > 9 { return Err("invalid iterations"); }
  var i: Int = 0;
  var value: Int = 0;
  while i < s.len() {
    let c = s.byte_at(i);
    if c < 48u8 || c > 57u8 { return Err("invalid iterations"); }
    let digit = (c as Int) - 48;
    if i == 0 && digit == 0 { return Err("non-canonical iterations"); }
    if value > 214748364 { return Err("iterations overflow"); }
    if value == 214748364 && digit > 7 { return Err("iterations overflow"); }
    value = value * 10 + digit;
    i = i + 1;
  }
  if value < 1 { return Err("invalid iterations"); }
  if value > PASS_MAX_ITERATIONS { return Err("iterations too large"); }
  return Ok(value);
}

/// users_valid_username reports whether `user` is 1..64 bytes. The check is
/// byte-exact: no trimming, case folding, or Unicode normalization.
/// Complexity: O(1). Pure.
pub fn users_valid_username(user: Str) -> Bool {
  return user.len() >= 1 && user.len() <= PASS_MAX_USER_BYTES;
}

// --- versioned credential string -------------------------------------------

/// password_encode builds and validates the versioned credential string.
/// Complexity: O(n). Pure.
pub fn password_encode(iterations: Int, salt_hex: Str, hash_hex: Str) -> Result[Str, Str] {
  if iterations < 1 || iterations > PASS_MAX_ITERATIONS { return Err("invalid iterations"); }
  if !_is_lower_hex(salt_hex, PASS_SALT_BYTES * 2) { return Err("invalid salt encoding"); }
  if !_is_lower_hex(hash_hex, PASS_KEY_BYTES * 2) { return Err("invalid hash encoding"); }
  return Ok(PASS_ALG + "$" + convert.int_to_string(iterations) + "$" + salt_hex + "$" + hash_hex);
}

/// password_parse strictly parses a credential string. Unknown algorithms,
/// bad field counts, non-canonical iterations, and non-lowercase or
/// wrong-length hex all return Err (fail closed).
/// Complexity: O(n). Pure.
pub fn password_parse(encoded: Str) -> Result[PasswordRecord, Str] {
  if encoded.len() == 0 { return Err("empty credential"); }
  let parts = string.str_split(encoded, "$");
  if parts.len() != 4 { return Err("invalid credential format"); }
  if parts[0] != PASS_ALG { return Err("unknown algorithm"); }
  let ir = _parse_iterations(parts[1]);
  if ir.is_err { return Err(ir.error); }
  if !_is_lower_hex(parts[2], PASS_SALT_BYTES * 2) { return Err("invalid salt encoding"); }
  if !_is_lower_hex(parts[3], PASS_KEY_BYTES * 2) { return Err("invalid hash encoding"); }
  return Ok(PasswordRecord{
    alg: parts[0];
    iterations: ir.value;
    salt_hex: parts[2];
    hash_hex: parts[3];
  });
}

/// password_needs_rehash reports whether a parsed record is below the
/// iteration floor. Malformed credentials return true: the caller must
/// replace them rather than trust them.
/// Complexity: O(n). Pure.
pub fn password_needs_rehash(encoded: Str) -> Bool {
  let pr = password_parse(encoded);
  if pr.is_err { return true; }
  return pr.value.iterations < PASS_MIN_ITERATIONS;
}

// --- hashing / verification ------------------------------------------------

/// password_hash derives a new credential with a fresh 16-byte CSPRNG salt
/// and a 32-byte key. `iterations` is configurable; new production records
/// should use password_default_iterations(). Empty or >1024-byte passwords
/// and a failed/short CSPRNG draw are Err (fail closed).
/// Complexity: O(iterations).
pub fn password_hash(password: Str, iterations: Int) -> Result[Str, Str] {
  if password.len() < 1 { return Err("empty password"); }
  if password.len() > PASS_MAX_PASSWORD_BYTES { return Err("password too long"); }
  if iterations < 1 || iterations > PASS_MAX_ITERATIONS { return Err("invalid iterations"); }
  let salt = rng_crypto.crypto_random_bytes(PASS_SALT_BYTES);
  if salt.len() != PASS_SALT_BYTES { return Err("csprng unavailable"); }
  let pwd = slice.str_bytes(password);
  let key = hash.crypto_hash_pbkdf2_sha256(&pwd, &salt, iterations, PASS_KEY_BYTES);
  if key.len() != PASS_KEY_BYTES { return Err("kdf failure"); }
  return password_encode(iterations, encoding.hex_encode(&salt), encoding.hex_encode(&key));
}

/// password_verify checks a password against a credential string. Wrong
/// passwords, malformed/tampered records, unknown algorithms, empty or
/// >1024-byte passwords all return ok=false. `needs_rehash` is true only on
/// a successful verify whose iteration count is below the floor.
/// Complexity: O(iterations).
pub fn password_verify(password: Str, encoded: Str) -> VerifyResult {
  let bad = VerifyResult{ ok: false; needs_rehash: false; };
  if password.len() < 1 || password.len() > PASS_MAX_PASSWORD_BYTES { return bad; }
  let pr = password_parse(encoded);
  if pr.is_err { return bad; }
  let rec = pr.value;
  let sr = encoding.hex_decode(rec.salt_hex);
  if sr.is_err { return bad; }
  let hr = encoding.hex_decode(rec.hash_hex);
  if hr.is_err { return bad; }
  let stored = hr.value;
  if sr.value.len() != PASS_SALT_BYTES { return bad; }
  if stored.len() != PASS_KEY_BYTES { return bad; }
  let pwd = slice.str_bytes(password);
  let key = hash.crypto_hash_pbkdf2_sha256(&pwd, &sr.value, rec.iterations, PASS_KEY_BYTES);
  if key.len() != PASS_KEY_BYTES { return bad; }
  if !mac.constant_time_eq(&key, &stored) { return bad; }
  return VerifyResult{ ok: true; needs_rehash: rec.iterations < PASS_MIN_ITERATIONS };
}

/// password_rehash verifies first, then returns a fresh credential with the
/// requested iteration count and a new salt. If the verified record is
/// already at/above the floor it is returned unchanged.
/// Complexity: O(iterations).
pub fn password_rehash(password: Str, encoded: Str, iterations: Int) -> Result[Str, Str] {
  if iterations < 1 || iterations > PASS_MAX_ITERATIONS { return Err("invalid iterations"); }
  let vr = password_verify(password, encoded);
  if !vr.ok { return Err("invalid credentials"); }
  if !vr.needs_rehash { return Ok(encoded); }
  return password_hash(password, iterations);
}

// --- JSONL credential store ------------------------------------------------

fn _str_opt(obj: JsonValue, key: Str) -> Option[Str] {
  let opt = json.json_get(obj, key);
  if opt.is_none { return None; }
  match opt.value {
    JsonValue.String(x) => { return Some(x); },
    _ => { return None; },
  }
}

fn _int_opt(obj: JsonValue, key: Str) -> Option[Int] {
  let opt = json.json_get(obj, key);
  if opt.is_none { return None; }
  return json.json_as_int(opt.value);
}

fn _record_line(user: Str, cred: Str, status: Str, created_at: Int, updated_at: Int) -> Str {
  return "{\"kind\":\"user\",\"v\":1,\"user\":" + json.json_stringify(json.json_string(user))
    + ",\"cred\":" + json.json_stringify(json.json_string(cred))
    + ",\"status\":" + json.json_stringify(json.json_string(status))
    + ",\"created_at\":" + convert.int_to_string(created_at)
    + ",\"updated_at\":" + convert.int_to_string(updated_at) + "}";
}

fn _parse_line(line: Str) -> Result[StoredUser, Str] {
  let pv = json.json_parse(line);
  if pv.is_err { return Err("invalid json"); }
  if json.json_type(pv.value) != "object" { return Err("record is not an object"); }
  let kind = _str_opt(pv.value, "kind");
  if kind.is_none || kind.value != "user" { return Err("invalid record kind"); }
  let ver = _int_opt(pv.value, "v");
  if ver.is_none || ver.value != PASS_RECORD_VERSION { return Err("unsupported record version"); }
  let user = _str_opt(pv.value, "user");
  if user.is_none || !users_valid_username(user.value) { return Err("invalid user"); }
  let cred = _str_opt(pv.value, "cred");
  if cred.is_none { return Err("missing credential"); }
  let pr = password_parse(cred.value);
  if pr.is_err { return Err(pr.error); }
  let status = _str_opt(pv.value, "status");
  if status.is_none { return Err("missing status"); }
  if status.value != "active" && status.value != "disabled" { return Err("invalid status"); }
  let created = _int_opt(pv.value, "created_at");
  if created.is_none || created.value < 0 { return Err("invalid created_at"); }
  let updated = _int_opt(pv.value, "updated_at");
  if updated.is_none || updated.value < 0 { return Err("invalid updated_at"); }
  return Ok(StoredUser{
    user: user.value;
    cred: cred.value;
    status: status.value;
    created_at: created.value;
    updated_at: updated.value;
  });
}

fn _write_all(path: Str, records: &Vec[StoredUser]) -> Bool {
  var content: Str = "";
  var i: Int = 0;
  while i < records.len() {
    let rec = records[i];
    content = content + _record_line(rec.user, rec.cred, rec.status, rec.created_at, rec.updated_at) + "\n";
    i = i + 1;
  }
  let tmp = path + ".tmp";
  let w = io.write_file(tmp, content);
  if w.is_err { return false; }
  let _tp = io.set_permissions(tmp, 384); // 0600
  let rn = io.rename(tmp, path);
  if rn.is_err {
    let _rm = io.remove_file(tmp);
    return false;
  }
  let _pp = io.set_permissions(path, 384); // 0600
  return true;
}

/// users_find returns the index of `user` in `records`, or -1.
/// Complexity: O(n). Pure.
pub fn users_find(records: &Vec[StoredUser], user: Str) -> Int {
  var i: Int = 0;
  while i < records.len() {
    if records[i].user == user { return i; }
    i = i + 1;
  }
  return -1;
}

/// users_load reads and validates every record. A missing/unreadable file,
/// a malformed line, an unknown kind/version/status, a bad credential, or a
/// duplicate user record makes the whole load fail closed (ok=false).
/// Complexity: O(lines).
pub fn users_load(path: Str) -> UserLoad {
  let empty = Vec[StoredUser].new();
  if path.len() == 0 { return UserLoad{ ok: false; error: "empty store path"; records: empty }; }
  let rr = io.read_file_lines(path);
  if rr.is_err { return UserLoad{ ok: false; error: "credential store unreadable"; records: empty }; }
  var out: Vec[StoredUser] = Vec[StoredUser].new();
  let lines = rr.value;
  var i: Int = 0;
  while i < lines.len() {
    let line = string.str_trim(lines[i]);
    if line.len() > 0 {
      let pr = _parse_line(line);
      if pr.is_err { return UserLoad{ ok: false; error: pr.error, records: empty }; }
      let rec = pr.value;
      if users_find(&out, rec.user) >= 0 {
        return UserLoad{ ok: false; error: "duplicate user record", records: empty };
      }
      out.push(rec);
    }
    i = i + 1;
  }
  return UserLoad{ ok: true; error: ""; records: out };
}

/// users_create appends a new active credential. The store must be absent or
/// fully valid; an existing record for the same user is rejected as a
/// duplicate. The file is created with mode 0600 via a temp file + rename.
/// Complexity: O(lines + iterations).
pub fn users_create(path: Str, user: Str, password: Str, iterations: Int) -> Result[Str, Str] {
  if path.len() == 0 { return Err("empty store path"); }
  if !users_valid_username(user) { return Err("invalid user"); }
  let exists = io.file_exists(path);
  if exists {
    let loaded = users_load(path);
    if !loaded.ok { return Err("credential store invalid: " + loaded.error); }
    if users_find(&loaded.records, user) >= 0 { return Err("duplicate user record"); }
  }
  let hr = password_hash(password, iterations);
  if hr.is_err { return Err(hr.error); }
  let now = time.unix_timestamp();
  let line = _record_line(user, hr.value, "active", now, now);
  if exists {
    let ap = io.append_line_sync(path, line);
    if ap.is_err { return Err("credential store write failed"); }
    let _pp = io.set_permissions(path, 384); // 0600
    return Ok(user);
  }
  let tmp = path + ".tmp";
  let w = io.write_file(tmp, line + "\n");
  if w.is_err { return Err("credential store write failed"); }
  let _tp = io.set_permissions(tmp, 384); // 0600
  let rn = io.rename(tmp, path);
  if rn.is_err {
    let _rm = io.remove_file(tmp);
    return Err("credential store create failed");
  }
  let _pp = io.set_permissions(path, 384); // 0600
  return Ok(user);
}

/// users_verify looks up an active user and verifies the password. Missing
/// store, unknown user, disabled user, and bad password all return
/// ok=false with the same shape (callers return one generic error).
/// Complexity: O(lines + iterations).
pub fn users_verify(path: Str, user: Str, password: Str) -> VerifyResult {
  let bad = VerifyResult{ ok: false; needs_rehash: false; };
  if !users_valid_username(user) { return bad; }
  let loaded = users_load(path);
  if !loaded.ok { return bad; }
  let idx = users_find(&loaded.records, user);
  if idx < 0 { return bad; }
  let rec = loaded.records[idx];
  if rec.status != "active" { return bad; }
  return password_verify(password, rec.cred);
}

/// users_rehash verifies the current password and, when the record is below
/// the requested iterations or the policy floor, atomically rewrites the
/// store with a fresh salt and the new iteration count. Returns true when a
/// rewrite happened, false when the record was already at/above policy.
/// Wrong passwords, unknown/disabled users, and invalid stores are Err.
/// Complexity: O(lines + iterations).
pub fn users_rehash(path: Str, user: Str, password: Str, iterations: Int) -> Result[Bool, Str] {
  if iterations < 1 || iterations > PASS_MAX_ITERATIONS { return Err("invalid iterations"); }
  let loaded = users_load(path);
  if !loaded.ok { return Err("credential store invalid: " + loaded.error); }
  let idx = users_find(&loaded.records, user);
  if idx < 0 { return Err("unknown user"); }
  let rec = loaded.records[idx];
  if rec.status != "active" { return Err("user is disabled"); }
  let vr = password_verify(password, rec.cred);
  if !vr.ok { return Err("invalid credentials"); }
  let pr = password_parse(rec.cred);
  if pr.is_err { return Err(pr.error); }
  if pr.value.iterations >= iterations {
    return Ok(false);
  }
  let hr = password_hash(password, iterations);
  if hr.is_err { return Err(hr.error); }
  var updated: Vec[StoredUser] = Vec[StoredUser].new();
  let now = time.unix_timestamp();
  var i: Int = 0;
  while i < loaded.records.len() {
    if i == idx {
      updated.push(StoredUser{
        user: rec.user;
        cred: hr.value;
        status: rec.status;
        created_at: rec.created_at;
        updated_at: now;
      });
    } else {
      updated.push(loaded.records[i]);
    }
    i = i + 1;
  }
  if !_write_all(path, &updated) { return Err("credential store rewrite failed"); }
  return Ok(true);
}
