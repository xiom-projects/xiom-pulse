// XIOM PULSE -- service metrics on registry xiom.metrics 0.2.0
// (labeled counters + latency-bounds histogram + Prometheus exposition).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The registry is a caller-owned package aggregate held in a plain Vec
// (C-PULSE-07). Shadow Int counters keep metrics_snapshot O(1) (the package
// exposes no value-by-index getter).
module xiom.pulse.metrics

use xiom.metrics;
use xiom.time;

var m_regs: Vec[Registry] = Vec[Registry].new();
var m_start_ms: Int = 0;
var m_requests: Int = 0;
var m_2xx: Int = 0;
var m_4xx: Int = 0;
var m_5xx: Int = 0;
var m_bytes: Int = 0;

fn ensure() {
  if m_regs.len() == 0 {
    m_regs.push(metric_registry_new());
  }
}

fn inc_class(cls: Str, delta: Int) {
  let l = metric_labels_new();
  metric_labels_add(&mut l, "class", cls);
  metric_counter_inc_labeled(&mut m_regs[0], "pulse_http_responses_total", l, delta);
}

/// metrics_mark_start records the process start (first call wins).
/// Complexity: O(1).
pub fn metrics_mark_start(now_ms: Int) {
  if m_start_ms == 0 {
    m_start_ms = now_ms;
  }
}

/// metrics_record counts one completed response.
/// Complexity: O(1).
pub fn metrics_record(status: Int, bytes: Int) {
  ensure();
  let l = metric_labels_new();
  metric_counter_inc_labeled(&mut m_regs[0], "pulse_http_requests_total", l, 1);
  let lb = metric_labels_new();
  metric_counter_inc_labeled(&mut m_regs[0], "pulse_http_bytes_out_total", lb, bytes);
  m_requests = m_requests + 1;
  m_bytes = m_bytes + bytes;
  if status >= 200 && status < 300 {
    inc_class("2xx", 1);
    m_2xx = m_2xx + 1;
  } else if status >= 400 && status < 500 {
    inc_class("4xx", 1);
    m_4xx = m_4xx + 1;
  } else if status >= 500 {
    inc_class("5xx", 1);
    m_5xx = m_5xx + 1;
  }
}

/// metrics_record_duration counts one request-duration observation (ms).
/// Complexity: O(1).
pub fn metrics_record_duration(ms: Int) {
  ensure();
  let hb = metric_latency_bounds_ms();
  let hl = metric_labels_new();
  metric_histogram_observe_labeled(&mut m_regs[0], "pulse_http_request_duration_ms", hl, &hb, ms);
}

/// metrics_render returns the Prometheus text exposition. The uptime gauge
/// is set at render time; `pulse_store_records` and `pulse_app_info` are
/// appended by server.xi (they need app state at request time).
/// Complexity: O(1) plus exposition size.
pub fn metrics_render() -> Str {
  ensure();
  var up_s: Int = 0;
  if m_start_ms > 0 {
    up_s = (time.monotonic_ms() - m_start_ms) / 1000;
  }
  let lg = metric_labels_new();
  metric_gauge_set_labeled(&mut m_regs[0], "pulse_uptime_seconds", lg, up_s);
  return metric_exposition(&m_regs[0]);
}

/// metrics_snapshot returns (requests, 2xx, 4xx, 5xx, bytes).
/// Complexity: O(1).
pub fn metrics_snapshot() -> (Int, Int, Int, Int, Int) {
  return (m_requests, m_2xx, m_4xx, m_5xx, m_bytes);
}

/// metrics_reset zeroes all counters (tests).
/// Complexity: O(1).
pub fn metrics_reset() {
  m_regs = Vec[Registry].new();
  m_requests = 0;
  m_2xx = 0;
  m_4xx = 0;
  m_5xx = 0;
  m_bytes = 0;
}
