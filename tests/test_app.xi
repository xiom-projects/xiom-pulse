// XIOM PULSE -- Step 2 app-skeleton suite (router, envelope, config,
// metrics, sessions, JWT HS256, dispatch).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: .\scripts\run.ps1 tests\test_app.xi
// Exit code = number of failures (0 = green).
module pulse_app_tests

use xiom.io;
use xiom.string;
use xiom.string.slice;
use xiom.time;
use xiom.env;
use xiom.jwt;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.envelope;
use xiom.pulse.config;
use xiom.pulse.cors;
use xiom.pulse.metrics;
use xiom.pulse.sessions;
use xiom.pulse.store;
use xiom.pulse.ratelimit;
use xiom.pulse.validate;
use xiom.pulse.reqctx;
use xiom.pulse.outbound;
use xiom.pulse.app;

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn make_req(method: Str, target: Str, body: Str) -> PulseRequest {
  let raw_str = method + " " + target + " HTTP/1.1\r\nHost: t\r\nContent-Length: " + body.len().to_str() + "\r\n\r\n" + body;
  let raw = http.str_to_bytes(raw_str);
  return http.parse_request(&raw);
}

fn route_req(method: Str, target: Str, body: Str) -> HandlerOut {
  let req = make_req(method, target, body);
  let m = router.route_match(method, target);
  return app.handle_route(m, &req, body);
}

fn route_req_hdr(method: Str, target: Str, headers: Str, body: Str) -> HandlerOut {
  let raw_str = method + " " + target + " HTTP/1.1\r\nHost: t\r\n" + headers + "\r\n" + body;
  let raw = http.str_to_bytes(raw_str);
  let req = http.parse_request(&raw);
  let m = router.route_match(method, target);
  // pass the PARSED body so chunked decoding is exercised (decoded == body
  // for plain Content-Length requests).
  let decoded = http.bytes_to_str(&req.body, 0, req.body.len());
  return app.handle_route(m, &req, decoded);
}

fn route_req_hdr_cl(method: Str, target: Str, headers: Str, body: Str) -> HandlerOut {
  // Custom headers + a proper Content-Length body (idempotency tests).
  let raw_str = method + " " + target + " HTTP/1.1\r\nHost: t\r\n" + headers + "Content-Length: " + body.len().to_str() + "\r\n\r\n" + body;
  let raw = http.str_to_bytes(raw_str);
  let req = http.parse_request(&raw);
  let m = router.route_match(method, target);
  return app.handle_route(m, &req, body);
}

fn route_req_v1(method: Str, target: Str, body: Str) -> HandlerOut {
  // Mirrors dispatch_one: strip the /v1 alias, match the canonical path,
  // dispatch with the ORIGINAL request (Link/target semantics intact).
  let t = router.v1_path(target);
  let req = make_req(method, target, body);
  let m = router.route_match(method, t);
  return app.handle_route(m, &req, body);
}

fn json_field(body: Str, field: Str) -> Str {
  // First "field":"value" string value in a small JSON body (upload names).
  let needle = "\"" + field + "\":\"";
  let idx = string.str_index_of(body, needle);
  if idx.is_none { return ""; }
  let start = idx.value + needle.len();
  let rest = string.str_slice(body, start, body.len());
  let end = string.str_index_of(rest, "\"");
  if end.is_none { return ""; }
  return string.str_slice(body, start, start + end.value);
}


