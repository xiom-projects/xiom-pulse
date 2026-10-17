// XIOM PULSE -- game control plane (/api/game/*) for XIOM Engine servers.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The P8 forward contract (game server process -> control plane), acked
// with the engine lane (REL-20261013-1455-engine):
//   register (build/protocol/map/mode/capacity/region -> server id +
//   per-server bearer token + config revision + heartbeat cadence),
//   heartbeat (liveness/load; the response carries pending commands),
//   config (by revision/ETag; explicit unavailable/incompatible),
//   compat (min/current build + protocol facts), match-report and
//   telemetry (bearer + Idempotency-Key), admin command (ops-gated
//   state: active | drain_requested | shutdown).
//
// Records are append-only JSONL in PULSE_GAME_PATH (kind-tagged,
// latest-wins per server_id); the config document is
// PULSE_GAME_CONFIG_PATH (JSON, `revision` field feeds ETag and the
// register/compat responses). The realtime plane stays engine-owned:
// nothing here sits in a tick path.
module xiom.pulse.game

use xiom.io;
use xiom.time;
use xiom.convert;
use xiom.serialize.json;
use xiom.string;
use xiom.pulse.http;
use xiom.pulse.station.router;
use xiom.pulse.envelope;
use xiom.pulse.station.config;
use xiom.pulse.sessions;
use xiom.pulse.store;
use xiom.pulse.validate;

const CONTENT_JSON: Str = "application/json; charset=utf-8";

// --- small helpers ----------------------------------------------------------

/// gjson builds a JSON HandlerOut (module-local mirror of the server
/// helper; the envelope stays uniform). Complexity: O(body). Pure.
fn gjson(status: Int, body: Str) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_JSON; headers: Vec[(Str, Str)].new(); body: body; body_bytes: Vec[UInt8].new(); };
}

/// gjson_hdr is gjson with extra response headers (ETag).
/// Complexity: O(body). Pure.
fn gjson_hdr(status: Int, body: Str, hs: Vec[(Str, Str)]) -> HandlerOut {
  return HandlerOut{ status: status; content_type: CONTENT_JSON; headers: hs; body: body; body_bytes: Vec[UInt8].new(); };
}

/// game_err maps a stable code to the standard envelope.
/// Complexity: O(1). Pure.
fn game_err(status: Int, code: Str, msg: Str) -> HandlerOut {
  return gjson(status, envelope.error_body(code, msg));
}

/// rec_str returns a string field from a record ("" when absent).
/// Complexity: O(record). Pure.
fn rec_str(rec: Str, key: Str) -> Str {
  return validate.field_str(rec, key, 4096);
}

/// rec_int returns a number field from a record (0 when absent).
/// Complexity: O(record). Pure.
fn rec_int(rec: Str, key: Str) -> Int {
  let pv = json.json_parse(rec);
  if pv.is_err { return 0; }
  let opt = json.json_get(pv.value, key);
  if opt.is_none { return 0; }
  if json.json_type(opt.value) != "number" { return 0; }
  match opt.value {
    JsonValue.Number(x) => { return convert.float_to_int(x); },
    _ => { return 0; },
  }
}

fn rec_kind(rec: Str) -> Str {
  return rec_str(rec, "kind");
}

/// game_records returns every valid control-plane record in order.
/// Complexity: O(n). Pure.
fn game_records() -> Vec[Str] {
  return store.store_valid_records(config.cfg_game_path());
}

/// latest_server returns the newest record for `server_id` ("" none).
/// Latest-wins keeps the file append-only while state changes are
/// O(1) appends. Complexity: O(n). Pure.
fn latest_server(server_id: Str) -> Str {
  let recs = game_records();
  var out: Str = "";
  var i: Int = 0;
  while i < recs.len() {
    let r = recs[i];
    if rec_kind(r) == "game_server" && rec_str(r, "server_id") == server_id { out = r; }
    i = i + 1;
  }
  return out;
}

/// server_by_token resolves a per-server bearer token to its newest
/// server record ("" when unknown). Complexity: O(n). Pure.
fn server_by_token(tok: Str) -> Str {
  let recs = game_records();
  var out: Str = "";
  var i: Int = 0;
  while i < recs.len() {
    let r = recs[i];
    if rec_kind(r) == "game_server" && rec_str(r, "token") == tok { out = r; }
    i = i + 1;
  }
  return out;
}

/// find_idem reports the 1-based record index of a known idempotency
/// key (0 when new) across the control-plane records.
/// Complexity: O(n). Pure.
fn find_idem(idem: Str) -> Int {
  let recs = game_records();
  var i: Int = 0;
  while i < recs.len() {
    if rec_str(recs[i], "idem") == idem { return i + 1; }
    i = i + 1;
  }
  return 0;
}

