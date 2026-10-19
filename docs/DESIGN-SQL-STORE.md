<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: SQL store + repository/query layer (knex query builder)

Status: **IMPLEMENTED (2026-10-19, session 22)** -- `src/sql.xi` is the
runtime SQL surface over `xiom.sqlite` 0.4.1; `tests/test_sql.xi` is the
dedicated gate (**53/53 on Windows + WSL**, CI Linux leg added). The serving
binary does **not** import this module (or the driver): SQL stays opt-in
until the pool and the serving-grade surface are settled. `pulse_migrate`
remains the separate tool binary. Evidence: `probe-logs/sql-test-*`.

References: `E:\repos\knex` (knex.js 3.3.0, MIT, light clone) -- the
immutable query-builder compilation, identifier wrapping, value binding and
transaction discipline. Driver contract: `xiom.sqlite.driver` 0.4.1
(`docs/requirements/pulse-sql-driver.md` in the packages repo). Companion:
`docs/DESIGN-SQL-MIGRATIONS.md` (the runner built on the same driver).

## 1. Problem statement

The SQL class today is **tool-only**: migrations run through
`pulse_migrate`, but application code has no sanctioned way to:

- execute a query with values that are guaranteed to be *bound* rather
  than concatenated (the package's `xiom.sqlite.query` helpers interpolate
  literals and must not be used for untrusted input);
- map rows to a stable wire shape without leaking driver types across the
  compiler's imported-struct fault line (m371);
- page a table with a truthful `has_more`, or run a unit of work inside an
  explicit transaction with a rollback-on-first-error rule.

This unit fixes that surface before it is wired into the serving binary.

## 2. Reference matrix (crawled, not recalled)

| Reference (knex 3.3.0) | Mechanism | What PULSE needs | XIOM conversion |
|---|---|---|---|
| `lib/query/querybuilder.js:400-470` `where()` | one entry point normalizes `where(col, value)`, `where(col, op, value)`; `null` becomes `whereNull`; `in`/`between` dispatch before the basic form | a small, predictable predicate set instead of a string API | fixed helpers (`where_*` via the repository functions + raw SQL with bound params); operators never come from untrusted text |
| `lib/query/querybuilder.js:535-545` `_objectWhere()` | object literals expand to AND-ed equality predicates | ergonomic equality filters | repository equality keys; arrays of filters can be added later without changing the wire format |
| `lib/query/querycompiler.js:619-681` `where()` | compiles predicate objects into fragments **and appends values to a parallel bindings list** | SQL text and values stay separate | compile `sql` + `Vec[Str]` encoded params; never splice a value into the SQL string |
| `lib/client.js:578-601` `parameterize()` | turns values into an ordered `?, ?, ...` list, pushing each value into `bindingsHolder` | one binding per placeholder, in order | `p_*()` encoders + `bind_all()` in placeholder order |
| `lib/formatter/wrappingFormatter.js:86-134` `wrap()` / `unwrapRaw()` | identifiers are wrapped separately from values; raw values become parameters | identifiers are trusted only after validation; values are always bound | `ident_ok()` (ASCII `[A-Za-z_][A-Za-z0-9_]*`) is the only path that interpolates text; all values go through `sqlite.bind_*` |
| `lib/query/querybuilder.js:1144-1153` `first()` | `first()` is `limit(1)` plus a single-row response contract | single-record reads | `find_json()` returns one object or `null` |
| `lib/query/querybuilder.js:1225-1264` `insert()` / `update()` | object/key forms become explicit column lists and bound values; `returning` is optional | CRUD with generated ids | `insert_json()` reports `rows_affected` + `last_insert_rowid`; `update_json()`/`delete_json()` report `rows_affected` |
| `lib/execution/runner.js:135-165` `query()` | one execution path; response post-processing is a separate step | one executor, one mapping step | `run_prepared()` executes + maps rows; error text is the driver's code+message pair |
| `lib/execution/transaction.js:101-165` `begin()`/`commit()`/`rollback()` | explicit BEGIN/COMMIT/ROLLBACK; rollback is the failure path | unit-of-work control | `tx_begin()`/`tx_commit()`/`tx_rollback()` on the same handle; the caller reports the **original** error after rollback (driver contract) |
| `lib/query/querybuilder.js:83-90` `toSQL()`/`clone()` | builder compiles to `{sql, bindings}`; clone gives a new chain | compile-once, no hidden mutable state | no persistent builder object in v1: each repository call compiles a fresh statement |

Also adopted from the migrations unit: lexicographic/UTC discipline is not
relevant here; the lock/heartbeat tables stay in `migrations.xi`.

## 3. Surface decision

### D1. Module boundary

`xiom.pulse.station.sql` (source `src/sql.xi`) is an **opt-in Station
module**. It is declared in `package.xi` for resolution, but no serving
path imports it. `src/server.xi` and the existing suites therefore keep
building without the vendored SQLite C source. Builds that include this
module (the SQL test) pass `--c-source` explicitly.

