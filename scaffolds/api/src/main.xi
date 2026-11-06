// __APP_NAME__ -- PULSE Beacon API scaffold.
// Copyright (c) 2026 The XIOM Authors. SPDX-License-Identifier: MIT OR Apache-2.0
//
// A minimal production-shaped app: health, JSON, a text echo, a root
// identity, and a JSON 404. Replace the handlers with your routes; keep
// `/health` stable for the edge probe.
module app_main

use xiom.pulse.app;

fn handle(req: &PulseRequest, m: &PulseRoute, body: Str) -> HandlerOut {
  if m.route_id == 1 {
    return app.out_json(200, "{\"status\":\"ok\"}");
  }
  if m.route_id == 2 {
    return app.out_json(200, "{\"message\":\"Hello, World!\"}");
  }
  if m.route_id == 3 {
    return app.out_text(200, body);
  }
  if m.route_id == 4 {
    return app.out_json(200, "{\"app\":\"__APP_NAME__\"}");
  }
  return app.out_json(404, "{\"error\":\"not_found\"}");
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  let _ = app.register("GET", "/api/hello");
  let _ = app.register("POST", "/api/echo");
  let _ = app.register("GET", "/");
  return app.serve(handle);
}