/// config_doc reads the config document ("" when unreadable).
/// Complexity: O(size). Pure.
fn config_doc() -> Str {
  let r = io.read_file(config.cfg_game_config_path());
  if r.is_err { return ""; }
  return r.value;
}

/// config_revision returns the document's revision (0 when absent).
/// Complexity: O(size). Pure.
fn config_revision() -> Int {
  return rec_int(config_doc(), "revision");
}

/// bearer_ok resolves the request bearer to a server record; the second
/// value of the pair is false when the token is missing/unknown.
/// Complexity: O(n). Pure.
fn bearer_server(req: &PulseRequest) -> (Bool, Str) {
  let tok = http.bearer_token(req);
  if tok.len() == 0 { return (false, ""); }
  let srec = server_by_token(tok);
  if srec.len() == 0 { return (false, ""); }
  return (true, srec);
}

// --- register ---------------------------------------------------------------

/// register onboards a game server: validates identity/build facts,
/// mints the server id + bearer token and stores the opening record.
/// Complexity: O(body + n).
pub fn register(body: Str) -> HandlerOut {
  if !validate.is_json_object(body) {
    return game_err(400, "invalid_json", "body must be a JSON object");
  }
  let build = validate.field_str(body, "build", 64);
  let map = validate.field_str(body, "map", 64);
  let mode = validate.field_str(body, "mode", 32);
  let proto = validate.field_str(body, "protocol_version", 32);
  if build.len() == 0 || map.len() == 0 || mode.len() == 0 || proto.len() == 0 {
    return game_err(400, "invalid_request", "build, map, mode and protocol_version are required strings");
  }
  var region = validate.field_str(body, "region", 32);
  if region.len() == 0 { region = "any"; }
  let gend = validate.field_str(body, "game_endpoint", 255);
  let qend = validate.field_str(body, "query_endpoint", 255);
  let capacity = rec_int(body, "capacity");
  let sid = "srv-" + sessions.csrf_new_token();
  let tok = sessions.csrf_new_token() + sessions.csrf_new_token();
  var v = json.json_object_new();
  v = json.json_set(v, "kind", json.json_string("game_server"));
  v = json.json_set(v, "server_id", json.json_string(sid));
  v = json.json_set(v, "token", json.json_string(tok));
  v = json.json_set(v, "protocol_version", json.json_string(proto));
  v = json.json_set(v, "build", json.json_string(build));
  v = json.json_set(v, "map", json.json_string(map));
  v = json.json_set(v, "mode", json.json_string(mode));
  v = json.json_set(v, "region", json.json_string(region));
  v = json.json_set(v, "game_endpoint", json.json_string(gend));
  v = json.json_set(v, "query_endpoint", json.json_string(qend));
  v = json.json_set(v, "capacity", json.json_number(convert.int_to_float(capacity)));
  v = json.json_set(v, "state", json.json_string("active"));
  v = json.json_set(v, "revision", json.json_number(1.0));
  v = json.json_set(v, "registered_at", json.json_number(convert.int_to_float(time.unix_timestamp())));
  if !store.store_append(config.cfg_game_path(), json.json_stringify(v)) {
    return game_err(500, "store_error", "append failed");
  }
  var out = json.json_object_new();
  out = json.json_set(out, "ok", json.json_bool(true));
  out = json.json_set(out, "server_id", json.json_string(sid));
  out = json.json_set(out, "server_token", json.json_string(tok));
  out = json.json_set(out, "config_revision", json.json_number(convert.int_to_float(config_revision())));
  out = json.json_set(out, "heartbeat_cadence_secs", json.json_number(convert.int_to_float(config.cfg_game_heartbeat_secs())));
  return gjson(200, json.json_stringify(out));
}

// --- heartbeat --------------------------------------------------------------

