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
- **Registry artifact: BLOCKING FINDING** -- `xiom pkg install
  xiom.sqlite@0.4.0` (checksum+signature verified) is not consumable by
  an external project: the published `package.xi` has no `modules:`
  list, so `use xiom.sqlite;` fails with `unresolved import` on both
  toolchains (control: `xiom.kv`, whose manifest declares modules,
  imports fine). Filed to packages (bug, high,
  `REL-20261013-1715-pulse`); the artifact-level rerun happens when the
  fixed publish lands.

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
