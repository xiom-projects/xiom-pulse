// XIOM PULSE -- stream-auth diagnostic (token carriers, redaction, session).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module probe_wsauth

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.pulse.http;
use xiom.pulse.sessions;
use xiom.pulse.station.router;
use xiom.pulse.station.wsauth;

pub fn main() -> Int {
  let st = router.split_target("/api/ws?token=secret&x=1");
  io.println("split path='" + st.0 + "' query='" + st.1 + "'");
  let pq = router.parse_query(st.1);
  io.println("pq len=" + pq.0.len().to_str());
  if pq.0.len() > 0 {
    let n0: Str = pq.0[0];
    let v0: Str = pq.1[0];
    io.println("n0='" + n0 + "' v0='" + v0 + "'");
  }
  if pq.0.len() > 1 {
    let n1: Str = pq.0[1];
    let v1: Str = pq.1[1];
    io.println("n1='" + n1 + "' v1='" + v1 + "'");
  }
  io.println("redact='" + wsauth.redact_target("/api/ws?token=secret&x=1") + "'");
  io.println("redact2='" + wsauth.redact_target("/api/sse?access_token=abc") + "'");

  let raw = http.str_to_bytes("GET /api/ws?token=abc HTTP/1.1\r\nHost: bench\r\n\r\n");
  let req = http.parse_request(&raw);
  io.println("target='" + req.target + "' extract='" + wsauth.extract_token(&req) + "'");

  let sid = sessions.session_create("bob", 60);
  io.println("sid='" + sid + "' get='" + sessions.session_get(sid) + "' fromcookie='" + sessions.session_id_from_cookie("sid=" + sid) + "'");
  env.set_var("PULSE_WS_AUTH", "session");
  let rawc = http.str_to_bytes("GET /api/ws HTTP/1.1\r\nHost: bench\r\nCookie: sid=" + sid + "\r\n\r\n");
  let reqc = http.parse_request(&rawc);
  io.println("cookie_header='" + http.header_get(&reqc, "cookie") + "' denied='" + wsauth.denied_reason(&reqc) + "'");
  env.remove_var("PULSE_WS_AUTH");
  sessions.session_reset();
  return 0;
}