/// heartbeat records liveness/load and returns the pending commands
/// derived from the server's state (command piggyback; no inbound game
/// route). Complexity: O(body + n).
pub fn heartbeat(req: &PulseRequest, body: Str) -> HandlerOut {
  let br = bearer_server(req);
  if !br.0 {
    return game_err(401, "unauthorized", "server bearer token required");
  }
  let srec = br.1;
  let sid = rec_str(srec, "server_id");
  if body.len() > 0 && !validate.is_json_object(body) {
    return game_err(400, "invalid_json", "body must be a JSON object");
  }
  var hb = json.json_object_new();
  hb = json.json_set(hb, "kind", json.json_string("game_heartbeat"));
  hb = json.json_set(hb, "server_id", json.json_string(sid));
  hb = json.json_set(hb, "players", json.json_number(convert.int_to_float(rec_int(body, "players"))));
  hb = json.json_set(hb, "tick_rate", json.json_number(convert.int_to_float(rec_int(body, "tick_rate"))));
  hb = json.json_set(hb, "frame_time_ms", json.json_number(convert.int_to_float(rec_int(body, "frame_time_ms"))));
  hb = json.json_set(hb, "uptime_sec", json.json_number(convert.int_to_float(rec_int(body, "uptime_sec"))));
  hb = json.json_set(hb, "at", json.json_number(convert.int_to_float(time.unix_timestamp())));
  if !store.store_append(config.cfg_game_path(), json.json_stringify(hb)) {
    return game_err(500, "store_error", "append failed");
  }
  let state = rec_str(srec, "state");
  var cmds = json.json_array_new();
  if state == "drain_requested" { cmds = json.json_array_push(cmds, json.json_string("drain_requested")); }
  if state == "shutdown" { cmds = json.json_array_push(cmds, json.json_string("shutdown")); }
  var out = json.json_object_new();
  out = json.json_set(out, "ok", json.json_bool(true));
  out = json.json_set(out, "server_id", json.json_string(sid));
  out = json.json_set(out, "config_revision", json.json_number(convert.int_to_float(config_revision())));
  out = json.json_set(out, "heartbeat_cadence_secs", json.json_number(convert.int_to_float(config.cfg_game_heartbeat_secs())));
  out = json.json_set(out, "commands", cmds);
  return gjson(200, json.json_stringify(out));
}

// --- config + compat --------------------------------------------------------

/// query_first returns the first value of `name` from the matched route
/// query pairs ("" when absent). Complexity: O(q). Pure.
fn query_first(m: &PulseRoute, name: Str) -> Str {
  var i: Int = 0;
  while i < m.query_names.len() {
    if m.query_names[i] == name && i < m.query_values.len() { return m.query_values[i]; }
    i = i + 1;
  }
  return "";
}

/// config_feed serves the config document with revision/ETag and an
/// explicit unavailable status; a build older than `min_build` gets
/// 409 incompatible_build. Complexity: O(size).
pub fn config_feed(m: &PulseRoute, req: &PulseRequest) -> HandlerOut {
  let doc = config_doc();
  if doc.len() == 0 {
    return game_err(404, "config_unavailable", "no config document at " + config.cfg_game_config_path());
  }
  let build = query_first(m, "build");
  let min_build = validate.field_str(doc, "min_build", 64);
  if build.len() > 0 && min_build.len() > 0 && build != min_build {
    // v1 gate: exact min/current match; the engine owns richer ordering.
    let cur = validate.field_str(doc, "current_build", 64);
    if build != cur {
      var eb = json.json_object_new();
      eb = json.json_set(eb, "code", json.json_string("incompatible_build"));
      eb = json.json_set(eb, "min_build", json.json_string(min_build));
      eb = json.json_set(eb, "current_build", json.json_string(cur));
      return gjson(409, json.json_stringify(eb));
    }
  }
  let etag = "\"rev-" + config_revision().to_str() + "\"";
  let inm = http.header_get(req, "if-none-match");
  if inm.len() > 0 && inm == etag {
    var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
    hs.push(("ETag", etag));
    return gjson_hdr(304, "", hs);
  }
  var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  hs.push(("ETag", etag));
  return gjson_hdr(200, doc, hs);
}

/// compat returns the build/protocol facts for the compatibility gate
/// (the engine decides using min_build semantics it owns).
/// Complexity: O(size).
pub fn compat(m: &PulseRoute) -> HandlerOut {
  let doc = config_doc();
  let build = query_first(m, "build");
  var v = json.json_object_new();
  v = json.json_set(v, "min_build", json.json_string(validate.field_str(doc, "min_build", 64)));
  v = json.json_set(v, "current_build", json.json_string(validate.field_str(doc, "current_build", 64)));
  v = json.json_set(v, "protocol_version", json.json_string(validate.field_str(doc, "protocol_version", 32)));
  var compatible: Bool = false;
  let cur = validate.field_str(doc, "current_build", 64);
  if build.len() > 0 && cur.len() > 0 && build == cur { compatible = true; }
  v = json.json_set(v, "compatible", json.json_bool(compatible));
  return gjson(200, json.json_stringify(v));
}

// --- match-report + telemetry ----------------------------------------------

/// read_idem validates and returns the Idempotency-Key header.
/// Complexity: O(1). Pure.
fn read_idem(req: &PulseRequest) -> (Bool, Str) {
  let idem = http.header_get(req, "idempotency-key");
  if idem.len() == 0 { return (false, ""); }
  if !http.idem_key_valid(idem) { return (false, ""); }
  return (true, idem);
}

