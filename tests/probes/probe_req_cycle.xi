// XIOM PULSE -- pure HTTP retention probe (no sockets).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Modes:
//   parse  -- http.parse_request on a fixed request, drop it
//   build  -- http.build_response_full for a small JSON body, drop it
//   both   -- parse + build (the server cycle)
// RSS growth here means the floor is in the http package; a flat run
// points at the socket read/write path instead.
module probe_req_cycle

use xiom.io;
use xiom.env;
use xiom.string;
use xiom.pulse.http;
use xiom.convert.parse;

pub fn main() -> Int {
  let args = env.args();
  var mode: Str = "both";
  if args.len() > 1 { mode = args[1]; }
  let nr = parse_int(env.var_or("PROBE_ITERS", "50000"));
  var n: Int = 50000;
  if nr.is_ok { n = nr.value; }
  let raw = http.str_to_bytes("GET /health HTTP/1.1\r\nHost: bench\r\nUser-Agent: probe-cycle/1\r\nAccept: */*\r\n\r\n");
  let body: Str = "{\"status\":\"ok\",\"version\":\"probe\"}";
  var i: Int = 0;
  var acc: Int = 0;
  while i < n {
    if mode == "parse" || mode == "both" {
      let req = http.parse_request(&raw);
      acc = acc + req.target.len();
    }
    if mode == "build" || mode == "both" {
      var hs: Vec[(Str, Str)] = Vec[(Str, Str)].new();
      let resp = http.build_response_full(200, "application/json", &hs, body, true);
      acc = acc + resp.len();
    }
    i = i + 1;
  }
  io.println("done mode=" + mode + " n=" + n.to_str() + " acc=" + acc.to_str());
  return 0;
}