### D2. Handles are integers

The module keeps a small append-only connection registry
(`Vec[driver.SqlDriver]` + a closed-handle list) and exposes `open()` as
`Result[Int, Str]`. Callers never receive a PULSE struct across module
boundaries; this is the conservative side of compiler finding m371
(imported-struct identity/field access). It mirrors the proven
module-local-holder pattern in `src/store.xi` (kv backend).

### D3. Binding is mandatory

- Values are encoded with `p_text()`, `p_int()`, `p_real()`, `p_null()`
  and bound through `xiom.sqlite.prepare` + `bind_*` + `step`.
- `execute` (multi-statement DDL, no values) remains available as
  `exec()`; `exec_params()` uses a prepared single statement.
- Identifiers (table/column names) are the only interpolated tokens and
  must pass `ident_ok()`. Anything else is an `Err` and no SQL runs.
- The package's `xiom.sqlite.query` builder is **not** used: it
  interpolates values directly into SQL.

### D4. Wire shape

Rows are returned as JSON text:

- `query_json()` -> `[ {col: value, ...}, ... ]`
- `query_one_json()` -> one object or `null`
- `find_json()` -> one object or `null`
- `list_json()` -> `{ "rows": [...], "has_more": bool }`
- `count_json()` -> `{ "count": N }`
- CRUD -> `{ "rows_affected": N }` (insert also
  `"last_insert_rowid": N`)

Integers are emitted exactly (`int.to_str()`), reals via
`convert.float_to_string`, text via `json_escape`, SQL NULL as `null`.
Blobs are **not** part of the v1 JSON surface: `xiom.sqlite` 0.4.1 has no
`column_blob` accessor, and pretending a blob is text would be worse than
refusing it. A blob column maps to `null` and the docs say so.

### D5. Paging

`list_json()` implements knex's `limit+1` technique: it selects one row
past `limit`, sets `has_more`, and drops the probe row. `limit` is capped
at 1000 to keep one response bounded.

### D6. Transactions

Explicit `tx_begin()` / `tx_commit()` / `tx_rollback()` on the connection
handle. No implicit transaction wrapping and no nested transactions in
v1 (SQLite savepoints are a later unit). The documented failure path is
the driver's: on the first `Err`, roll back, then report the original
error.

### D7. No pool yet

One handle owns one connection. SQLite serializes writers; WAL and
`busy_timeout` are set through the DSN (`?busy_timeout=5000&journal_mode=wal`).
Connection pooling and a request-scoped acquisition contract belong to
W1/W5, after the serving surface is decided. That is why SQL remains out
of the serving binary in this unit.

### D8. Error model

`Result[_, Str]`; error text is `"SQLITE <code>: <message>"` (or a
validation error such as `"sql: invalid table identifier"`). No silent
fallback, no empty result on failure. `last_error(handle)` exposes the
connection's pair for diagnostics.

## 4. Public API (v1)

Connections:
`open(dsn) -> Result[Int, Str]`, `close(handle) -> Bool`,
`ping(handle) -> Bool`, `last_error(handle) -> Str`,
`in_tx(handle) -> Bool`.

Binding helpers:
`p_text(Str)`, `p_int(Int)`, `p_real(Float64)`, `p_null()` -> encoded
parameter strings.

Raw execution:
`exec(handle, sql) -> Result[Int, Str]` (rows affected),
`exec_params(handle, sql, params) -> Result[Int, Str]`.

Queries:
`query_json(handle, sql)`, `query_params_json(handle, sql, params)`,
`query_one_json(handle, sql)`, `query_one_params_json(handle, sql, params)`.

Repository:
`find_json(handle, table, key_column, key_value)`,
`list_json(handle, table, order_column, desc, limit, offset)`,
`count_json(handle, table)`,
`insert_json(handle, table, columns, values)`,
`update_json(handle, table, set_columns, set_values, key_column, key_value)`,
`delete_json(handle, table, key_column, key_value)`.

Transactions: `tx_begin`, `tx_commit`, `tx_rollback`.

## 5. Test plan (tests/test_sql.xi)

- open/close/ping; closed and invalid handles fail closed.
- DDL through `exec`; insert/update/delete through bound values.
- Exact integer round-trip and real/text/null mapping.
- `find_json` hit/miss; `list_json` paging incl. `has_more` boundary;
  `count_json`.
- Injection: a malicious table/column identifier is an `Err`; a value
  containing quotes/`OR 1=1` is bound literally and changes nothing.
- Invalid parameter encoding is an `Err`; bad SQL returns the code+message
  pair.
- Transactions: rollback drops the insert; commit keeps it.
- `query_params_json` with integer and text placeholders.

## 6. Out of scope (explicit)

- ORM/model mapping, relations, schema diffing.
- Blob read/write in the JSON surface (no binding accessor yet).
- Nested transactions/savepoints.
- Pooling, request-scoped connections, serving integration.
- Per-engine dialect abstraction (sqlite first; postgres/mysql later).
