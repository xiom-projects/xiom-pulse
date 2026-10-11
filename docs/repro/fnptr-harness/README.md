<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Witness: module-scope fn-pointer reassignment (REL-20261011-0317-pulse-7)

Ask (PULSE -> compiler, forwarded from the stdlib `test/harness.xi`
wishlist): a module-scope `var handler: fn(Int) -> Int = f0;` must be
callable and reassignable, so a test harness can execute registered
tests (pre-fix failure: codegen `unresolved function symbol handler`).

Fix: m265 (compiler commit `fde5548e`); locks
`tests/regression/m265_module_scope_fnptr` +
`e2e_m265_module_scope_fnptr` in the compiler CI.

## Executed results

- m271 / v0.64.4 build: **exit 0** -- "OK module-scope fn-ptr call +
  reassign + reassign-back" (`probe-logs/fnptr-check/m271.log`).
- v0.64.3 control: **exit 1** -- `error[C001]: codegen: unresolved
  function symbol(s) ... 'handler'` (`probe-logs/fnptr-check/v0643.log`).

Run: `xiom --run docs/repro/fnptr-harness/witness.xi` (exit code =
failure count; self-contained, no stdlib imports beyond `xiom.io`).

Note: PULSE suites do not adopt fn-pointer harness dispatch yet -- the
middleware/jobs design keeps dispatch-by-id -- but the capability is
verified for future test-runner work.
