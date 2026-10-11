<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: SQL class migrations discipline (knex)

Status: DESIGN (2026-10-11, PULSE session). Backlog order 4 of
`docs/PRODUCTION-REFERENCES.md`. Reference: `E:\repos\knex` (knex.js
3.3.0, MIT, light clone). Applies to the **future SQL store class** --
PULSE has no SQL backend today; the SQL driver arrives with the packages
lane (vendored sqlite, `REL-20261010-1548-bindings-11` build-hook item).

## 1. What knex fixes (the model to adopt)

- **Two tables**: `knex_migrations` (`id`, `name`, `batch`,
  `migration_time`; `table-creator.js:33-43`) and
  `knex_migrations_lock` (single row, `is_locked`;
  `table-creator.js:45-65`).
- **Pending = files minus applied names**, matched by filename only
  (`Migrator.js:74-78`, `747-751`); all pending run as one **batch**
  with `batch = max(batch)+1` (`Migrator.js:528-538, 621-626`).
- **Ordering = lexicographic filename**, generated as
  `yyyymmddhhmmss_name` in UTC so sort order equals chronology
  (`fs-migrations.js:47-51`, `MigrationGenerator.js:42-47`).
- **Up/down contract**: every migration must export both `up` and
  `down`; strict validation rejects the run otherwise
  (`Migrator.js:506-508, 581-598`).
- **Lock protocol**: conditional `UPDATE ... SET is_locked=1 WHERE
  is_locked=0`; 0 rows affected -> `LockError` and the run aborts with
  a pointer at `migrate:unlock` (`Migrator.js:455-475, 544-555`).
- **Tracking insert rides the migration transaction when the engine
  supports it** (`Migrator.js:663-700`): SQL + insert commit atomically
  on transactional-DDL engines; on MySQL DDL implicitly commits
  (`mysql/transaction.js:12-16`), and with `disableTransactions` the
  insert is a separate commit (`Migrator.js:645, 690-700`).
- **Rollback**: last batch (`WHERE batch = (SELECT max(batch))`), in
  reverse insert order, deleting rows after each `down`
  (`Migrator.js:186-196, 602-618, 701-706`).

## 2. Known knex weaknesses -> PULSE corrections

| knex behavior | PULSE discipline |
|---|---|
| No stale-lock timeout; a crashed run leaves `is_locked=1` and every later run fails until the destructive `migrate:unlock` wipes the table (`Migrator.js:426-442`) | Lock row carries `owner` (host + pid), `locked_at`, `heartbeat_at`. `pulse migrate` refuses a live lock (heartbeat fresh) and **auto-breaks only a stale lock** (heartbeat older than `--stale-lock-secs`, default 900; prints what it did). `--break-lock` forces with a loud warning. |
| First-run DDL is unprotected and racy: check-then-create tables + check-then-seed the lock row, before any lock is held (`table-creator.js:8-31, 55-65`); duplicate lock rows are fatal | DDL uses `CREATE TABLE IF NOT EXISTS` + `INSERT ... ON CONFLICT DO NOTHING`, and the lock row is upserted by primary key -- safe under concurrent first runs. `pulse migrate status` heals duplicate rows to one. |
| Applied names matched by filename only; a deleted-but-applied file aborts unless validation is disabled (`Migrator.js:68-70, 727-739`) | Strict by default: applied-but-missing file = hard error naming the file. `--allow-missing-applied` is explicit and prints the skipped set (audit trail). |
| SQLite DDL-in-transaction caveats (`sqlite-transaction.js:37-81`, docs `migrations.md:311-337`) | Migrations declare `-- no-transaction` in their header when the engine cannot run the DDL transactionally; the runner then pre-checks and post-verifies and records the row immediately after (never mixing). MySQL-class implicit commits are handled the same way and documented. |
| `rollback` never uses a wrapping transaction (`Migrator.js:199, 244`) | Rollback uses the same per-migration transaction rule as up; the lock is held across the whole rollback batch. |

## 3. PULSE runner contract

- **Explicit CLI step, never at startup.** The server process never
  auto-migrates; migrations run from the binary as
  `pulse_app migrate status|up|down|create|break-lock`, reusing the
  existing CLI subcommand shape (`server.xi` main: `routes`, `openapi`,
  `version`, `check-config`).
- **Files**: `migrations/YYYYMMDDHHMMSS_name.sql` (lexicographic
  ordering; UTC stamps), each with a header comment declaring
  `-- pulse: no-transaction` when needed. `create` renders the stub with
  both directions.
- **Connection**: `PULSE_SQL_DSN` (config surface like the rest of the
  env table + `sql_dsn` JSON key). `--check-config` prints the DSN with
  the password redacted.
- **Exit codes**: 0 = applied/no-op; 1 = error; `status` exits 0 with a
  table of applied/pending when current, 1 when pending (CI gate
  friendly).
- **Status output**: one line per migration (`applied batch=N time=...`
  / `pending`), the current version, and the lock state (owner,
  heartbeat).
- **Backup fence first**: `migrate up` refuses to run unless the last
  backup manifest covers the current store state **or**
  `--no-backup-check` is passed -- migrations are the one schema-level
  destructive operation, so the durability story
  (`docs/DESIGN-STORE-DURABILITY.md` P4) gates them.
- **Engine support matrix** (first targets): sqlite (vendored, via the
  bindings build hook) -> postgres-class -> mysql-class. The runner
  treats transactional DDL as a declared engine capability, not a
  guess.

## 4. Test plan (when a driver exists)

- Ordering: pending set = files minus applied; batch increment;
  rollback reverses the last batch only.
- Locking: second concurrent runner aborts cleanly; stale lock
  auto-breaks with a message; `--break-lock` forces; duplicate lock
  rows are healed by `status`.
- Atomicity: on a transactional-DDL engine, a failing migration leaves
  neither schema change nor tracking row; on a no-transaction engine,
  the failure output names the half-applied file and the runner leaves
  the lock released and the row absent (operator re-run path
  documented).
- First-run race: two runners against an empty database -- one wins,
  the other learns the lock is live; no duplicate rows.
- Validation: applied-but-missing file errors; `--allow-missing-applied`
  lists what it skipped.
- Backup gate: `migrate up` refuses without a covering fence unless
  forced.

## 5. Non-goals / open questions

- No auto-migration hooks in the serving binary; embedding migrations in
  the store seam stays out of scope.
- Schema introspection/diffing (knex `schema` DSL equivalents) is not
  part of this unit; migrations are explicit SQL/text.
- The sqlite driver package shape (stdlib `xiom.sql` vs a package) is
  the packages lane's call; this runner consumes it either way.
- CI coverage of postgres/mysql classes needs runner images; deferred
  until the second engine target exists.

## 6. Source index

- knex: `lib/migrations/migrate/Migrator.js` (`:59-99` latest,
  `:455-482` lock, `:528-572` batch/lock scope, `:602-618` rollback
  selection, `:644-707` waterfall + tracking),
  `lib/migrations/migrate/table-creator.js:8-65`,
  `lib/migrations/migrate/migration-list-resolver.js:11-27`,
  `lib/migrations/migrate/sources/fs-migrations.js:24-70`,
  `lib/migrations/migrate/MigrationGenerator.js:42-54`,
  `lib/migrations/migrate/migrator-configuration-merger.js:6-15`,
  `docs/src/guide/migrations.md:15-25, 285-337, 400-406`.
- PULSE: `src/server.xi` main CLI block; `docs/DESIGN-STORE-DURABILITY.md`
  (P4 fence); `REL-20261010-1548-bindings-11` (vendored-C sqlite hook).
