// probe_pkg_metrics -- registry-package consumption check: xiom.metrics 0.2.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: .\scripts\run.ps1 tests\probes\probe_pkg_metrics.xi
//      scripts/run.sh   tests\probes\probe_pkg_metrics.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_metrics

use xiom.metrics;
use xiom.string;
use xiom.io;

// C-PULSE-07 workaround: package aggregate held in a plain Vec (module-scope
// Vec.new() is safe; package ctors at module scope crash).
var g_regs: Vec[Registry] = Vec[Registry].new();

fn reg_init() {
  if g_regs.len() == 0 {
    g_regs.push(metric_registry_new());
  }
}

pub fn main() -> Int {
  var fails: Int = 0;

  // --- value types ---------------------------------------------------------
  var c = metric_counter_new();
  metric_counter_inc(&mut c);
  metric_counter_add(&mut c, 4);
  if metric_counter_value(&c) != 5 {
    io.println("[FAIL] counter value");
    fails = fails + 1;
  } else {
    io.println("[PASS] counter value=5");
  }
  metric_counter_reset(&mut c);
  if metric_counter_value(&c) != 0 {
    io.println("[FAIL] counter reset");
    fails = fails + 1;
  } else {
    io.println("[PASS] counter reset");
  }

  var g = metric_gauge_new(10);
  metric_gauge_add(&mut g, 5);
  metric_gauge_set(&mut g, 7);
  if metric_gauge_value(&g) != 7 {
    io.println("[FAIL] gauge value");
    fails = fails + 1;
  } else {
    io.println("[PASS] gauge value=7");
  }

  let bounds = metric_latency_bounds_ms();
  if bounds.len() != 11 {
    io.println("[FAIL] latency bounds len");
    fails = fails + 1;
  } else {
    io.println("[PASS] latency bounds len=11");
  }
  var h = metric_histogram_new(&bounds);
  metric_histogram_observe(&mut h, 3);
  metric_histogram_observe(&mut h, 700);
  if metric_histogram_count(&h) != 2 || metric_histogram_sum(&h) != 703 {
    io.println("[FAIL] histogram count/sum");
    fails = fails + 1;
  } else {
    io.println("[PASS] histogram count=2 sum=703");
  }
  if metric_histogram_min(&h) != 3 || metric_histogram_max(&h) != 700 {
    io.println("[FAIL] histogram min/max");
    fails = fails + 1;
  } else {
    io.println("[PASS] histogram min=3 max=700");
  }
  if metric_histogram_mean(&h) != 351 {
    io.println("[FAIL] histogram mean");
    fails = fails + 1;
  } else {
    io.println("[PASS] histogram mean=351");
  }
  // bounds [1,5,10,...]: 3 falls in le=5 (index 1), 700 in le=1000 (index 8)
  if metric_histogram_bucket_count(&h, 1) != 1 || metric_histogram_bucket_count(&h, 8) != 1 {
    io.println("[FAIL] histogram buckets");
    fails = fails + 1;
  } else {
    io.println("[PASS] histogram buckets");
  }

  var l = metric_labels_new();
  metric_labels_add(&mut l, "class", "2xx");
  if metric_labels_len(&l) != 1 {
    io.println("[FAIL] labels len");
    fails = fails + 1;
  } else {
    io.println("[PASS] labels len=1");
  }
  let ln = metric_labels_name(&l, 0);
  let lv = metric_labels_value(&l, 0);
  if ln.is_err || lv.is_err || ln.value != "class" || lv.value != "2xx" {
    io.println("[FAIL] labels name/value");
    fails = fails + 1;
  } else {
    io.println("[PASS] labels name/value");
  }
  let leq = metric_labels_equal(&l, &l);
  if !leq {
    io.println("[FAIL] labels equal");
    fails = fails + 1;
  } else {
    io.println("[PASS] labels equal");
  }

  // --- registry + labeled + exposition ------------------------------------
  reg_init();
  let l2 = metric_labels_new();
  metric_labels_add(&mut l2, "class", "2xx");
  metric_counter_inc_labeled(&mut g_regs[0], "pulse_http_responses_total", l2, 3);
  let l3 = metric_labels_new();
  metric_labels_add(&mut l3, "class", "4xx");
  metric_counter_inc_labeled(&mut g_regs[0], "pulse_http_responses_total", l3, 1);
  let find2 = metric_registry_find(&g_regs[0], "pulse_http_responses_total", &l2);
  let find9 = metric_registry_find(&g_regs[0], "nope_total", &l2);
  if find2 < 0 || find9 != -1 {
    io.println("[FAIL] registry find");
    fails = fails + 1;
  } else {
    io.println("[PASS] registry find");
  }

  let hb = metric_latency_bounds_ms();
  let hl = metric_labels_new();
  metric_histogram_observe_labeled(&mut g_regs[0], "pulse_http_request_duration_ms", hl, &hb, 3);
  let gl = metric_labels_new();
  metric_gauge_set_labeled(&mut g_regs[0], "pulse_uptime_seconds", gl, 42);

  let txt = metric_exposition(&g_regs[0]);
  if !string.str_contains(txt, "pulse_http_responses_total{class=\"2xx\"} 3") {
    io.println("[FAIL] exposition labeled counter");
    fails = fails + 1;
  } else {
    io.println("[PASS] exposition labeled counter");
  }
  if !string.str_contains(txt, "pulse_http_request_duration_ms_bucket{le=\"5\"} 1") {
    io.println("[FAIL] exposition histogram bucket");
    fails = fails + 1;
  } else {
    io.println("[PASS] exposition histogram bucket");
  }
  if !string.str_contains(txt, "pulse_http_request_duration_ms_count 1") {
    io.println("[FAIL] exposition histogram count");
    fails = fails + 1;
  } else {
    io.println("[PASS] exposition histogram count");
  }
  if !string.str_contains(txt, "pulse_uptime_seconds 42") {
    io.println("[FAIL] exposition gauge");
    fails = fails + 1;
  } else {
    io.println("[PASS] exposition gauge");
  }
  let ct = metric_content_type();
  if !string.str_contains(ct, "0.0.4") {
    io.println("[FAIL] content type");
    fails = fails + 1;
  } else {
    io.println("[PASS] content type");
  }

  if fails == 0 {
    io.println("[PASS] pkg-metrics");
    return 0;
  }
  io.println("[FAIL] pkg-metrics fails=" + fails.to_str());
  return fails;
}
