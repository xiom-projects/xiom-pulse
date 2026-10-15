<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Batch-5 witness: the `&HandlerOut` ref-param helper (REL-20261010-1854/2122)

Re-verification lock for the compiler batch-5 gate
("PULSE STARTUP AV: the `&HandlerOut`-helper shape compiles and runs").

## Shape (from REL-20261010-2122-pulse)

A module-level helper taking `&HandlerOut` and returning `Str` (body,
falling back to the byte buffer), called from the suite. The helper
*alone* in a 20-line probe is fine -- the suite context is required to
trigger the crash.

## Protocol

1. From the PULSE repo root: `git apply docs/repro/handlerout-helper/witness.patch`
   (patch against the current `tests/test_app.xi`).
2. Run: `scripts\run.ps1 tests\test_app.xi` with the pinned toolchain
   env (`XIOM_COMPILER` v0.64.3+ / `XIOM_STDLIB` at the consumed pin).
3. **Pre-fix expectation**: exit `-1073741819` (0xC0000005 access
   violation) after `compiled: a.exe` -- captured 2026-10-11 on v0.64.3,
   evidence `probe-logs/repro-2122-20261011.log`.
4. **Post-fix expectation** (batch 5 shipped): suite GREEN, including
   the `batch5 witness helper` PASS line.
5. Revert the patch afterwards (`git checkout -- tests/test_app.xi`).
   Once green, the helper + check can be re-landed permanently as the
   positive lock (the site-mode workaround was inlining; no other
   re-land is pending).

## Executed results

- 2026-10-11 (pre-fix, v0.64.3): **RED** -- suite exit `-1073741819`
  (0xC0000005) after compiling (`probe-logs/repro-2122-20261011.log`).
- 2026-10-11 (post-fix, m271/v0.64.4 build, pin `dd352f6`): **GREEN** --
  suite exit 0 including the helper check
  (`probe-logs/witness5-m271-reverify.log`).
- 2026-10-15 (released v0.64.5, pin `092dfa0c`): **GREEN** -- suite exit
  0 including the helper check; the helper + check were **RE-LANDED
  PERMANENTLY** into `tests/test_app.xi` alongside the v0.64.5 CI pin
  move. This directory stays as the witness record; `witness.patch` is
  now applied in-tree (no longer a floating patch).

## Evidence trail

- `witness.patch` -- the exact suite edit (helper + one call).
- `probe-logs/repro-2122-20261011.log` (local, gitignored) -- the red run.
- Origin items: `REL-20261010-1854-pulse` (site-mode startup crash),
  `REL-20261010-2122-pulse` (bisect: `&HandlerOut` helper = 0xC0000005;
  inlining avoids it), compiler batch plan `REL-20261011-1342-compiler`
  (batch 5 is this gate).
