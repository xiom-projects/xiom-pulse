// XIOM PULSE -- product version (Station build).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Station's own version lives here, NOT in the consumed xiom.pulse package:
// the registry package has its own release line (0.1.0, then 0.2.x), so its
// carved modules must never be the product version source. server.xi keeps
// APP_VERSION in sync (the release checklist bumps both literals).
module xiom.pulse.station.version

/// pulse_version returns the PULSE product version string.
/// Complexity: O(1). Pure.
pub fn pulse_version() -> Str
  ensures: result.len() > 0
{
  "0.2.1"
}
