// probe_app_flow -- replicate the suite's store+dispatch flow with prints.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module pulse_probe_app_flow

use xiom.io;
use xiom.env;
use xiom.pulse.http;
use xiom.pulse.router;
use xiom.pulse.store;
use xiom.pulse.app;

fn route_req(method: Str, target: Str, body: Str) -> HandlerOut {
  let raw_str = method + " " + target + " HTTP/1.1\r\nHost: t\r\nContent-Length: " + body.len().to_str() + "\r\n\r\n" + body;
  let raw = http.str_to_bytes(raw_str);
  let req = http.parse_request(&raw);
  let m = router.route_match(method, target);
  return app.handle_route(m, &req, body);
}

fn main() -> Int {
  let sp = "pulse-appflow.jsonl";
  let _rm = io.remove_file(sp);
  io.println("init=" + store.store_init(sp).to_str());
  let a1 = store.store_append_event(sp, "{\"a\":1}");
  io.println("append1=" + a1.to_str() + " count=" + store.store_count(sp).to_str());

  env.set_var("PULSE_STORE_PATH", sp);
  let ev = route_req("POST", "/api/events", "{\"kind\":\"click\",\"n\":1}");
  io.println("post status=" + ev.status.to_str() + " body=" + ev.body);
  let ec = route_req("GET", "/api/events/count", "");
  io.println("count status=" + ec.status.to_str() + " body=" + ec.body);
  let el = route_req("GET", "/api/events", "");
  io.println("list status=" + el.status.to_str() + " body=" + el.body);
  io.println("count-direct=" + store.store_count(sp).to_str());
  let lines = io.read_file_lines(sp);
  if lines.is_ok {
    let ls = lines.value;
    var i: Int = 0;
    while i < ls.len() {
      io.println("line[" + i.to_str() + "]=[" + ls[i] + "]");
      i = i + 1;
    }
  }
  env.remove_var("PULSE_STORE_PATH");
  let _rm2 = io.remove_file(sp);
  return 0;
}
