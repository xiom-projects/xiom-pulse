<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Repro: `[dependencies]` root matching -- dotted vs dash-form names

**Status: CLOSED on v0.64.1 (2026-10-08).** With the compiler updated in
place to v0.64.1, BOTH variants exit 0 with no `source-roots` workaround
(verified on Windows: `run.ps1` on `dash/probe.xi` and `dot/probe.xi`,
both `exit code: 0`). The m215 dotted-key normalization resolves the
canonical dotted keys to `xiom-rate-0.2.0`-style directories; the
C-PULSE-08 latent name-form gap never shipped. The v0.64.0 results below
are kept as the historical baseline.

**Filed:** 2026-10-07 by the PULSE consumer lane.
**Class:** C-PULSE-02 follow-up (m212 `dependency_roots_under`, latent until
the next compiler archive ships).

## What this tests

`xiom-graph/src/manifest.rs::dependency_roots_under` (m212) maps registry
dependencies to installed package directories:

```rust
let prefix = format!("{}-", dep.name);
// matches dirs under <xiom_home>/packages named "<dep.name>-<version>"
```

The registry package `xiom.rate` installs to
`<xiom_home>/packages/xiom-rate-0.2.0/` (dots become dashes on install), but
the `[dependencies]` key in PULSE's `xiom.toml` is the canonical dotted name
`xiom.rate`. `prefix` is then `xiom.rate-`, which never matches the
`xiom-rate-0.2.0` directory -- dotted dependency keys still get no catalog
roots. The m212 unit tests only cover dash-form keys (`xiom-rate = "0.2"`),
so the gap ships green.

## How to run (WSL/Linux, installed compiler)

The package must be installed first (`xiom pkg install xiom.rate@0.2.0`).

```
cd dash && xiom --check probe.xi   # dash-form key
cd dot  && xiom --check probe.xi   # canonical dotted key
```

## Results (v0.64.0 installed WSL Linux build, 2026-10-07)

| Variant | `[dependencies]` key | Observed |
|---|---|---|
| `dash/` | `xiom-rate = "0.2.0"` | exit 1 -- 6x T001 `undefined variable 'rate'` |
| `dot/`  | `xiom.rate = "0.2.0"` | exit 1 -- identical 6x T001 |

Both variants fail **identically** on the installed v0.64.0 binary (matching
the Windows-side C-PULSE-02 re-test): the released compiler ships **without**
m212, so `[dependencies]` contribute no catalog roots regardless of key
form. `xiom pkg install xiom.rate@0.2.0` preceded both runs (package present
under `<xiom_home>/packages/xiom-rate-0.2.0/`).

The m212 code exists only in the compiler lane checkout
(`crates/xiom-graph/src/manifest.rs::dependency_roots_under`). Its unit
tests cover dash-form keys only (`installed_dependency_roots_are_added` uses
`name: "xiom-rate"` against a `xiom-rate-0.2.0` directory), so when m212
ships, canonical dotted keys will still miss the installed directories
(`prefix = "xiom.rate-"` vs directory `xiom-rate-0.2.0`).

**Acceptance gate for the next archive:** both variants must exit 0. Until
then PULSE keeps its `source-roots` workaround for both platforms.

## Impact

- PULSE keeps the `source-roots` workaround on both platforms until the
  compiler dasherizes `dep.name` before the prefix match (or the package
  manager records the installed directory name).
- Any registry consumer using canonical dotted keys (`xiom.http`, `xiom.kv`,
  ...) with `[dependencies]` hits the same silent miss once the workaround is
  removed.
