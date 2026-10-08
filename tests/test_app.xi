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
use xiom.pulse.metrics;
use xiom.pulse.session;
use xiom.pulse.store;
use xiom.pulse.ratelimit;
use xiom.pulse.validate;
use xiom.pulse.reqctx;
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
  let cw = io.write_file(cf, "{\"port\":12346,\"cors_origin\":\"http://cfg.test\",\"csrf\":false,\"rate_limit\":7}");
  f = f + check("config file write", cw.is_ok);
  env.set_var("PULSE_CONFIG", cf);
  env.remove_var("PULSE_PORT");
  f = f + check("config file load", config.cfg_load_file());
  f = f + check("config file port", config.cfg_port() == 12346);
  f = f + check("config file cors", config.cfg_cors_origin() == "http://cfg.test");
  f = f + check("config file csrf off", !config.cfg_csrf_enabled());
  f = f + check("config file rate", config.cfg_rate_limit() == 7);
  env.set_var("PULSE_PORT", "9999");
  f = f + check("config env wins", config.cfg_load_file() && config.cfg_port() == 9999);
  env.remove_var("PULSE_CONFIG");
  env.remove_var("PULSE_PORT");
  env.remove_var("PULSE_CORS_ORIGIN");
  env.remove_var("PULSE_CSRF");
  env.remove_var("PULSE_RATE_LIMIT");
  let _rmc2 = io.remove_file(cf);

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
  session.session_reset();
  let sid = session.session_create("bob", 60);
  f = f + check("session created", sid.len() == 32);
  f = f + check("session get", session.session_get(sid) == "bob");
  let ch = session.session_cookie_header(sid, 60);
  f = f + check("session cookie header value-only", string.str_starts_with(ch, "sid=" + sid) && !string.str_contains(ch, "Set-Cookie"));
  f = f + check("session cookie parse", session.session_id_from_cookie("a=1; sid=" + sid + "; b=2") == sid);
  f = f + check("session cookie absent", session.session_id_from_cookie("a=1") == "");
  session.session_drop(sid);
  f = f + check("session dropped", session.session_get(sid) == "");
  let ctok = session.csrf_new_token();
  f = f + check("csrf token len", ctok.len() == 32);
  f = f + check("csrf match", session.csrf_matches("sid=x; csrf=" + ctok + "; a=1", ctok));
  f = f + check("csrf mismatch", !session.csrf_matches("csrf=" + ctok, "wrong"));
  f = f + check("csrf absent", !session.csrf_matches("sid=x", ctok));
  session.session_reset();

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
  let tampered = string.str_slice(tok, 0, tok.len() - 1) + "x";
  let vt = jwt.jwt_signature_valid_hs256(tampered, &secret_bytes);
  f = f + check("jwt tamper rejected", vt.is_ok && !vt.value);
  let ve = jwt.jwt_verify_hs256(tok, &secret_bytes, now + 7200);
  f = f + check("jwt exp rejected later", ve.is_err);

  // --- dispatch ------------------------------------------------------------
  let h = route_req("GET", "/health", "");
  f = f + check("dispatch health", h.status == 200 && string.str_contains(h.body, "\"status\":\"ok\""));
  let h405 = route_req("POST", "/health", "");
  f = f + check("dispatch 405 allow", h405.status == 405 && h405.headers.len() == 1);
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

  if f == 0 {
    io.println("pulse-app: GREEN");
  } else {
    io.println("pulse-app: RED failures=" + f.to_str());
  }
  return f;
}
