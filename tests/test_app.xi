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
use xiom.time;
use xiom.env;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.envelope;
use xiom.pulse.config;
use xiom.pulse.metrics;
use xiom.pulse.session;
use xiom.pulse.jwt_hs;
use xiom.pulse.store;
use xiom.pulse.server;

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
  return server.handle_route(m, &req, body);
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
  session.session_reset();

  // --- jwt hs256 -----------------------------------------------------------
  let now = time.unix_timestamp();
  let payload = "{\"sub\":\"bob\",\"exp\":" + (now + 3600).to_str() + "}";
  let tok = jwt_hs.hs256_sign(payload, "s3cret");
  f = f + check("jwt sign shape", string.str_contains(tok, "."));
  f = f + check("jwt verify", jwt_hs.hs256_verify(tok, "s3cret"));
  f = f + check("jwt wrong secret", !jwt_hs.hs256_verify(tok, "other"));
  let tampered = string.str_slice(tok, 0, tok.len() - 1) + "x";
  f = f + check("jwt tamper rejected", !jwt_hs.hs256_verify(tampered, "s3cret"));
  f = f + check("jwt exp ok now", jwt_hs.hs256_verify_now(tok, "s3cret", now));
  f = f + check("jwt exp rejected later", !jwt_hs.hs256_verify_now(tok, "s3cret", now + 7200));
  f = f + check("jwt payload text", string.str_contains(jwt_hs.hs256_payload_text(tok), "\"sub\":\"bob\""));

  // --- dispatch ------------------------------------------------------------
  let h = route_req("GET", "/health", "");
  f = f + check("dispatch health", h.status == 200 && string.str_contains(h.body, "\"status\":\"ok\""));
  let h405 = route_req("POST", "/health", "");
  f = f + check("dispatch 405 allow", h405.status == 405 && h405.headers.len() == 1);
  let nf = route_req("GET", "/nope", "");
  f = f + check("dispatch 404 envelope", nf.status == 404 && string.str_contains(nf.body, "\"code\":\"not_found\""));
  let item = route_req("GET", "/api/items/xyz", "");
  f = f + check("dispatch item", item.status == 200 && string.str_contains(item.body, "\"item\":\"xyz\""));
  let login = route_req("POST", "/api/session/login", "{\"user\":\"carol\"}");
  f = f + check("dispatch login 200", login.status == 200 && login.headers.len() == 1);
  f = f + check("dispatch login body", string.str_contains(login.body, "\"user\":\"carol\""));
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
  let e405 = route_req("PUT", "/api/events", "");
  f = f + check("dispatch events 405 allow", e405.status == 405 && e405.headers.len() == 1);
  let evbad = route_req("POST", "/api/events", "notjson");
  f = f + check("dispatch events 400", evbad.status == 400);
  env.remove_var("PULSE_STORE_PATH");
  let rm1 = io.remove_file(sp);
  f = f + check("store cleanup", rm1.is_ok);

  if f == 0 {
    io.println("pulse-app: GREEN");
  } else {
    io.println("pulse-app: RED failures=" + f.to_str());
  }
  return f;
}
