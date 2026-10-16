// probe -- xiom.ssl 0.1.0 consumer-verify (PULSE side)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Consumer-verify for the registry artifact xiom.ssl 0.1.0
// (eco-v0.1.189, sha256 ba42cf2b...; PULSE top-tier item 2 -- the TLS
// headline). Consumes the INSTALLED registry artifact. Two legs:
//   * pure checks always run (ALPN wire golden, verify catalogs, the
//     SKIP classification for a bogus soname);
//   * the live leg runs when a libssl build is loadable (Windows with
//     Git's mingw64 bin on PATH): server/client contexts built from the
//     installed fixtures, a full TLS handshake over memory BIOs only
//     (no socket), app data both directions, ALPN negotiated-read,
//     clean shutdown, and the untrusted self-signed rejection path.
// Exit code = failures (0 = green). A live-leg-less host reports
// LIVE=0 with the pure checks green (SKIP semantics, same as the
// package's own CI contract).
//
// Run (pinned v0.64.5; from this directory):
//   $env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new-20261015-2240\bin\xiom.exe"
//   $env:XIOM_STDLIB = "$env:LOCALAPPDATA\xiom-pins\stdlib-092dfa0c"
//   $env:SSL_CERT_PATH / $env:SSL_KEY_PATH = installed fixture PEM paths
//   $env:PATH = "C:\Program Files\Git\mingw64\bin;" + $env:PATH   (live leg)
//   xiom --run probe.xi
module ssl_verify

use xiom.io;
use xiom.env;
use xiom.string.compare;
use xiom.ssl;

