// XIOM PULSE -- libcurl transport for the outbound seam.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// This module is the only place that links the registry xiom.http client
// (libcurl). Building it requires the package build hook -- the same
// `--c-source` story filed for xiom.sqlite:
//
//   xiom --c-source <xiom-http-bridge.c> --link curl --link-path <dir>
//
// (a bare consumer build fails with undefined curl_easy_* / xiom_read_byte
// symbols; the import alone links fine -- verified 2026-10-10). The server
// build does NOT import this module yet; integrations (0.4) consume it,
// and the guard half in xiom.pulse.outbound is fully probed today.
module xiom.pulse.outbound_transport

use xiom.http;
use xiom.pulse.outbound;

/// outbound_get performs one guarded GET. Complexity: O(response).
pub fn outbound_get(url: Str) -> OutboundResult {
  let plan = outbound.outbound_verdict(url);
  if !plan.allowed {
    return OutboundResult{ ok: false; status: 0; body: ""; error: "blocked_by_ssrf_guard:" + plan.reason };
  }
  let r = http_get(url);
  match r {
    Err(e) => { return OutboundResult{ ok: false; status: 0; body: ""; error: "transport_error:" + e }; },
    Ok(resp) => {
      let cap = outbound.outbound_max_bytes();
      if resp.body.len() > cap {
        return OutboundResult{ ok: false; status: resp.status; body: ""; error: "response_too_large" };
      }
      return OutboundResult{ ok: true; status: resp.status; body: resp.body; error: "" };
    },
  }
  return OutboundResult{ ok: false; status: 0; body: ""; error: "transport_error:unreachable" };
}

/// outbound_post performs one guarded POST. Complexity: O(response).
pub fn outbound_post(url: Str, body: Str, content_type: Str) -> OutboundResult {
  let plan = outbound.outbound_verdict(url);
  if !plan.allowed {
    return OutboundResult{ ok: false; status: 0; body: ""; error: "blocked_by_ssrf_guard:" + plan.reason };
  }
  let r = http_post(url, body, content_type);
  match r {
    Err(e) => { return OutboundResult{ ok: false; status: 0; body: ""; error: "transport_error:" + e }; },
    Ok(resp) => {
      let cap = outbound.outbound_max_bytes();
      if resp.body.len() > cap {
        return OutboundResult{ ok: false; status: resp.status; body: ""; error: "response_too_large" };
      }
      return OutboundResult{ ok: true; status: resp.status; body: resp.body; error: "" };
    },
  }
  return OutboundResult{ ok: false; status: 0; body: ""; error: "transport_error:unreachable" };
}
