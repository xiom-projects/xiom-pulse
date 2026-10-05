// probe_method_receiver -- isolate struct-by-value method receiver reads.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A { fd: Int } type with ident()/take() methods, called on a local, a
// Result payload and a tuple element. All must print fd=432.
module pulse_probe_method_receiver

use xiom.io;

pub type Fd = { fd: Int; }

pub fn Fd.ident(self) -> Int {
  return self.fd;
}

pub fn Fd.take(self, buf: &mut Vec[UInt8]) -> Int {
  io.println("take self.fd=" + self.fd.to_str());
  buf.push(7u8);
  return self.fd;
}

fn mkr() -> Result[(Fd, Str), Str] {
  return Ok((Fd{ fd: 432; }, "peer"));
}

fn main() -> Int {
  let a = Fd{ fd: 432; };
  io.println("direct=" + a.fd.to_str());
  io.println("ident-local=" + a.ident().to_str());
  var b1: Vec[UInt8] = Vec[UInt8].new();
  let t1 = a.take(&mut b1);
  io.println("take-local=" + t1.to_str() + " len1=" + b1.len().to_str());

  let r = mkr();
  if r.is_err {
    io.println("[FAIL] mkr");
    return 1;
  }
  let pair = r.value;
  let s = pair.0;
  io.println("tuple.fd=" + s.fd.to_str());
  io.println("ident-tuple=" + s.ident().to_str());
  var b2: Vec[UInt8] = Vec[UInt8].new();
  let t2 = s.take(&mut b2);
  io.println("take-tuple=" + t2.to_str() + " len2=" + b2.len().to_str());

  if a.fd == 432 && b1.len() == 1 && s.fd == 432 && b2.len() == 1 {
    io.println("[PASS] method-receiver");
    return 0;
  }
  io.println("[FAIL] method-receiver");
  return 1;
}
