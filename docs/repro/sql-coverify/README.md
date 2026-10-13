<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Co-verification: xiom.sqlite 0.4.0 SQL driver (PULSE consumer side)

Scope: consumer co-verify requested by the packages lane
(`REL-20261013-1540-packages`, per `docs/requirements/pulse-sql-driver.md`
sec. 4) for the frozen driver surface: SqlDsn.parse (fail-closed), open/
close, execute (rows_affected + last_insert_rowid), query/query_one
(typed values by index; by-name via column_index/value_by_name),
transaction begin/commit/rollback + in_transaction, transactional_ddl/
caps, last_error.

## Result

- **Driver surface: GREEN, 24/24 checks, on v0.64.4 and v0.64.3**
  (in-tree vendored copy of the 0.4.0 sources, `--c-source` against the
  package's vendored `sqlite3.c`).
- **Registry artifact 0.4.0: BLOCKING packaging finding** -- published
  `package.xi` had no `modules:` list -> `use xiom.sqlite;` failed with
  `unresolved import` on both toolchains (control: `xiom.kv`, whose
  manifest declares modules, imports fine). Filed
  (`REL-20261013-1715-pulse`), fixed by packages: **0.4.1 published**
  (eco-v0.1.175, `21c1f673...`, modules restored; install checksum +
  signature verified).
- **Registry artifact 0.4.1 rerun: still blocked, residual cause on the
  compiler side.** The import is now accepted, but the dependency's
  symbols stay undefined (`undefined variable 'SqlDsn'` / `'driver'`,
  T001 cascades, both qualified and unqualified forms). Matches the
  packages lane's systemic multi-module finding (kv single-module
  passes; multi-module sqlite/sdl3 fail) and extends it to the `--run`
  path: `REL-20261013-1731-packages` -> compiler item; PULSE datapoint
  filed (`REL-20261013-1901-pulse`). 1715 closed (manifest fix correct
  + necessary); artifact-level rerun repeats on the next compiler
  candidate.

## How to run

- **Artifact-level (target, after republish):**
  `xiom --run docs/repro/sql-coverify/coverify.xi --c-source
  "<XIOM_HOME>/packages/xiom-sqlite-<ver>/xiom-sqlite/vendor/sqlite3.c"`.
- **In-tree (how this result was produced):** `intree/` vendors the 8
  source files + a manifest; run `xiom --run main.xi --c-source
  "<abs>/vendor/sqlite3.c"` from `intree/`. That mirrors the package's
  own conformance setup (which validated 21/21 in-lane).

## Notes for the driver docs (suggestions)

1. `execute`'s `rows_affected` follows `sqlite3_changes()` -- the LAST
   statement's changes (multi-statement scripts report the final
   statement, not the sum). Worth one README sentence; the co-verify
   initially expected the sum and the driver was right.
2. Consumer call syntax that works in-tree: type-qualified statics are
   unqualified (`SqliteResult.value_by_name(&res, 0, "n")`,
   `SqliteValue.as_int(&v)`); free functions from the root module take
   the module prefix (`sqlite.open`). The README's `driver.`-prefixed
   examples need the modules-list fix to even resolve externally.

## Evidence

- `probe-logs/sql-coverify/`: `main-0644.log` + `main-0643.log`
  (24/24 GREEN each), `root_min.log` + `coverify*.log` (the unresolved-
  import/undefined-alias failures proving the packaging gap).
- Counterparts: `REL-20261013-1715-pulse` (finding),
  `REL-20261013-1540-packages` (request), `REL-20261013-1524-bindings-3`
  (frozen surface).
