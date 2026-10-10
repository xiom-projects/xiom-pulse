<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Compiler relay -- 2026-10-09: v0.64.2 release-ready (Pulse lane)

> **Coordination retired (2026-10-10):** hand-carried relays are replaced
> by the private `xiom-lang/xiom-relays` bus
> (`python tools/relay.py view --lane compiler`). Frozen history +
> evidence; the live asks are bus items.

Status from the XIOM compiler lane.

## Release state

v0.64.2 is RELEASE-READY on local main (compiler repo); tag/push held for
the owner's call. Final gates green: e2e 2458/0/4 (without XIOM_STDLIB),
feature 549, xiom-check 197 + checker_locks 29, xiom-verify 9+36,
xiom-graph 34, driver 61+6+integration; nine-tool release build green;
version 0.64.2 == STDLIB_VERSION 4dd884423ab7ea39a3962630d1ea2552bfd16a2d.

## Your findings in this batch

- C-PULSE-08 `[dependencies]` dotted keys: FIXED (m215).
- C-PULSE-09 package-aggregate wrapper crash: fixed in the m223..m227
  batch; re-run `probe_adopt_smoke.xi` on the v0.64.2 archive to confirm.
- C-PULSE-10: closed (kv_get address-like Str fixed).
- C-PULSE-11 `pub type X = PackageType`: fixed (swap retry acceptance).
- C-PULSE-13: installer home unified (m232).
- General: m228 `--run` exit codes, m231 enum-payload determinism, m234
  Vec stride padding, m239 deep container equality (Vec/Option/Result
  content `==`).

## Open compiler-side (not blockers)

- Triplicate sibling exports break alias-qualified calls (wave-97
  finding, reproduced on v0.64.2; next batch).
- Map/Set `==` content equality: documented design, not implemented.

## Ask

When the v0.64.2 tag lands: re-run your probe suite (especially
probe_adopt_smoke.xi and the kv probes) on it, drop obsolete workarounds,
and relay residual reds with minimal repros.
