<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: SQL serving surface (0.3.0 decision)

Status: **PROPOSED (2026-10-22)**. This is the decision that was open when
the SQL class landed: whether the stock serving binary should link
SQLite. Recommendation: **keep `pulse_app` SQL-free; expose the SQL
class as an opt-in library for application binaries.** The owner can
approve or redirect before the 0.3.0 cut.

Companion: `docs/DESIGN-SQL-STORE.md` (repository/query layer),
`docs/DESIGN-SQL-MIGRATIONS.md` (runner + tool).

## 1. Context

- `src/sql.xi` (repository/query layer) and `src/migrations.xi` are
  implemented and gated (SQL 53/53, migrations 21/21).
- `pulse_app` uses the JSONL/KV event store; it does not import SQL and
  therefore builds without the vendored SQLite C source.
- The owner directive was explicit: keep SQL out of the serving binary
  until the surface is decided.
- Release 0.3.0 is otherwise ready (realtime, per-route rate, bench
  baseline, linux-arm64, release dry-run); the serving SQL question is
  the remaining scope item.

## 2. Decision

### D1. The SQL class is an application-library surface

`xiom.pulse.station.sql` stays a normal module that application entry
modules import. The stock `src/server.xi` does not import it.

### D2. The stock event store stays JSONL/KV

No SQL event-store backend is added in 0.3.0. The `store` seam keeps its
jsonl/kv backends; swapping it to SQL would be a separate design with a
migration story for existing events.

### D3. SQL apps are separate binaries

An app that wants SQL writes a small entry module:

```xiom
module my_app
use xiom.pulse.station.sql;
// open(dsn), use the repository functions, then run the app's serve loop.
```

The build scripts already detect `use ...sql` and pass the vendored
SQLite C source; the stock `pulse_app` build does not. This is the same
rule the migrations tool follows.

### D4. One connection per process in 0.3.0

The serving loop is single-threaded; a pool adds no concurrency today.
Applications open one handle (or one per worker process) with a WAL +
busy_timeout DSN. Pooling and request-scoped acquisition are a future
unit, after the worker/scale-out work.

### D5. Transactions and error discipline

The repository API keeps explicit `tx_begin`/`tx_commit`/`tx_rollback`.
On the first error the app rolls back and reports the original error;
no implicit retries. Blobs remain outside the v1 JSON surface.

### D6. Migration gate before serving

The app runs `pulse_migrate status` (or the same runner API) before it
starts serving and refuses to start if `pending != 0` or `missing != 0`.
The backup fence is the tool's (`PULSE_SQL_BACKUP_MANIFEST` /
`--no-backup-check`); a library helper can wrap this later.

### D7. Release impact

0.3.0 ships this as an opt-in capability. The release fleet and assets
are unchanged (stock app: linux-x64, linux-arm64, windows-x64; macOS
gated), and no SQLite runtime is added to the stock binary. App authors
build their own SQL binary with the vendored C source.

### D8. Security

DSN values/secrets come from the environment; no SQL values are logged.
Identifiers are validated by the layer; values are always bound. File
permissions on the DB/backup directory are the operator's job.

## 3. Alternatives considered

| Alternative | Why not now |
|---|---|
| Link SQLite into the stock server | Adds the C build to every release leg and every deployment for routes the stock app does not use; the event-store backend is not designed. |
| Runtime dynamic loading of sqlite | XIOM has no sanctioned plugin/FFI loading path for this; adds deployment fragility. |
| SQL event-store backend now | Needs an event migration/import story and a store-seam design; separate unit. |
| Pool immediately | The loop is single-connection today; a pool would be unused complexity. Revisit with workers. |

## 4. Verification

- `pulse_app` builds **without** the SQLite C source (CI `Build (Unix)` /
  `Build (Windows)`).
- SQL tests build **with** the C source: `test_sql` 53/53, `test_migrations`
  21/21.
- Release dry-run `39588855890` is green on three legs with the stock app.
- An app binary importing `xiom.pulse.station.sql` is the SQL build path;
  the existing test binary is the reference.

## 5. Open follow-ups

- Pool / request-scoped connections after the worker scale-out.
- SQL-backed event store (if ever) with an event import path.
- A startup migration-gate helper in the SQL module.
- Blob (BLOB) access in the JSON surface, if needed.