/// match_report stores a final match record keyed by Idempotency-Key
/// (a duplicate key replays deduplicated=true). Complexity: O(body+n).
pub fn match_report(req: &PulseRequest, body: Str) -> HandlerOut {
  let br = bearer_server(req);
  if !br.0 {
    return game_err(401, "unauthorized", "server bearer token required");
  }
  if !validate.is_json_object(body) {
    return game_err(400, "invalid_json", "body must be a JSON object");
  }
  let idr = read_idem(req);
  if !idr.0 {
    return game_err(400, "idempotency_required", "a valid Idempotency-Key header is required");
  }
  if find_idem(idr.1) > 0 {
    return gjson(200, "{\"stored\":false,\"deduplicated\":true}");
  }
  let pv = json.json_parse(body);
  var v = json.json_object_new();
  v = json.json_set(v, "kind", json.json_string("game_match"));
  v = json.json_set(v, "idem", json.json_string(idr.1));
  v = json.json_set(v, "server_id", json.json_string(rec_str(br.1, "server_id")));
  v = json.json_set(v, "at", json.json_number(convert.int_to_float(time.unix_timestamp())));
  v = json.json_set(v, "report", pv.value);
  if !store.store_append(config.cfg_game_path(), json.json_stringify(v)) {
    return game_err(500, "store_error", "append failed");
  }
  return gjson(200, "{\"stored\":true}");
}

/// telemetry stores a batched telemetry payload keyed by Idempotency-Key.
/// Complexity: O(body+n).
pub fn telemetry(req: &PulseRequest, body: Str) -> HandlerOut {
  let br = bearer_server(req);
  if !br.0 {
    return game_err(401, "unauthorized", "server bearer token required");
  }
  if body.len() == 0 {
    return game_err(400, "invalid_json", "body required");
  }
  let idr = read_idem(req);
  if !idr.0 {
    return game_err(400, "idempotency_required", "a valid Idempotency-Key header is required");
  }
  if find_idem(idr.1) > 0 {
    return gjson(200, "{\"stored\":false,\"deduplicated\":true}");
  }
  let pv = json.json_parse(body);
  if pv.is_err {
    return game_err(400, "invalid_json", "body must be valid JSON");
  }
  var v = json.json_object_new();
  v = json.json_set(v, "kind", json.json_string("game_telemetry"));
  v = json.json_set(v, "idem", json.json_string(idr.1));
  v = json.json_set(v, "server_id", json.json_string(rec_str(br.1, "server_id")));
  v = json.json_set(v, "at", json.json_number(convert.int_to_float(time.unix_timestamp())));
  v = json.json_set(v, "batch", pv.value);
  if !store.store_append(config.cfg_game_path(), json.json_stringify(v)) {
    return game_err(500, "store_error", "append failed");
  }
  return gjson(200, "{\"stored\":true}");
}

// --- admin command ----------------------------------------------------------

/// admin_command sets a server's control state (ops-gated by
/// PULSE_GAME_ADMIN_TOKEN). The heartbeat piggyback then delivers it.
/// Complexity: O(body + n).
pub fn admin_command(req: &PulseRequest, body: Str) -> HandlerOut {
  let admin = config.cfg_game_admin_token();
  if admin.len() == 0 {
    return game_err(403, "admin_disabled", "PULSE_GAME_ADMIN_TOKEN is not configured");
  }
  if http.bearer_token(req) != admin {
    return game_err(401, "unauthorized", "admin bearer token required");
  }
  if !validate.is_json_object(body) {
    return game_err(400, "invalid_json", "body must be a JSON object");
  }
  let sid = validate.field_str(body, "server_id", 64);
  let state = validate.field_str(body, "state", 32);
  if sid.len() == 0 {
    return game_err(400, "invalid_request", "server_id is required");
  }
  if state != "active" && state != "drain_requested" && state != "shutdown" {
    return game_err(400, "invalid_request", "state must be active, drain_requested or shutdown");
  }
  let srec = latest_server(sid);
  if srec.len() == 0 {
    return game_err(404, "unknown_server", "no server with that id");
  }
  var v = json.json_parse(srec).value;
  let rev = rec_int(srec, "revision") + 1;
  v = json.json_set(v, "state", json.json_string(state));
  v = json.json_set(v, "revision", json.json_number(convert.int_to_float(rev)));
  if !store.store_append(config.cfg_game_path(), json.json_stringify(v)) {
    return game_err(500, "store_error", "append failed");
  }
  var out = json.json_object_new();
  out = json.json_set(out, "ok", json.json_bool(true));
  out = json.json_set(out, "server_id", json.json_string(sid));
  out = json.json_set(out, "state", json.json_string(state));
  out = json.json_set(out, "revision", json.json_number(convert.int_to_float(rev)));
  return gjson(200, json.json_stringify(out));
}