pub fn main() -> Int {
  var f: Int = 0;

  // --- router --------------------------------------------------------------
  let m1 = router.route_match("GET", "/health");
  f = f + check("route health matched", m1.kind == 1 && m1.route_id == 1);
  let m2 = router.route_match("POST", "/health");
  f = f + check("route health 405", m2.kind == 2 && m2.allow == "GET");
  let m3 = router.route_match("GET", "/nope");
  f = f + check("route unknown", m3.kind == 0);
  let m4 = router.route_match("GET", "/api/items/42");
  f = f + check("route item matched", m4.kind == 1 && m4.route_id == 10);
  f = f + check("route item param name", m4.param_names.len() == 1 && m4.param_names[0] == "id");
  f = f + check("route item param value", m4.param_values.len() == 1 && m4.param_values[0] == "42");
  let m5 = router.route_match("GET", "/api/items/");
  f = f + check("route item empty id not found", m5.kind == 0);

  // --- envelope ------------------------------------------------------------
  let eb = envelope.error_body("not_found", "not found");
  f = f + check("envelope code", string.str_contains(eb, "\"code\":\"not_found\""));
  f = f + check("envelope message", string.str_contains(eb, "\"message\":\"not found\""));

  // --- config --------------------------------------------------------------
  env.set_var("PULSE_PORT", "12345");
  f = f + check("config port override", config.cfg_port() == 12345);
  env.set_var("PULSE_PORT", "not-a-port");
  f = f + check("config port fallback", config.cfg_port() == 8080);
  env.remove_var("PULSE_PORT");

  // --- config file -----------------------------------------------------------
  let cf = "pulse-test-config.json";
  let _rmc = io.remove_file(cf);
  let cw = io.write_file(cf, "{\"port\":12346,\"cors_origin\":\"http://cfg.test\",\"csrf\":false,\"rate_limit\":7,\"upload_dir\":\"cfg-uploads\",\"http_max_bytes\":1234}");
  f = f + check("config file write", cw.is_ok);
  env.set_var("PULSE_CONFIG", cf);
  env.remove_var("PULSE_PORT");
  f = f + check("config file load", config.cfg_load_file());
  f = f + check("config file port", config.cfg_port() == 12346);
  f = f + check("config file cors", config.cfg_cors_origin() == "http://cfg.test");
  f = f + check("config file csrf off", !config.cfg_csrf_enabled());
  f = f + check("config file rate", config.cfg_rate_limit() == 7);
  f = f + check("config file upload dir", config.cfg_upload_dir() == "cfg-uploads");
  f = f + check("config file http cap", outbound.outbound_max_bytes() == 1234);
  env.set_var("PULSE_PORT", "9999");
  f = f + check("config env wins", config.cfg_load_file() && config.cfg_port() == 9999);
  env.remove_var("PULSE_CONFIG");
  env.remove_var("PULSE_PORT");
  env.remove_var("PULSE_CORS_ORIGIN");
  env.remove_var("PULSE_CSRF");
  env.remove_var("PULSE_RATE_LIMIT");
  env.remove_var("PULSE_UPLOAD_DIR");
  env.remove_var("PULSE_HTTP_MAX_BYTES");
  let _rmc2 = io.remove_file(cf);

  // --- config validation warnings -------------------------------------------
  env.set_var("PULSE_PORT", "abc");
  let w1 = config.cfg_validate();
  f = f + check("cfg warn bad port", w1.len() == 1 && string.str_contains(w1[0], "PULSE_PORT"));
  env.set_var("PULSE_PORT", "65536");
  let w2 = config.cfg_validate();
  f = f + check("cfg warn port range", w2.len() == 1 && string.str_contains(w2[0], "PULSE_PORT"));
  env.set_var("PULSE_PORT", "8080");
  let w3 = config.cfg_validate();
  f = f + check("cfg warn clean", w3.len() == 0);
  env.set_var("PULSE_STORE_BACKEND", "sqlite");
  let w4 = config.cfg_validate();
  f = f + check("cfg warn bad backend", w4.len() == 1 && string.str_contains(w4[0], "PULSE_STORE_BACKEND"));
  env.set_var("PULSE_STORE_BACKEND", "kv");
  let w5 = config.cfg_validate();
  f = f + check("cfg warn kv ok", w5.len() == 0);
  env.set_var("PULSE_CSRF", "yes");
  let w6 = config.cfg_validate();
  f = f + check("cfg warn bad bool", w6.len() == 1 && string.str_contains(w6[0], "PULSE_CSRF"));
  env.set_var("PULSE_CSRF", "1");
  env.set_var("PULSE_SESSION_TTL", "0");
  let w7 = config.cfg_validate();
  f = f + check("cfg warn ttl zero", w7.len() == 1 && string.str_contains(w7[0], "PULSE_SESSION_TTL"));
  env.set_var("PULSE_SESSION_TTL", "3600");
  env.set_var("PULSE_RATE_LIMIT", "fast");
  let w8 = config.cfg_validate();
  f = f + check("cfg warn bad rate", w8.len() == 1 && string.str_contains(w8[0], "PULSE_RATE_LIMIT"));
  env.remove_var("PULSE_PORT");
  env.remove_var("PULSE_STORE_BACKEND");
  env.remove_var("PULSE_CSRF");
  env.remove_var("PULSE_SESSION_TTL");
  env.remove_var("PULSE_RATE_LIMIT");

  // --- PULSE_BIND shape (address vs address:port) ---------------------------
  env.set_var("PULSE_BIND", "127.0.0.1:3500");
  let w9 = config.cfg_validate();
  f = f + check("cfg warn bind host:port", w9.len() == 1 && string.str_contains(w9[0], "PULSE_BIND"));
  env.set_var("PULSE_BIND", "[::1]:3500");
  let w10 = config.cfg_validate();
  f = f + check("cfg warn bind [v6]:port", w10.len() == 1 && string.str_contains(w10[0], "PULSE_BIND"));
  env.set_var("PULSE_BIND", "::1");
  let w11 = config.cfg_validate();
  f = f + check("cfg bind bare v6 ok", w11.len() == 0);
  env.set_var("PULSE_BIND", "127.0.0.1");
  let w12 = config.cfg_validate();
  f = f + check("cfg bind plain ok", w12.len() == 0);
  env.remove_var("PULSE_BIND");

  // --- CORS allowlist (comma-separated) -------------------------------------
  env.set_var("PULSE_CORS_ORIGIN", "https://pulse.xiom-lang.org, https://xiom-lang.org");
  f = f + check("cors list first", cors.cors_allow_origin("https://pulse.xiom-lang.org") == "https://pulse.xiom-lang.org");
  f = f + check("cors list second", cors.cors_allow_origin("https://xiom-lang.org") == "https://xiom-lang.org");
  f = f + check("cors list reject", cors.cors_allow_origin("https://evil.test") == "");
  env.set_var("PULSE_CORS_ORIGIN", "*");
  f = f + check("cors star", cors.cors_allow_origin("https://any.test") == "*");
  env.remove_var("PULSE_CORS_ORIGIN");
  f = f + check("cors off", cors.cors_allow_origin("https://any.test") == "");

  // --- metrics -------------------------------------------------------------
  metrics.metrics_reset();
  metrics.metrics_record(200, 10);
  metrics.metrics_record(404, 5);
  metrics.metrics_record(500, 3);
  let snap = metrics.metrics_snapshot();
  f = f + check("metrics requests", snap.0 == 3);
  f = f + check("metrics 2xx", snap.1 == 1);
  f = f + check("metrics 4xx", snap.2 == 1);
  f = f + check("metrics 5xx", snap.3 == 1);
  f = f + check("metrics bytes", snap.4 == 18);
  let mr = metrics.metrics_render();
  f = f + check("metrics render total", string.str_contains(mr, "pulse_http_requests_total 3"));
  f = f + check("metrics render class", string.str_contains(mr, "pulse_http_responses_total{class=\"2xx\"} 1"));

  // --- duration histogram --------------------------------------------------
  metrics.metrics_record_duration(1);
  metrics.metrics_record_duration(5);
  metrics.metrics_record_duration(50);
  metrics.metrics_record_duration(9000);
  let mr2 = metrics.metrics_render();
  f = f + check("hist count", string.str_contains(mr2, "pulse_http_request_duration_ms_count 4"));
  f = f + check("hist +Inf", string.str_contains(mr2, "pulse_http_request_duration_ms_bucket{le=\"+Inf\"} 4"));
  f = f + check("hist le5 cumulative", string.str_contains(mr2, "pulse_http_request_duration_ms_bucket{le=\"5\"} 2"));
  f = f + check("hist sum", string.str_contains(mr2, "pulse_http_request_duration_ms_sum 9056"));
  f = f + check("metrics uptime", string.str_contains(mr2, "pulse_uptime_seconds"));

  // --- rate limiting (registry xiom.rate 0.2.0) ----------------------------
  env.set_var("PULSE_RATE_LIMIT", "2");
  env.set_var("PULSE_RATE_BURST", "2");
  var rl = ratelimit.limiter_new(config.cfg_rate_limit(), config.cfg_rate_burst());
  f = f + check("rate enabled", rl.enabled);
  let rnow = 1000000;
  f = f + check("rate allow 1", ratelimit.limiter_allow(&mut rl, rnow));
  f = f + check("rate allow 2", ratelimit.limiter_allow(&mut rl, rnow));
  f = f + check("rate deny 3", !ratelimit.limiter_allow(&mut rl, rnow));
  f = f + check("rate retry positive", ratelimit.limiter_retry_after_ms(&rl, rnow) > 0);
  f = f + check("rate refill after 1s", ratelimit.limiter_allow(&mut rl, rnow + 1000));
  env.set_var("PULSE_RATE_LIMIT", "0");
  var rl2 = ratelimit.limiter_new(config.cfg_rate_limit(), config.cfg_rate_burst());
  f = f + check("rate disabled", !rl2.enabled && ratelimit.limiter_allow(&mut rl2, rnow));
  env.remove_var("PULSE_RATE_LIMIT");
  env.remove_var("PULSE_RATE_BURST");

  // --- sessions ------------------------------------------------------------
  sessions.session_reset();
  let sid = sessions.session_create("bob", 60);
  f = f + check("session created", sid.len() == 32);
  f = f + check("session get", sessions.session_get(sid) == "bob");
  let ch = sessions.session_cookie_header(sid, 60);
  f = f + check("session cookie header value-only", string.str_starts_with(ch, "sid=" + sid) && !string.str_contains(ch, "Set-Cookie"));
  f = f + check("session cookie parse", sessions.session_id_from_cookie("a=1; sid=" + sid + "; b=2") == sid);
  f = f + check("session cookie absent", sessions.session_id_from_cookie("a=1") == "");
  sessions.session_drop(sid);
  f = f + check("session dropped", sessions.session_get(sid) == "");
  let ctok = sessions.csrf_new_token();
  f = f + check("csrf token len", ctok.len() == 32);
  f = f + check("csrf match", sessions.csrf_matches("sid=x; csrf=" + ctok + "; a=1", ctok));
  f = f + check("csrf mismatch", !sessions.csrf_matches("csrf=" + ctok, "wrong"));
  f = f + check("csrf absent", !sessions.csrf_matches("sid=x", ctok));
  sessions.session_reset();

  // --- validation -----------------------------------------------------------
  f = f + check("validate field", validate.field_str("{\"user\":\"bob\"}", "user", 64) == "bob");
  f = f + check("validate too long", validate.field_str("{\"user\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}", "user", 64) == "");
  f = f + check("validate wrong type", validate.field_str("{\"user\":5}", "user", 64) == "");
  f = f + check("validate object", validate.is_json_object("{\"a\":1}"));
  f = f + check("validate not object", !validate.is_json_object("notjson"));

  // --- jwt hs256 (registry xiom.jwt 0.2.0) --------------------------------
  let now = time.unix_timestamp();
  let payload = "{\"sub\":\"bob\",\"exp\":" + (now + 3600).to_str() + "}";
  let secret_bytes = slice.str_bytes("s3cret");
  let tr = jwt.jwt_sign_hs256(payload, &secret_bytes);
  f = f + check("jwt sign ok", tr.is_ok);
  var tok: Str = "";
  if tr.is_ok { tok = tr.value; }
  f = f + check("jwt sign shape", string.str_contains(tok, "."));
  let vr = jwt.jwt_verify_hs256(tok, &secret_bytes, now);
  f = f + check("jwt verify ok", vr.is_ok && string.str_contains(vr.value, "\"sub\":\"bob\""));
  let wrong_bytes = slice.str_bytes("other");
  let vw = jwt.jwt_signature_valid_hs256(tok, &wrong_bytes);
  f = f + check("jwt wrong secret", vw.is_ok && !vw.value);
  // Append a byte to the signature: deterministic 401 (replacing the last
  // base64url char is flaky -- trailing padding bits can decode to the
  // same signature bytes, and replacing 'x' with 'x' is a no-op).
  let tampered = tok + "x";
  let vt = jwt.jwt_signature_valid_hs256(tampered, &secret_bytes);
  f = f + check("jwt tamper rejected", vt.is_ok && !vt.value);
  let ve = jwt.jwt_verify_hs256(tok, &secret_bytes, now + 7200);
  f = f + check("jwt exp rejected later", ve.is_err);

  // --- dispatch ------------------------------------------------------------
  let h = route_req("GET", "/health", "");
  f = f + check("dispatch health", h.status == 200 && string.str_contains(h.body, "\"status\":\"ok\""));
  let h405 = route_req("POST", "/health", "");
  f = f + check("dispatch 405 allow", h405.status == 405 && h405.headers.len() == 1);
  let te = route_req_hdr("POST", "/api/echo", "Transfer-Encoding: chunked\r\n", "7\r\n{\"a\":1}\r\n0\r\n\r\n");
  f = f + check("te chunked accepted", te.status == 200 && string.str_contains(te.body, "\"echo\":{\"a\":1}"));
  let tecl = route_req_hdr("POST", "/api/echo", "Transfer-Encoding: chunked\r\nContent-Length: 5\r\n", "0\r\n\r\n");
  f = f + check("te+cl rejected 400", tecl.status == 400 && string.str_contains(tecl.body, "ambiguous"));
  let tegz = route_req_hdr("POST", "/api/echo", "Transfer-Encoding: gzip\r\n", "x");
  f = f + check("te gzip rejected 501", tegz.status == 501 && string.str_contains(tegz.body, "unsupported_transfer_encoding"));
  let nf = route_req("GET", "/nope", "");
  f = f + check("dispatch 404 envelope", nf.status == 404 && string.str_contains(nf.body, "\"code\":\"not_found\""));
  reqctx.set_rid("r-test");
  let nf2 = route_req("GET", "/nope", "");
  f = f + check("error carries rid", string.str_contains(nf2.body, "\"rid\":\"r-test\""));
  reqctx.set_rid("");
  let nf3 = route_req("GET", "/nope", "");
  f = f + check("error rid omitted when unset", !string.str_contains(nf3.body, "\"rid\":"));
  let item = route_req("GET", "/api/items/xyz", "");
  f = f + check("dispatch item", item.status == 200 && string.str_contains(item.body, "\"item\":\"xyz\""));
  let itemq = route_req("GET", "/api/items/7?x=1", "");
  f = f + check("dispatch item with query", itemq.status == 200 && string.str_contains(itemq.body, "\"item\":\"7\""));
  let login = route_req("POST", "/api/session/login", "{\"user\":\"carol\"}");
  f = f + check("dispatch login 200", login.status == 200 && login.headers.len() == 2);
  f = f + check("dispatch login body", string.str_contains(login.body, "\"user\":\"carol\""));
  f = f + check("dispatch login csrf", string.str_contains(login.body, "\"csrf\":\""));
  let long_login = route_req("POST", "/api/session/login", "{\"user\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}");
  f = f + check("dispatch login long user 400", long_login.status == 400);
  let badlogin = route_req("POST", "/api/session/login", "notjson");
  f = f + check("dispatch login 400", badlogin.status == 400);
  let me = route_req("GET", "/api/me", "");
  f = f + check("dispatch me 401", me.status == 401 && string.str_contains(me.body, "\"code\":\"unauthorized\""));
  let token_resp = route_req("POST", "/api/token", "{\"user\":\"carol\"}");
  f = f + check("dispatch token 200", token_resp.status == 200 && string.str_contains(token_resp.body, "\"token\":\""));
  let metrics_resp = route_req("GET", "/metrics", "");
  f = f + check("dispatch metrics 200", metrics_resp.status == 200 && string.str_contains(metrics_resp.content_type, "text/plain"));

  // --- store (JSONL, crash tolerance) --------------------------------------
  let sp = "pulse-store-test.jsonl";
  let _rm0 = io.remove_file(sp);
  f = f + check("store init", store.store_init(sp));
  f = f + check("store init idempotent", store.store_init(sp));
  f = f + check("store empty", store.store_count(sp) == 0);
  f = f + check("store append", store.store_append_event(sp, "{\"a\":1}"));
  f = f + check("store count 1", store.store_count(sp) == 1);
  let torn = io.append_file(sp, "{\"torn\":");
  f = f + check("store torn append ok", torn.is_ok);
  f = f + check("store torn tolerated", store.store_count(sp) == 1);
  f = f + check("store last", store.store_last(sp, 10).len() == 1);
  let joined = store.store_join_array(&store.store_last(sp, 10));
  f = f + check("store join array", string.str_starts_with(joined, "[") && string.str_contains(joined, "\"a\":1"));

  env.set_var("PULSE_STORE_PATH", sp);
  let ev = route_req("POST", "/api/events", "{\"kind\":\"click\",\"n\":1}");
  f = f + check("dispatch events post", ev.status == 200 && string.str_contains(ev.body, "\"stored\":true"));
  let ec = route_req("GET", "/api/events/count", "");
  f = f + check("dispatch events count", ec.status == 200 && string.str_contains(ec.body, "\"count\":2"));
  let el = route_req("GET", "/api/events", "");
  f = f + check("dispatch events list", el.status == 200 && string.str_contains(el.body, "click"));
  let el1 = route_req("GET", "/api/events?limit=1", "");
  f = f + check("dispatch events limit", el1.status == 200 && string.str_contains(el1.body, "click") && !string.str_contains(el1.body, "\"a\":1"));
  let ek = route_req("GET", "/api/events?kind=click", "");
  f = f + check("dispatch events kind", ek.status == 200 && string.str_contains(ek.body, "click") && !string.str_contains(ek.body, "\"a\":1"));
  let kf1 = store.store_last_kind(sp, "click", 10);
  let k0 = kf1[0];
  f = f + check("store kind filter", kf1.len() == 1 && string.str_contains(k0, "click"));
  f = f + check("store kind filter none", store.store_last_kind(sp, "nope", 10).len() == 0);
  let ecmp = route_req("POST", "/api/events/compact", "");
  f = f + check("dispatch compact 200", ecmp.status == 200);
  f = f + check("compact keeps records", store.store_count(sp) == 2);
  let raw_after = io.read_file(sp);
  if raw_after.is_ok {
    let ra = raw_after.value;
    f = f + check("compact drops torn", !string.str_contains(ra, "torn"));
  } else {
    f = f + check("compact drops torn", false);
  }
  let m16 = router.route_match("POST", "/api/events/compact");
  f = f + check("route compact matched", m16.kind == 1 && m16.route_id == 16);
  let e405 = route_req("PUT", "/api/events", "");
  f = f + check("dispatch events 405 allow", e405.status == 405 && e405.headers.len() == 1);
  let evbad = route_req("POST", "/api/events", "notjson");
  f = f + check("dispatch events 400", evbad.status == 400);

  // --- pagination (0.2): durable seq cursor + RFC 8288 Link -----------------
  // The compact above left the two seq-carrying records (1, 2); a raw
  // pre-0.2-style line (no seq) falls back to its ordinal cursor (3).
  let legacy = io.append_line(sp, "{\"kind\":\"event\",\"ts\":0,\"data\":{\"legacy\":true}}");
  f = f + check("paginate legacy append", legacy.is_ok);
  let pg1 = route_req("GET", "/api/events?limit=2", "");
  f = f + check("paginate page1 200", pg1.status == 200);
  f = f + check("paginate page1 cursor", string.str_contains(pg1.body, "\"next_cursor\":2"));
  f = f + check("paginate page1 seq field", string.str_contains(pg1.body, "\"seq\":"));
  f = f + check("paginate page1 legacy in page", string.str_contains(pg1.body, "legacy"));
  f = f + check("paginate page1 excludes older", !string.str_contains(pg1.body, "\"a\":1"));
  f = f + check("paginate page1 link", pg1.headers.len() == 1 && string.str_contains(pg1.headers[0].1, "rel=\"next\""));
  f = f + check("paginate page1 link cursor", pg1.headers.len() == 1 && string.str_contains(pg1.headers[0].1, "before=2"));
  let pg2 = route_req("GET", "/api/events?limit=2&before=2", "");
  f = f + check("paginate page2 200", pg2.status == 200);
  f = f + check("paginate page2 no next", string.str_contains(pg2.body, "\"next_cursor\":0"));
  f = f + check("paginate page2 no link", pg2.headers.len() == 0);
  f = f + check("paginate page2 oldest", string.str_contains(pg2.body, "\"seq\":1"));
  let pgk = route_req("GET", "/api/events?kind=click&limit=1", "");
  f = f + check("paginate kind no next", pgk.status == 200 && string.str_contains(pgk.body, "\"next_cursor\":0"));
  f = f + check("paginate kind content", string.str_contains(pgk.body, "click") && !string.str_contains(pgk.body, "legacy"));
  let pgbad = route_req("GET", "/api/events?before=abc", "");
  f = f + check("paginate bad cursor 400", pgbad.status == 400 && string.str_contains(pgbad.body, "\"code\":\"invalid_cursor\""));
  let pg0 = route_req("GET", "/api/events?before=1", "");
  f = f + check("paginate oldest cursor empty", pg0.status == 200 && string.str_contains(pg0.body, "\"events\":[]"));

  // --- idempotency keys (0.2) -----------------------------------------------
  let c_before = store.store_count(sp);
  let idem1 = route_req_hdr_cl("POST", "/api/events", "Idempotency-Key: itest-1\r\n", "{\"kind\":\"idem\",\"n\":1}");
  f = f + check("idem first 200", idem1.status == 200 && string.str_contains(idem1.body, "\"stored\":true"));
  f = f + check("idem first seq", string.str_contains(idem1.body, "\"seq\":"));
  f = f + check("idem first appended", store.store_count(sp) == c_before + 1);
  f = f + check("idem find", store.store_find_idem(sp, "itest-1") > 0);
  let idem2 = route_req_hdr_cl("POST", "/api/events", "Idempotency-Key: itest-1\r\n", "{\"kind\":\"idem\",\"n\":1}");
  f = f + check("idem replay 200", idem2.status == 200);
  f = f + check("idem replay dedup", string.str_contains(idem2.body, "\"deduplicated\":true"));
  f = f + check("idem replay no append", store.store_count(sp) == c_before + 1);
  let idem3 = route_req_hdr_cl("POST", "/api/events", "Idempotency-Key: itest-2\r\n", "{\"kind\":\"idem\",\"n\":2}");
  f = f + check("idem new key appends", idem3.status == 200 && store.store_count(sp) == c_before + 2);
  var longkey: Str = "";
  var lki: Int = 0;
  while lki < 201 {
    longkey = longkey + "a";
    lki = lki + 1;
  }
  let idem_bad = route_req_hdr_cl("POST", "/api/events", "Idempotency-Key: " + longkey + "\r\n", "{\"kind\":\"idem\"}");
  f = f + check("idem long key 400", idem_bad.status == 400 && string.str_contains(idem_bad.body, "\"code\":\"invalid_idempotency_key\""));
  f = f + check("idem bad key no append", store.store_count(sp) == c_before + 2);
  let idem_list = route_req("GET", "/api/events?kind=idem", "");
  f = f + check("idem events listed", idem_list.status == 200 && string.str_contains(idem_list.body, "\"idem\":\"itest-1\""));

  // --- /v1 alias (0.2) ------------------------------------------------------
  f = f + check("v1 path map", router.v1_path("/v1/api/events?limit=2") == "/api/events?limit=2");
  f = f + check("v1 path root", router.v1_path("/v1") == "/");
  f = f + check("v1 path passthrough", router.v1_path("/api/events") == "/api/events");
  let v1h = route_req_v1("GET", "/v1/health", "");
  f = f + check("v1 health 200", v1h.status == 200 && string.str_contains(v1h.body, "\"status\":\"ok\""));
  let v1v = route_req_v1("GET", "/v1/api/version", "");
  f = f + check("v1 version 200", v1v.status == 200 && string.str_contains(v1v.body, "xiom-pulse"));
  let v1n = route_req_v1("GET", "/v1/nope", "");
  f = f + check("v1 unknown 404", v1n.status == 404);
  let v1e = route_req_v1("GET", "/v1/api/events?limit=1", "");
  f = f + check("v1 events 200", v1e.status == 200 && string.str_contains(v1e.body, "\"events\":"));
  f = f + check("v1 link preserves prefix", v1e.headers.len() == 1 && string.str_contains(v1e.headers[0].1, "</v1/api/events?"));
  let v1f = route_req_v1("GET", "/v1/favicon.ico", "");
  f = f + check("v1 favicon 200", v1f.status == 200 && v1f.body_bytes.len() > 1000);

  // --- multipart uploads (0.2) ----------------------------------------------
  // Unique dir per run so runs cannot contaminate each other.
  let updir = sp + "-uploads-" + time.monotonic_ms().to_str();
  env.set_var("PULSE_UPLOAD_DIR", updir);
  let mp_body = "--B1\r\nContent-Disposition: form-data; name=\"file\"; filename=\"hello.txt\"\r\nContent-Type: text/plain\r\n\r\nhello world\r\n--B1\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\nfield only\r\n--B1--\r\n";
  let up1 = route_req_hdr_cl("POST", "/api/uploads", "Content-Type: multipart/form-data; boundary=B1\r\n", mp_body);
  f = f + check("upload 200", up1.status == 200 && string.str_contains(up1.body, "\"stored\":1"));
  f = f + check("upload original", string.str_contains(up1.body, "\"original\":\"hello.txt\""));
  f = f + check("upload bytes", string.str_contains(up1.body, "\"bytes\":11"));
  // NOTE: no io.list_dir anywhere -- C-PULSE-17 returns dangling names
  // (docs/repro/io-list-dir-dangling). Generated names come from the
  // response JSON and are probed with io.file_exists/read_file/remove_file.
  let up1_name = json_field(up1.body, "name");
  f = f + check("upload stored on disk", up1_name.len() > 0 && io.file_exists(io.join_paths(updir, up1_name)));
  var up_text: Str = "";
  if up1_name.len() > 0 {
    let up_rf = io.read_file(io.join_paths(updir, up1_name));
    if up_rf.is_ok {
      up_text = up_rf.value;
    }
  }
  f = f + check("upload content exact", up_text == "hello world");
  f = f + check("upload generated name", string.str_contains(up1_name, "up-") && string.str_ends_with(up1_name, ".txt") && !string.str_contains(up1_name, "..") && !string.str_contains(up1_name, "/") && !string.str_contains(up1_name, "\\"));
  let mp_trav = "--B2\r\nContent-Disposition: form-data; name=\"f\"; filename=\"..\\..\\evil.txt\"\r\n\r\nx\r\n--B2--\r\n";
  let up2 = route_req_hdr_cl("POST", "/api/uploads", "Content-Type: multipart/form-data; boundary=B2\r\n", mp_trav);
  f = f + check("upload traversal 200", up2.status == 200 && string.str_contains(up2.body, "evil.txt"));
  let up2_name = json_field(up2.body, "name");
  f = f + check("upload traversal stored safely", up2_name.len() > 0 && !string.str_contains(up2_name, "evil") && io.file_exists(io.join_paths(updir, up2_name)));
  f = f + check("upload no escape", !io.file_exists(io.join_paths(updir, "evil.txt")) && !io.file_exists(io.join_paths(updir, "../evil.txt")));
  let up3 = route_req_hdr_cl("POST", "/api/uploads", "Content-Type: multipart/form-data\r\n", "nope");
  f = f + check("upload no boundary 415", up3.status == 415 && string.str_contains(up3.body, "\"code\":\"unsupported_media_type\""));
  let up4 = route_req_hdr_cl("POST", "/api/uploads", "Content-Type: multipart/form-data; boundary=B3\r\n", "no boundary here");
  f = f + check("upload bad body 400", up4.status == 400 && string.str_contains(up4.body, "\"code\":\"boundary_not_found\""));
  env.set_var("PULSE_UPLOAD_MAX_BYTES", "4");
  let mp_big = "--B4\r\nContent-Disposition: form-data; name=\"f\"; filename=\"big.txt\"\r\n\r\n0123456789\r\n--B4--\r\n";
  let up5 = route_req_hdr_cl("POST", "/api/uploads", "Content-Type: multipart/form-data; boundary=B4\r\n", mp_big);
  f = f + check("upload part cap 413", up5.status == 413 && string.str_contains(up5.body, "\"code\":\"part_too_large\""));
  env.remove_var("PULSE_UPLOAD_MAX_BYTES");
  // cleanup by known names (the dir itself stays; gitignored)
  if up1_name.len() > 0 {
    let _ru1 = io.remove_file(io.join_paths(updir, up1_name));
  }
  if up2_name.len() > 0 {
    let _ru2 = io.remove_file(io.join_paths(updir, up2_name));
  }
  env.remove_var("PULSE_UPLOAD_DIR");

  // --- site mode (0.3) ------------------------------------------------------
  // Guarded creates: io.create_dir requires the path NOT to exist, and the
  // r2 run finds the dirs r1 left behind (files are cleaned, dirs stay).
  let sdir = "pulse-test-site";
  if !io.is_dir(sdir) {
    let _smk1 = io.create_dir(sdir);
  }
  if !io.is_dir(sdir + "/assets") {
    let _smk2 = io.create_dir(sdir + "/assets");
  }
  if !io.is_dir(sdir + "/sub") {
    let _smk3 = io.create_dir(sdir + "/sub");
  }
  let _sw1 = io.write_file(sdir + "/index.html", "SITE_INDEX");
  let _sw2 = io.write_file(sdir + "/about.html", "SITE_ABOUT");
  let _sw3 = io.write_file(sdir + "/sub/index.html", "SITE_SUB");
  let _sw4 = io.write_file(sdir + "/404.html", "SITE_404");
  let _sw5 = io.write_file(sdir + "/assets/app.js", "SITE_JS");
  let _sw6 = io.write_file(sdir + "/assets/bundle.wasm", "SITE_WASM");
  let _sw7 = io.write_file("pulse-site-secret.txt", "SECRET");
  env.set_var("PULSE_SITE_DIR", sdir);
  let s1 = route_req("GET", "/", "");
  f = f + check("site index 200", s1.status == 200 && string.str_contains(http.bytes_to_str(&s1.body_bytes, 0, s1.body_bytes.len()), "SITE_INDEX"));
  let s2 = route_req("GET", "/about", "");
  f = f + check("site clean url", s2.status == 200 && string.str_contains(http.bytes_to_str(&s2.body_bytes, 0, s2.body_bytes.len()), "SITE_ABOUT"));
  let s3 = route_req("GET", "/sub/", "");
  f = f + check("site dir index", s3.status == 200 && string.str_contains(http.bytes_to_str(&s3.body_bytes, 0, s3.body_bytes.len()), "SITE_SUB"));
  let s4 = route_req("GET", "/assets/app.js", "");
  f = f + check("site assets", s4.status == 200 && string.str_contains(http.bytes_to_str(&s4.body_bytes, 0, s4.body_bytes.len()), "SITE_JS"));
  let s5 = route_req("GET", "/assets/bundle.wasm", "");
  f = f + check("site wasm mime", s5.status == 200 && s5.content_type == "application/wasm" && string.str_contains(http.bytes_to_str(&s5.body_bytes, 0, s5.body_bytes.len()), "SITE_WASM"));
  let s6 = route_req("GET", "/nope", "");
  f = f + check("site 404 page", s6.status == 404 && string.str_contains(http.bytes_to_str(&s6.body_bytes, 0, s6.body_bytes.len()), "SITE_404"));
  let s7 = route_req("GET", "/health", "");
  f = f + check("site api wins", s7.status == 200 && string.str_contains(s7.body, "\"status\":\"ok\""));
  let s7b = route_req("GET", "/api/version", "");
  f = f + check("site api version wins", s7b.status == 200 && string.str_contains(s7b.body, "\"version\":\"0.2.0\""));
  let s8 = route_req("GET", "/../pulse-site-secret.txt", "");
  f = f + check("site traversal blocked", s8.status != 200 && !string.str_contains(http.bytes_to_str(&s8.body_bytes, 0, s8.body_bytes.len()), "SECRET"));
  env.remove_var("PULSE_SITE_DIR");
  let _sc1 = io.remove_file(sdir + "/index.html");
  let _sc2 = io.remove_file(sdir + "/about.html");
  let _sc3 = io.remove_file(sdir + "/sub/index.html");
  let _sc4 = io.remove_file(sdir + "/404.html");
  let _sc5 = io.remove_file(sdir + "/assets/app.js");
  let _sc6 = io.remove_file(sdir + "/assets/bundle.wasm");
  let _sc7 = io.remove_file("pulse-site-secret.txt");
  env.remove_var("PULSE_STORE_PATH");
  let rm1 = io.remove_file(sp);
  f = f + check("store cleanup", rm1.is_ok);

  // --- app icon + landing page --------------------------------------------
  let m14 = router.route_match("GET", "/favicon.ico");
  f = f + check("route favicon matched", m14.kind == 1 && m14.route_id == 14);
  let m15 = router.route_match("GET", "/");
  f = f + check("route landing matched", m15.kind == 1 && m15.route_id == 15);
  f = f + check("icon load", app.load_icon("resources/img/pulse-ico.ico"));
  let fav = route_req("GET", "/favicon.ico", "");
  f = f + check("favicon 200 binary", fav.status == 200 && fav.body_bytes.len() > 1000);
  f = f + check("favicon content type", string.str_contains(fav.content_type, "image/x-icon"));
  let landing = route_req("GET", "/", "");
  f = f + check("landing 200", landing.status == 200 && string.str_contains(landing.body, "XIOM PULSE"));
  f = f + check("landing html type", string.str_contains(landing.content_type, "text/html"));

  // --- openapi contract (0.2) ------------------------------------------------
  let oa = route_req("GET", "/openapi.json", "");
  f = f + check("openapi 200", oa.status == 200);
  f = f + check("openapi marker", string.str_contains(oa.body, "\"3.1.0\""));
  f = f + check("openapi title", string.str_contains(oa.body, "XIOM PULSE"));
  f = f + check("openapi version", string.str_contains(oa.body, "\"version\": \"0.2.0\""));
  f = f + check("route openapi matched", router.route_match("GET", "/openapi.json").route_id == 17);
  let rl = router.routes_list();
  var has_openapi: Bool = false;
  var rli: Int = 0;
  while rli < rl.len() {
    if rl[rli].0 == "GET" && rl[rli].1 == "/openapi.json" { has_openapi = true; }
    rli = rli + 1;
  }
  f = f + check("routes list has openapi", has_openapi);
  var has_uploads: Bool = false;
  var rli2: Int = 0;
  while rli2 < rl.len() {
    if rl[rli2].0 == "POST" && rl[rli2].1 == "/api/uploads" { has_uploads = true; }
    rli2 = rli2 + 1;
  }
  f = f + check("routes list has uploads", has_uploads);
  f = f + check("routes list size", rl.len() == 18);

  // --- additive error status field (0.2) -------------------------------------
  let nf = route_req("GET", "/nope", "");
  f = f + check("error status field 404", nf.status == 404 && string.str_contains(nf.body, "\"status\":404"));
  let m405b = route_req("DELETE", "/health", "");
  f = f + check("error status field 405", m405b.status == 405 && string.str_contains(m405b.body, "\"status\":405"));
  let okb = route_req("GET", "/api/items/7", "");
  f = f + check("ok body untouched", okb.status == 200 && !string.str_contains(okb.body, "\"error\":"));

  if f == 0 {
    io.println("pulse-app: GREEN");
  } else {
    io.println("pulse-app: RED failures=" + f.to_str());
  }
  return f;
}
