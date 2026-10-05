// XIOM PULSE -- in-process service metrics (Prometheus text exposition).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module xiom.pulse.metrics

use xiom.time;

var m_requests: Int = 0;
var m_2xx: Int = 0;
var m_4xx: Int = 0;
var m_5xx: Int = 0;
var m_bytes: Int = 0;
var m_dur_buckets: Vec[Int] = Vec[Int].new();
var m_dur_sum_ms: Int = 0;
var m_dur_count: Int = 0;
var m_start_ms: Int = 0;

/// metrics_mark_start records the process start (first call wins).
/// Complexity: O(1).
pub fn metrics_mark_start(now_ms: Int) {
  if m_start_ms == 0 {
    m_start_ms = now_ms;
  }
}

fn bucket_index(ms: Int) -> Int {
  if ms <= 1 { return 0; }
  if ms <= 5 { return 1; }
  if ms <= 10 { return 2; }
  if ms <= 25 { return 3; }
  if ms <= 50 { return 4; }
  if ms <= 100 { return 5; }
  if ms <= 250 { return 6; }
  if ms <= 500 { return 7; }
  if ms <= 1000 { return 8; }
  if ms <= 2500 { return 9; }
  if ms <= 5000 { return 10; }
  return 11;
}

fn bucket_bound(i: Int) -> Str {
  if i == 0 { return "1"; }
  if i == 1 { return "5"; }
  if i == 2 { return "10"; }
  if i == 3 { return "25"; }
  if i == 4 { return "50"; }
  if i == 5 { return "100"; }
  if i == 6 { return "250"; }
  if i == 7 { return "500"; }
  if i == 8 { return "1000"; }
  if i == 9 { return "2500"; }
  if i == 10 { return "5000"; }
  return "+Inf";
}

/// metrics_record_duration counts one request-duration observation (ms).
/// Complexity: O(1).
pub fn metrics_record_duration(ms: Int) {
  let bi = bucket_index(ms);
  while m_dur_buckets.len() <= bi {
    m_dur_buckets.push(0);
  }
  let cur = m_dur_buckets[bi];
  m_dur_buckets[bi] = cur + 1;
  m_dur_sum_ms = m_dur_sum_ms + ms;
  m_dur_count = m_dur_count + 1;
}

/// metrics_record counts one completed response.
/// Complexity: O(1).
pub fn metrics_record(status: Int, bytes: Int) {
  m_requests = m_requests + 1;
  m_bytes = m_bytes + bytes;
  if status >= 200 && status < 300 {
    m_2xx = m_2xx + 1;
  } else if status >= 400 && status < 500 {
    m_4xx = m_4xx + 1;
  } else if status >= 500 {
    m_5xx = m_5xx + 1;
  }
}

/// metrics_render returns the Prometheus text exposition.
/// Complexity: O(1).
pub fn metrics_render() -> Str {
  var out: Str = "";
  out = out + "# HELP pulse_http_requests_total Total HTTP requests served.\n";
  out = out + "# TYPE pulse_http_requests_total counter\n";
  out = out + "pulse_http_requests_total " + m_requests.to_str() + "\n";
  out = out + "# HELP pulse_http_responses_total Responses by status class.\n";
  out = out + "# TYPE pulse_http_responses_total counter\n";
  out = out + "pulse_http_responses_total{class=\"2xx\"} " + m_2xx.to_str() + "\n";
  out = out + "pulse_http_responses_total{class=\"4xx\"} " + m_4xx.to_str() + "\n";
  out = out + "pulse_http_responses_total{class=\"5xx\"} " + m_5xx.to_str() + "\n";
  out = out + "# HELP pulse_http_bytes_out_total Response body bytes.\n";
  out = out + "# TYPE pulse_http_bytes_out_total counter\n";
  out = out + "pulse_http_bytes_out_total " + m_bytes.to_str() + "\n";
  out = out + "# HELP pulse_http_request_duration_ms Request duration (ms).\n";
  out = out + "# TYPE pulse_http_request_duration_ms histogram\n";
  var cum: Int = 0;
  var bi: Int = 0;
  while bi < 12 {
    var bc: Int = 0;
    if bi < m_dur_buckets.len() {
      bc = m_dur_buckets[bi];
    }
    cum = cum + bc;
    out = out + "pulse_http_request_duration_ms_bucket{le=\"" + bucket_bound(bi) + "\"} " + cum.to_str() + "\n";
    bi = bi + 1;
  }
  out = out + "pulse_http_request_duration_ms_sum " + m_dur_sum_ms.to_str() + "\n";
  out = out + "pulse_http_request_duration_ms_count " + m_dur_count.to_str() + "\n";
  var up_s: Int = 0;
  if m_start_ms > 0 {
    up_s = (time.monotonic_ms() - m_start_ms) / 1000;
  }
  out = out + "# HELP pulse_uptime_seconds Seconds since start.\n";
  out = out + "# TYPE pulse_uptime_seconds gauge\n";
  out = out + "pulse_uptime_seconds " + up_s.to_str() + "\n";
  return out;
}

/// metrics_snapshot returns (requests, 2xx, 4xx, 5xx, bytes).
/// Complexity: O(1).
pub fn metrics_snapshot() -> (Int, Int, Int, Int, Int) {
  return (m_requests, m_2xx, m_4xx, m_5xx, m_bytes);
}

/// metrics_reset zeroes all counters (tests).
/// Complexity: O(1).
pub fn metrics_reset() {
  m_requests = 0;
  m_2xx = 0;
  m_4xx = 0;
  m_5xx = 0;
  m_bytes = 0;
  m_dur_buckets = Vec[Int].new();
  m_dur_sum_ms = 0;
  m_dur_count = 0;
}
