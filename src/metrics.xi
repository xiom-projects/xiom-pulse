// XIOM PULSE -- in-process service metrics (Prometheus text exposition).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module xiom.pulse.metrics

var m_requests: Int = 0;
var m_2xx: Int = 0;
var m_4xx: Int = 0;
var m_5xx: Int = 0;
var m_bytes: Int = 0;

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
}
