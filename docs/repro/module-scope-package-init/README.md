# Module-scope package-constructor init -- compiler finding (v0.64.0, OPEN)

**Filed by:** PULSE lane, 2026-10-05, while wiring the `xiom.rate` limiter.

## Summary

A module-level `var` initialized by a **cross-package constructor call** is
accepted by the checker but emits a call to a function with no definition
(`use of undefined value '@rate_keyed_new'`), or (in a larger program)
produces a runtime `0xC0000005` before `main` prints anything. Function-
scoped (caller-owned) values are unaffected.

## Minimal repro

`probe.xi` (same file at `tests/probes/probe_module_pkg_init.xi`):

```xiom
module pulse_probe_module_pkg_init
use xiom.rate;
use xiom.io;

var b = rate_keyed_new(1, 1);

fn main() -> Int {
  io.println("module-pkg-init ok");
  return 0;
}
```

v0.64.0 actual:

```
error: clang failed with exit code 1
  stderr: xiominput.ll:4356:20: error: use of undefined value '@rate_keyed_new'
  4356 |   %tmp0 = call i64 @rate_keyed_new(i64 1, i64 1)
```

Second evidence point: PULSE's first `src/ratelimit.xi` kept a module-level
`var bucket = rate.rate_keyed_new(1, 1);` inside the program; the suite
compiled and then died with exit `-1073741819` (0xC0000005) **before the
first test printed**, i.e., during module initialization. Moving the
limiter to a caller-owned value (`Limiter` struct created in `main`/tests)
made the same suite green (75 checks).

## Workaround (PULSE)

- Never initialize module-scope variables from package functions; keep
  package aggregates in function-scoped / caller-owned values.
- Module-scope stdlib constructors (`Vec[...].new()`) are fine.

## Suggested fix

Module-scope initializers must reference definitions included in codegen
(emit the callee body or reject with a diagnostic). At minimum, turn the
undefined-value situation into a checker error instead of an IR/clang
failure or a runtime crash.

## Status

OPEN on v0.64.0. Distinct from C-PULSE-06 (missing struct fields); both are
"statically checkable but silently accepted" holes.
