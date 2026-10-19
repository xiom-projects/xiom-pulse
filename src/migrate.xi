// XIOM PULSE -- pulse_migrate CLI entry (separate binary: SQL stays out of
// the serving/test dependency graph until the SQL class ships fully).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
module xiom.pulse.station.migrate_cli

use xiom.io;
use xiom.env;
use xiom.pulse.station.migrations;

pub fn main() -> Int {
  let av = env.args();
  var sub: Str = "status";
  if av.len() > 1 { sub = av[1]; }
  var force: Bool = false;
  var name: Str = "";
  var i: Int = 2;
  while i < av.len() {
    if av[i] == "--force" { force = true; }
    else { name = av[i]; }
    i = i + 1;
  }
  if sub != "status" && sub != "up" && sub != "down" && sub != "create" {
    io.println("usage: pulse_migrate status|up|down [--force] | create <name>");
    return 1;
  }
  return migrations.cli(sub, force, name);
}
