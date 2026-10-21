// XIOM PULSE -- minimal arm64 module-scope Vec codegen repro.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// `xiom --target arm --emit-ir` then `opt -verify` exposes an invalid
// `load i8*, i8** %struct.Vec*` in the module initializer. The arm64 CI
// build of src/server.xi fails at the same pattern.
module probe_arm64_ginit

var g: Vec[Str] = Vec[Str].new();

pub fn main() -> Int {
  g.push("x");
  return g.len();
}
