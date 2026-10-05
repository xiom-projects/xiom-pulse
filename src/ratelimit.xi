// XIOM PULSE -- global request rate limiting (consumer of xiom.rate 0.2.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Single global token bucket because per-client keys need the peer address
// (`socket_peer_addr` is still a stdlib stub). Disabled by default; enable
// with PULSE_RATE_LIMIT=<req/s> (+ optional PULSE_RATE_BURST).
//
// The limiter is a VALUE the caller owns (main/tests), never a module-level
// package struct: module-scope initialization of cross-package aggregates
// crashes on v0.64.0 (same class as C-PULSE-06).
module xiom.pulse.ratelimit

use xiom.rate;

/// Limiter - PULSE's global token bucket wrapper.
pub type Limiter = {
  enabled: Bool;
  bucket: KeyedBuckets;
  per_sec: Int;
}

/// limiter_new builds a limiter; per_sec <= 0 returns a disabled one.
/// Complexity: O(1).
pub fn limiter_new(per_sec: Int, burst: Int) -> Limiter {
  if per_sec <= 0 {
    return Limiter{ enabled: false; bucket: rate.rate_keyed_new(1, 1); per_sec: 0; };
  }
  var cap: Int = burst;
  if cap <= 0 { cap = per_sec; }
  return Limiter{ enabled: true; bucket: rate.rate_keyed_new(cap, per_sec); per_sec: per_sec; };
}

/// limiter_allow consumes one token for the global key.
/// Complexity: O(1) amortized.
pub fn limiter_allow(l: &mut Limiter, now_ms: Int) -> Bool {
  if !l.enabled { return true; }
  return rate.rate_keyed_allow(&mut l.bucket, "global", now_ms);
}

/// limiter_retry_after_ms returns ms until the next token (0 when disabled).
/// Complexity: O(1).
pub fn limiter_retry_after_ms(l: &Limiter, now_ms: Int) -> Int {
  if !l.enabled { return 0; }
  return rate.rate_keyed_retry_after_ms(&l.bucket, "global", 1, now_ms);
}
