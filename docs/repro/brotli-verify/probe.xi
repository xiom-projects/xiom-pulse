// probe -- xiom.brotli 0.1.0 consumer-verify (PULSE side)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Consumer-verify for the registry artifact xiom.brotli 0.1.0
// (eco-v0.1.189, sha256 f37f3a39...; PULSE top-tier item 4 --
// compression). Consumes the INSTALLED registry artifact: one-shot +
// streaming encode/decode round trips, the quality sweep, typed
// corrupt/truncated errors, and the RFC 9110 Content-Encoding helpers.
// Exit code = failures (0 = green).
//
// Run (pinned v0.64.5; from this directory):
//   $env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new-20261015-2240\bin\xiom.exe"
//   $env:XIOM_STDLIB = "$env:LOCALAPPDATA\xiom-pins\stdlib-092dfa0c"
//   xiom --run probe.xi @(<port.args.json args from the installed package>)
module brotli_verify

use xiom.io;
use xiom.string.compare;
use xiom.brotli;

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

/// pattern builds a 4096-byte compressible payload ('A'..'Z' cycling).
fn pattern() -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4096 {
    v.push((65 + (i % 26)) as UInt8);
    i = i + 1;
  }
  return v;
}

pub fn main() -> Int {
  var f: Int = 0;

  // 1. pinned upstream version.
  let v = brotli_version();
  f = f + check("version pin is 1.2.0", streq(v, "1.2.0"));

  // 2. RFC 9110 helpers + bound.
  var ok2 = streq(brotli_content_encoding(), "br");
  if !brotli_is_content_encoding("br") {
    ok2 = false;
  }
  if brotli_is_content_encoding("gzip") {
    ok2 = false;
  }
  f = f + check("Content-Encoding helpers ('br')", ok2);
  f = f + check("compress_bound is positive", brotli_compress_bound(4096) > 0);

  // 3. one-shot round trip on a compressible payload.
  var body = pattern();
  let packed = brotli_compress(&mut body, 5, 22, 0);
  var ok3 = false;
  if packed.is_ok {
    var wire: Vec[UInt8] = packed.value;
    ok3 = wire.len() > 0 && wire.len() < 512;
    let back = brotli_decompress_auto(&mut wire);
    if back.is_ok {
      let got: Vec[UInt8] = back.value;
      let ref = pattern();
      ok3 = ok3 && same_bytes(&got, &ref);
    } else {
      ok3 = false;
    }
  }
  f = f + check("one-shot round trip (4096 bytes -> br -> bytes)", ok3);

  // 4. quality sweep: 0, 5, 11 all round-trip byte-exact.
  var ok4 = true;
  var qs = Vec[Int].new();
  qs.push(0);
  qs.push(5);
  qs.push(11);
  var qi: Int = 0;
  while qi < qs.len() {
    var b2 = pattern();
    let p2 = brotli_compress(&mut b2, qs[qi], 22, 0);
    if !p2.is_ok {
      ok4 = false;
    } else {
      var w2: Vec[UInt8] = p2.value;
      let b3 = brotli_decompress_auto(&mut w2);
      if !b3.is_ok {
        ok4 = false;
      } else {
        let g3: Vec[UInt8] = b3.value;
        let r3 = pattern();
        if !same_bytes(&g3, &r3) {
          ok4 = false;
        }
      }
    }
    qi = qi + 1;
  }
  f = f + check("quality sweep (0/5/11) round-trips byte-exact", ok4);

  // 5. streaming decode of a fresh stream, fed in one push.
  var b5 = pattern();
  let p5 = brotli_compress(&mut b5, 5, 22, 0);
  var ok5 = false;
  if p5.is_ok {
    var wire5: Vec[UInt8] = p5.value;
    let d = brotli_decoder_new();
    var out5: Vec[UInt8] = Vec[UInt8].new();
    var off: Int = 0;
    var done: Int = 0;
    var bad: Int = 0;
    var guard: Int = 0;
    while done == 0 && bad == 0 && guard < 64 {
      let st = brotli_decoder_push(d, &mut wire5, off, &mut out5, 65536);
      if !st.is_ok {
        bad = 1;
      } else {
        let prog: BrotliDecodeProgress = st.value;
        off = off + prog.consumed;
        if prog.result == BROTLI_DECODER_RESULT_SUCCESS {
          done = 1;
        } elif prog.result == BROTLI_DECODER_RESULT_ERROR {
          bad = 1;
        } elif prog.consumed == 0 && prog.written == 0 {
          bad = 1; // stall guard
        }
      }
      guard = guard + 1;
    }
    brotli_decoder_destroy(d);
    let r5 = pattern();
    ok5 = done == 1 && bad == 0 && off == wire5.len() && same_bytes(&out5, &r5);
  }
  f = f + check("streaming decode (decoder_push, input fully consumed)", ok5);

  // 6. streaming encode (FINISH op) then decode back.
  var b6 = pattern();
  let en = brotli_encoder_new(5, 22, 0);
  var ok6 = false;
  if en.is_ok {
    let e: Int = en.value;
    var out6: Vec[UInt8] = Vec[UInt8].new();
    var fin: Int = 0;
    var bad6: Int = 0;
    var k: Int = 0;
    while fin == 0 && bad6 == 0 && k < 64 {
      let ps = brotli_encoder_push(e, &mut b6, 0, BROTLI_OPERATION_FINISH, &mut out6, 65536);
      if !ps.is_ok {
        bad6 = 1;
      } else {
        let ep: BrotliEncodeProgress = ps.value;
        if ep.finished == 1 {
          fin = 1;
        }
      }
      k = k + 1;
    }
    let isfin = brotli_encoder_is_finished(e);
    brotli_encoder_destroy(e);
    if bad6 == 0 && fin == 1 {
      var w6: Vec[UInt8] = out6;
      let b7 = brotli_decompress_auto(&mut w6);
      if b7.is_ok {
        let g7: Vec[UInt8] = b7.value;
        let r7 = pattern();
        ok6 = isfin && same_bytes(&g7, &r7);
      }
    }
  }
  f = f + check("streaming encode (FINISH) decodes back byte-exact", ok6);

  // 7. corrupt input -> typed error.
  var garbage = bytes_of("this is not a brotli stream");
  let bad7 = brotli_decompress_auto(&mut garbage);
  f = f + check("corrupt input -> typed error", !bad7.is_ok && bad7.error.len() > 0);

  // 8. truncated stream -> error.
  var b8 = pattern();
  let p8 = brotli_compress(&mut b8, 5, 22, 0);
  var ok8 = false;
  if p8.is_ok {
    let w8: Vec[UInt8] = p8.value;
    var cut: Vec[UInt8] = Vec[UInt8].new();
    var cutto: Int = w8.len() - 4;
    var i8: Int = 0;
    while i8 < cutto {
      cut.push(w8[i8]);
      i8 = i8 + 1;
    }
    let t8 = brotli_decompress_auto(&mut cut);
    ok8 = !t8.is_ok;
  }
  f = f + check("truncated stream -> error", ok8);

  // 9. streaming error detail: upstream code + string after a bad decode.
  let d9 = brotli_decoder_new();
  var g9 = bytes_of("nope, definitely not brotli");
  var o9: Vec[UInt8] = Vec[UInt8].new();
  let s9 = brotli_decoder_push(d9, &mut g9, 0, &mut o9, 65536);
  var ok9 = false;
  if s9.is_ok {
    let pg9: BrotliDecodeProgress = s9.value;
    if pg9.result == BROTLI_DECODER_RESULT_ERROR {
      let code9 = brotli_decoder_error_code(d9);
      ok9 = code9 != 0 && brotli_decoder_error_string(code9).len() > 0;
    }
  } else {
    ok9 = s9.error.len() > 0; // typed bridge error also acceptable
  }
  brotli_decoder_destroy(d9);
  f = f + check("streaming decode failure carries upstream detail", ok9);

  // 10. empty input round trip.
  var e10: Vec[UInt8] = Vec[UInt8].new();
  let p10 = brotli_compress(&mut e10, 5, 22, 0);
  var ok10 = false;
  if p10.is_ok {
    var w10: Vec[UInt8] = p10.value;
    let b10 = brotli_decompress_auto(&mut w10);
    if b10.is_ok {
      let g10: Vec[UInt8] = b10.value;
      ok10 = g10.len() == 0;
    }
  }
  f = f + check("empty input round trip (0 bytes)", ok10);

  io.println("brotli-verify: FAILS=" + f.to_str());
  return f;
}