// BUG 17 discipline: every Str equality goes through str_compare.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn check(name: Str, ok: Bool) -> Int {
  if ok {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn same_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// bio_move: drain `from`'s outgoing memory BIO into `to`'s incoming BIO.
fn bio_move(lib: &SslLibrary, from: &SslStream, to: &mut SslStream) -> Result[Int, Str] {
  var moved: Int = 0;
  var i: Int = 0;
  while i < 64 {
    let pend = ssl_bio_pending(lib, from);
    if !pend.is_ok {
      return Err(pend.error.message);
    }
    if pend.value == 0 {
      return Ok(moved);
    }
    let chunk = ssl_bio_drain(lib, from, 16384);
    if !chunk.is_ok {
      return Err(chunk.error.message);
    }
    let data: Vec[UInt8] = chunk.value;
    if data.len() == 0 {
      return Ok(moved);
    }
    let w = ssl_bio_feed(lib, to, &data);
    if !w.is_ok {
      return Err(w.error.message);
    }
    moved = moved + data.len();
    i = i + 1;
  }
  return Ok(moved);
}

/// pure_checks: the SKIP-safe surface every host can verify.
fn pure_checks() -> Int {
  var f: Int = 0;

  // ALPN wire golden (RFC 7301): [2,'h','2', 8,'h','t','t','p','/','1','.','1'].
  var names = Vec[Str].new();
  names.push("h2");
  names.push("http/1.1");
  let w = ssl_alpn_wire(&names);
  var ok1 = false;
  if w.is_ok {
    let wire: Vec[UInt8] = w.value;
    var want: Vec[UInt8] = Vec[UInt8].new();
    want.push(2 as UInt8);
    want.push(104 as UInt8);
    want.push(50 as UInt8);
    want.push(8 as UInt8);
    want.push(104 as UInt8);
    want.push(116 as UInt8);
    want.push(116 as UInt8);
    want.push(112 as UInt8);
    want.push(47 as UInt8);
    want.push(49 as UInt8);
    want.push(46 as UInt8);
    want.push(49 as UInt8);
    ok1 = same_bytes(&wire, &want);
  }
  f = f + check("ALPN wire golden (h2, http/1.1)", ok1);

  f = f + check("verify-result catalog names (0 and 18)",
    ssl_verify_result_name(0).len() > 0 && ssl_verify_result_name(18).len() > 0);

  let b = ssl_load_named("libssl-bogus-9.dll");
  var ok3 = false;
  if !b.is_ok {
    ok3 = b.error.kind == SSL_LOAD_ABSENT && b.error.message.len() > 0;
  }
  f = f + check("bogus soname -> typed SSL_LOAD_ABSENT (SKIP classification)", ok3);

  return f;
}

/// live_checks: contexts, memory-BIO handshake, data, ALPN, shutdown,
/// and the untrusted-cert rejection path.
fn live_checks(lib: &SslLibrary, cert_path: Str, key_path: Str) -> Int {
  var f: Int = 0;

  let pr = ssl_probe(lib);
  var okp = false;
  if pr.is_ok {
    let info: SslInfo = pr.value;
    okp = info.version.len() > 0 && info.version_num > 0;
    if okp {
      io.println("ssl-verify: probe: " + info.version);
    }
  }
  f = f + check("probe: version string + packed number", okp);

  // Server context from the installed artifact's fixtures.
  let sc = ssl_ctx_new(lib, true);
  if !sc.is_ok {
    io.println("ssl-verify: server ctx failed: " + sc.error.message);
    return f + 1;
  }
  let sctx: SslContext = sc.value;
  let r1 = ssl_ctx_use_cert_file(lib, &sctx, cert_path, true);
  if !r1.is_ok {
    io.println("ssl-verify: cert load failed: " + r1.error.message);
  }
  let r2 = ssl_ctx_use_key_file(lib, &sctx, key_path, true);
  if !r2.is_ok {
    io.println("ssl-verify: key load failed: " + r2.error.message);
  }
  let r3 = ssl_ctx_check_private_key(lib, &sctx);
  f = f + check("server ctx: cert + key (PEM files) + consistency",
    r1.is_ok && r2.is_ok && r3.is_ok);

  // Client context: verify none + ALPN list (before ssl_new).
  let cc = ssl_ctx_new(lib, false);
  if !cc.is_ok {
    io.println("ssl-verify: client ctx failed: " + cc.error.message);
    ssl_ctx_free(lib, &sctx);
    return f + 1;
  }
  let cctx: SslContext = cc.value;
  ssl_ctx_set_verify(lib, &cctx, SSL_VERIFY_NONE);
  var names = Vec[Str].new();
  names.push("h2");
  names.push("http/1.1");
  let aw = ssl_alpn_wire(&names);
  var okaw = false;
  if aw.is_ok {
    let awv: Vec[UInt8] = aw.value;
    let aset = ssl_ctx_set_alpn_protos(lib, &cctx, &awv);
    okaw = aset.is_ok;
  }
  f = f + check("client ctx: ALPN list set (h2, http/1.1)", okaw);

  // Streams over memory BIOs (no socket anywhere).
  let ns = ssl_new(lib, &sctx);
  let nc = ssl_new(lib, &cctx);
  if !ns.is_ok || !nc.is_ok {
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    io.println("ssl-verify: SSL_new failed");
    return f + 1;
  }
  var srv: SslStream = ns.value;
  var cli: SslStream = nc.value;
  let b1 = ssl_set_bio_mem(lib, &mut srv);
  let b2 = ssl_set_bio_mem(lib, &mut cli);
  var okb = b1.is_ok && b2.is_ok;
  f = f + check("memory-BIO streams attached", okb);
  if !okb {
    ssl_free(lib, &srv);
    ssl_free(lib, &cli);
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return f;
  }

  // Handshake pump: step both sides, move ciphertext between the BIOs.
  var sdone = false;
  var cdone = false;
  var serr = false;
  var cerr = false;
  var rounds: Int = 0;
  while rounds < 2000 && !serr && !cerr && !(sdone && cdone) {
    if !sdone {
      let rs = ssl_step(lib, &srv, true);
      if rs.is_ok {
        if rs.value.done {
          sdone = true;
        }
      } else {
        serr = true;
      }
    }
    if !serr && !cerr && !cdone {
      let rc = ssl_step(lib, &cli, false);
      if rc.is_ok {
        if rc.value.done {
          cdone = true;
        }
      } else {
        cerr = true;
      }
    }
    let _m1 = bio_move(lib, &srv, &mut cli);
    let _m2 = bio_move(lib, &cli, &mut srv);
    rounds = rounds + 1;
  }
  var hs_ok = sdone && cdone && !serr && !cerr;
  f = f + check("TLS handshake over memory BIOs only (no socket)", hs_ok);

  if hs_ok {
    let sv = ssl_get_version(lib, &srv);
    let cv = ssl_get_version(lib, &cli);
    f = f + check("negotiated TLSv1.3 on both ends", streq(sv, "TLSv1.3") && streq(cv, "TLSv1.3"));

    let scip = ssl_get_cipher(lib, &srv);
    let ccip = ssl_get_cipher(lib, &cli);
    f = f + check("cipher negotiated (both ends, equal)", scip.len() > 0 && streq(scip, ccip));

    // App data both directions via the BIO pump.
    let ping = bytes_of("pulse-tls-ping");
    let w1 = ssl_write(lib, &cli, &ping);
    let m1 = bio_move(lib, &cli, &mut srv);
    let rd1 = ssl_read(lib, &srv, 64);
    var okp1 = false;
    if w1.is_ok && m1.is_ok && rd1.is_ok {
      let got: Vec[UInt8] = rd1.value;
      okp1 = w1.value == 14 && got.len() == 14 && same_bytes(&got, &ping);
    }
    let pong = bytes_of("pulse-tls-pong");
    let w2 = ssl_write(lib, &srv, &pong);
    let m2 = bio_move(lib, &srv, &mut cli);
    let rd2 = ssl_read(lib, &cli, 64);
    var okp2 = false;
    if w2.is_ok && m2.is_ok && rd2.is_ok {
      let got2: Vec[UInt8] = rd2.value;
      okp2 = w2.value == 14 && got2.len() == 14 && same_bytes(&got2, &pong);
    }
    f = f + check("app data both directions (ping + pong)", okp1 && okp2);

    // ALPN negotiated read: client offered; the server has no selector
    // (documented), so both ends read "".
    let sa = ssl_alpn_selected(lib, &srv);
    let ca = ssl_alpn_selected(lib, &cli);
    var okal = false;
    if sa.is_ok && ca.is_ok {
      okal = sa.value.len() == 0 && ca.value.len() == 0;
    }
    f = f + check("ALPN negotiated read is empty (no server selector)", okal);

    // Clean shutdown over the BIO pump (close_notify both ways).
    var xdone = false;
    var ydone = false;
    var shf = false;
    var k: Int = 0;
    while k < 128 && !(xdone && ydone) && !shf {
      if !xdone {
        let r = ssl_shutdown(lib, &srv);
        if r.is_ok {
          if r.value == 1 {
            xdone = true;
          }
        } else {
          if !(r.error.kind == SSL_ERR_WANT_READ || r.error.kind == SSL_ERR_WANT_WRITE) {
            shf = true;
          }
        }
      }
      if !ydone && !shf {
        let r2 = ssl_shutdown(lib, &cli);
        if r2.is_ok {
          if r2.value == 1 {
            ydone = true;
          }
        } else {
          if !(r2.error.kind == SSL_ERR_WANT_READ || r2.error.kind == SSL_ERR_WANT_WRITE) {
            shf = true;
          }
        }
      }
      let _p1 = bio_move(lib, &srv, &mut cli);
      let _p2 = bio_move(lib, &cli, &mut srv);
      k = k + 1;
    }
    f = f + check("clean shutdown (close_notify both ways)", !shf && xdone && ydone);
  }

  // Untrusted self-signed path: fresh client ctx with VERIFY_PEER and no
  // trust anchors -> typed handshake error with a non-OK verify result.
  let cc2 = ssl_ctx_new(lib, false);
  if cc2.is_ok {
    let cctx2: SslContext = cc2.value;
    ssl_ctx_set_verify(lib, &cctx2, SSL_VERIFY_PEER);
    let ns2 = ssl_new(lib, &sctx);
    let nc2 = ssl_new(lib, &cctx2);
    if ns2.is_ok && nc2.is_ok {
      var srv2: SslStream = ns2.value;
      var cli2: SslStream = nc2.value;
      let q1 = ssl_set_bio_mem(lib, &mut srv2);
      let q2 = ssl_set_bio_mem(lib, &mut cli2);
      if q1.is_ok && q2.is_ok {
        var d1 = false;
        var d2 = false;
        var e2 = false;
        var e2kind: Int = -1;
        var rr: Int = 0;
        while rr < 2000 && !e2 && !(d1 && d2) {
          if !d1 {
            let a1 = ssl_step(lib, &srv2, true);
            if a1.is_ok {
              if a1.value.done {
                d1 = true;
              }
            }
          }
          if !e2 && !d2 {
            let a2 = ssl_step(lib, &cli2, false);
            if a2.is_ok {
              if a2.value.done {
                d2 = true;
              }
            } else {
              e2 = true;
              e2kind = a2.error.kind;
            }
          }
          let _z1 = bio_move(lib, &srv2, &mut cli2);
          let _z2 = bio_move(lib, &cli2, &mut srv2);
          rr = rr + 1;
        }
        let vr = ssl_get_verify_result(lib, &cli2);
        f = f + check("untrusted self-signed rejected (typed handshake error, verify_result != 0)",
          e2 && e2kind == SSL_ERR_HANDSHAKE && vr != 0);
      } else {
        f = f + check("verify-fail: memory-BIO setup", false);
      }
      ssl_free(lib, &srv2);
      ssl_free(lib, &cli2);
    } else {
      f = f + check("verify-fail: SSL_new", false);
    }
    ssl_ctx_free(lib, &cctx2);
  } else {
    f = f + check("verify-fail: client ctx", false);
  }

  ssl_free(lib, &srv);
  ssl_free(lib, &cli);
  ssl_ctx_free(lib, &cctx);
  ssl_ctx_free(lib, &sctx);
  return f;
}

pub fn main() -> Int {
  var f: Int = pure_checks();

  let lr = ssl_load();
  if lr.is_ok {
    let lib: SslLibrary = lr.value;
    let cert_path = env.var_or("SSL_CERT_PATH", "");
    let key_path = env.var_or("SSL_KEY_PATH", "");
    if cert_path.len() == 0 || key_path.len() == 0 {
      io.println("ssl-verify: SSL_CERT_PATH/SSL_KEY_PATH not set; pure checks only");
      io.println("ssl-verify: LIVE=1 FAILS=" + f.to_str());
      let _cl0 = ssl_close(&lib);
      return f;
    }
    f = f + live_checks(&lib, cert_path, key_path);
    let _cl = ssl_close(&lib);
    io.println("ssl-verify: LIVE=1 FAILS=" + f.to_str());
    return f;
  }

  var okk = lr.error.kind == SSL_LOAD_ABSENT;
  f = f + check("no candidate library -> typed SSL_LOAD_ABSENT (SKIP leg)", okk);
  io.println("ssl-verify: LIVE=0 (no libssl on PATH; SKIP leg) FAILS=" + f.to_str());
  return f;
}
