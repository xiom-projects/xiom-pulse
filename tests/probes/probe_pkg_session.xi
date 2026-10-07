// probe_pkg_session -- registry-package consumption check: xiom.session 0.1.0.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Run: scripts/run.sh tests\probes\probe_pkg_session.xi
// Exit code = failures (0 = green).
module pulse_probe_pkg_session

use xiom.session;
use xiom.string;
use xiom.io;

// C-PULSE-07 workaround: package aggregates live in a plain Vec at module
// scope; store[0] is the default-TTL store, store[1] a short-TTL one.
var g_stores: Vec[SessionStore] = Vec[SessionStore].new();

fn stores_init() {
  if g_stores.len() == 0 {
    g_stores.push(session_store_new(60000));
    g_stores.push(session_store_new(1000));
  }
}

pub fn main() -> Int {
  var fails: Int = 0;
  stores_init();

  if session_store_ttl_ms(&g_stores[0]) != 60000 {
    io.println("[FAIL] store ttl");
    fails = fails + 1;
  } else {
    io.println("[PASS] store ttl=60000");
  }
  if session_count(&g_stores[0]) != 0 {
    io.println("[FAIL] store starts empty");
    fails = fails + 1;
  } else {
    io.println("[PASS] store starts empty");
  }

  // --- create + id shape ---------------------------------------------------
  let cr = session_create(&mut g_stores[0], 0);
  if cr.is_err {
    io.println("[FAIL] session create");
    fails = fails + 1;
  } else {
    let sid = cr.value;
    if !session_id_valid(sid) {
      io.println("[FAIL] id shape");
      fails = fails + 1;
    } else {
      io.println("[PASS] session create + id shape");
    }
    if session_count(&g_stores[0]) != 1 {
      io.println("[FAIL] count after create");
      fails = fails + 1;
    } else {
      io.println("[PASS] count=1 after create");
    }

    // --- set + read --------------------------------------------------------
    if !session_set(&mut g_stores[0], sid, "user", "carol", 0) {
      io.println("[FAIL] session set");
      fails = fails + 1;
    } else {
      io.println("[PASS] session set");
    }
    let uv = session_value(&g_stores[0], sid, "user", 0);
    if uv.is_none || uv.value != "carol" {
      io.println("[FAIL] session value");
      fails = fails + 1;
    } else {
      io.println("[PASS] session value user=carol");
    }
    let mk = session_value(&g_stores[0], sid, "nope", 0);
    if !mk.is_none {
      io.println("[FAIL] missing key must be none");
      fails = fails + 1;
    } else {
      io.println("[PASS] missing key none");
    }

    // --- expiry ------------------------------------------------------------
    let ge = session_get(&g_stores[0], sid, 70000);
    if !ge.is_none {
      io.println("[FAIL] expired session still returned");
      fails = fails + 1;
    } else {
      io.println("[PASS] expired session none");
    }

    // --- rotate ------------------------------------------------------------
    let rr = session_rotate(&mut g_stores[0], sid, 1000);
    if rr.is_err {
      io.println("[FAIL] session rotate");
      fails = fails + 1;
    } else {
      let nid = rr.value;
      let old = session_get(&g_stores[0], sid, 1000);
      if nid == sid || !old.is_none {
        io.println("[FAIL] rotate left the old id valid");
        fails = fails + 1;
      } else {
        io.println("[PASS] session rotate");
      }
    }
  }

  // --- prune ---------------------------------------------------------------
  let cr2 = session_create(&mut g_stores[1], 0);
  if cr2.is_err {
    io.println("[FAIL] short-ttl create");
    fails = fails + 1;
  } else {
    let pruned = session_prune(&mut g_stores[1], 5000);
    if pruned != 1 {
      io.println("[FAIL] prune count");
      fails = fails + 1;
    } else {
      io.println("[PASS] prune removed 1");
    }
  }

  // --- cookies -------------------------------------------------------------
  let ch = session_cookie_header("sid", "abc", 3600, false);
  if !string.str_contains(ch, "sid=abc") || !string.str_contains(ch, "HttpOnly") {
    io.println("[FAIL] cookie header: " + ch);
    fails = fails + 1;
  } else {
    io.println("[PASS] cookie header");
  }
  if string.str_contains(ch, "Secure") {
    io.println("[FAIL] insecure cookie marked Secure");
    fails = fails + 1;
  } else {
    io.println("[PASS] insecure cookie unmarked");
  }
  let chs = session_cookie_header("sid", "abc", 3600, true);
  if !string.str_contains(chs, "Secure") {
    io.println("[FAIL] secure cookie attribute");
    fails = fails + 1;
  } else {
    io.println("[PASS] secure cookie attribute");
  }
  let cc = session_cookie_clear("sid");
  if !string.str_contains(cc, "Max-Age=0") {
    io.println("[FAIL] cookie clear");
    fails = fails + 1;
  } else {
    io.println("[PASS] cookie clear");
  }

  if fails == 0 {
    io.println("[PASS] pkg-session");
    return 0;
  }
  io.println("[FAIL] pkg-session fails=" + fails.to_str());
  return fails;
}
