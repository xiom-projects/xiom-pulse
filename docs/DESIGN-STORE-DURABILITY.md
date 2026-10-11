<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: store durability discipline (bbolt)

Status: DESIGN (2026-10-11, PULSE session). Backlog order 3 of
`docs/PRODUCTION-REFERENCES.md`. Reference: `E:\repos\bbolt`
(etcd-io/bbolt 1.5.0, MIT, light clone). Bus asks: `REL-20261011-0317-pulse-6`
(PULSE fsync), `-pulse-5` (durable flush_stdout), plus the shared runtime
bundle asks from orbitdb (`-1550-orbitdb-3/-4/-7`), packages (`-1550-packages`),
xvector (`-1550-xvector-2/-8`) -- all acked, one implementation.

## 1. Problem statement

PULSE's durability claim today is **torn-tail healing, not power-loss
safety**:

- `src/store.xi`: JSONL append = `io.append_line`, no flush/sync
  (`store_init`, `store_append`); crash safety = newline repair before
  append (`file_ends_with_newline`) + invalid-line skip on read
  (`store_valid_records`). The kv backend (`xiom.kv`) appends via
  `kv_put` with a durable sequence in the key; compaction is
  `kv_compact`.
- Idempotency and sequence live **inside** the record
  (`{"seq":N,"idem":...}`), checked newest-first (`store_find_idem`).
- `src/audit.xi` rotation = remove `.1`, rename active to `.1`, next
  append recreates; appends are unsynced (`server.xi` `audit_event`).
- Backups (`scripts/backup.{ps1,sh}`) copy the store/audit/kv-dir live
  with a sha256 manifest; kv consistency relies on compacting first.
- Sessions are memory-only (out of scope). No `fsync`/`FlushFileBuffers`
  exists in the runtime (grep, 2026-10-05; `docs/STDLIB-WISHLIST-PULSE.md`).

The stdlib runtime bundle (acked) will add the sync primitives; this doc
fixes **where PULSE puts the barriers and what it may then claim**.

## 2. The reference model (bbolt)

bbolt's reputation rests on one ordering rule and its corollaries:

1. **Data before pointer, sync in between.** A commit is: spill dirty
   pages -> write data pages -> `fdatasync` -> write the meta page
   (txid + checksum) -> `fdatasync` (`tx.go:520-592` write, sync at
   `:565-572`; `tx.go:595-625` meta, sync at `:613-619`). A crash before
   the first sync loses the whole tx; a crash between syncs leaves the
   old meta valid; a torn meta is detected by checksum.
2. **Alternating meta pages, newest-valid-wins.** Each commit writes
   `txid % 2` of the two meta pages (`meta.go:42-58`); on open, the
   higher-txid meta wins and a checksum failure falls back to the other
   -- one bad meta page degrades to the previous commit, never
   corruption (`db.go:1141-1162`, open validation `db.go:542-550`).
3. **Monotonic txid/page ids.** txid and high-water mark never decrease;
   freed pages are reused only through the freelist, and only after a
   pending->free transition pinned by open readers (`shared.go:141-158`).
   A freed page is never reused while an older meta (possibly the live
   one after a crash) can still reference it.
4. **NoSync is not a durability mode.** It skips both barriers
   (`tx.go:566`, `:613`); page-cache survivability does not extend to
   machine crash.
5. **Hot backup = reader-pinned streaming snapshot.** `tx.WriteTo`
   freezes the meta at tx start, pins the pages a reader may reference,
   and emits a self-consistent image with freshly written metas
   (`tx.go:391-468`); a raw copy of a live file can catch a new pointer
   with partially copied data and is documented as unsafe.

## 3. Adopted principles for PULSE

### P1. Commit points and sync placement

Define the durability unit per sink, and put the sync *before* the
acknowledgement:

- **Event store (jsonl):** record append is the commit. With the fsync
  wrapper available: append line -> `fsync` -> 2xx. Without it, the
  current healing semantics stay and the docs keep the honest language
  ("crash-safe reopen", never "durable").
- **Event store (kv):** `kv_put` key order mirrors `seq`; treat the kv
  engine's own commit as the barrier only once `xiom.kv` states its
  sync behavior; until then kv durability == jsonl durability (healing),
  and `PULSE_STORE_SYNC` applies to compaction boundaries at minimum.
- **Audit:** security-relevant; sync-before-return for mutating
  requests once available (`PULSE_AUDIT_SYNC`, default on).
- **Compaction / rotation renames:** rename is the publish step; it
  needs `fsync(file)` on the new file *before* the rename and
  `fsync_dir(dir)` after, or a crash can publish a name whose contents
  are not durable. This is a new stdlib ask (`fsync_dir`), filed as an
  interface note.

### P2. One commit marker, checksummed, newest-valid-wins

PULSE has no meta page, but the invariant ports:

- The **seq-inside-record** design already gives monotonicity and
  newest-wins recovery; keep it (kv keys and jsonl scan agree).
- `store_compact` (jsonl: rewrite to `.tmp`, `io.rename`; kv:
  `kv_compact`) is the one place a partial publish is possible. Order:
  write tmp -> sync tmp -> rename -> sync dir. On any failure the tmp is
  removed (existing behavior) and the old file stays the commit.
- Idempotency markers stay in-record (durable with the record); never
  move them to a side table.

### P3. Torn-tail discipline stays

jsonl keeps heal-on-append + skip-invalid-on-read. Document it as
*recovery*, not durability: a power loss may still lose the tail that
was never synced.

### P4. Backup story

Adopt the bbolt stance: a backup must produce a self-consistent image
with its own header, not a best-effort live copy.

- **jsonl:** snapshot = copy under a write pause or accept healing;
  the manifest gains a `fence_seq` (last sequence visible at copy
  start) and `fence_sha256`; the restore runbook verifies
  `GET /api/events/count` >= fence and that seq monotonicity holds.
- **kv:** keep `compact -> copy` as the sanctioned path (already
  documented); after compaction ordering (P1) lands, the snapshot is a
  single synced segment -- record the compact generation in the
  manifest.
- Backups never quiesce; the manifest states which of the two modes ran
  (`live-heal` vs `compacted-fence`).

### P5. What PULSE may claim, when

| Claim | Allowed when |
|---|---|
| "Crash-safe reopen (torn tail healed)" | today |
| "Writes acknowledged only after fsync" | P1 wired + `PULSE_STORE_SYNC=1` |
| "Snapshot is a point-in-time fence" | P4 manifest + restore verification |
| "Power-loss durable (compaction)" | rename ordering + `fsync_dir` shipped |

Docs (`security.md`, `operations.md`, `DEPLOYMENT.md` sections 5/9)
must be updated in the same change that flips each claim.

## 4. Interfaces needed from stdlib (acked bundle)

- `io.fsync(path)` (or a held-handle variant): open -> flush ->
  `FlushFileBuffers`/`fsync`; already covered in substance by
  `REL-20261011-0317-pulse-6` / orbitdb-3 / packages / xvector-2.
- `io.append_line_sync(path, line)` (orbitdb-7) and a held append handle
  (`open_append` + `sync`, orbitdb-4) -- the efficient shape for the
  store's hot path; either is acceptable.
- `fsync_dir(path)` -- **new, this doc**: needed for rename durability
  on compaction/rotation (POSIX `fsync(dirfd)`; Windows: open dir with
  `FILE_FLAG_BACKUP_SEMANTICS` + `FlushFileBuffers`; a documented
  no-op-with-warning is acceptable on platforms where it is a no-op, but
  the semantics must be stated).
- Durable `io.flush_stdout` (`-pulse-5`, xvector-8) -- step-log
  durability for the ops runbooks.

Filed as an interface note to stdlib (this session) referencing this
doc; no new wishlist rows while the bundle is queued.

## 5. Phased plan

**Phase A -- sync points (when the runtime bundle lands):**

1. `store_append`/`store_append_event_keyed`: sync before the 2xx path
   (config `PULSE_STORE_SYNC`, default `1`; `0` documented as
   healing-only).
2. `audit_event`: sync before returning from the mutating path
   (`PULSE_AUDIT_SYNC`, default `1`).
3. `--check-config` prints both; startup warning when disabled.
4. Tests: suite checks for the config surface; crash harness re-run
   (hard-kill x2) asserting the last acknowledged seq survives reopen;
   power-loss itself is not locally testable -- the claim stays
   conditional on the OS contract and is documented as such.

**Phase B -- publish ordering + backup fence:**

1. `store_compact` rename ordering (tmp sync -> rename -> dir sync).
2. Backup manifests gain `fence_seq`/mode; restore verification steps in
   `DEPLOYMENT.md` §9 and `operations.md`.
3. kv: record compact generation; document the compact-then-copy path
   as the only supported live snapshot.

**Phase C -- orbitdb driver interplay (0.3):** the ORBITDB lane's WAL
items (`-1550-orbitdb-3/-4/-7`) share the runtime bundle; the driver
design consumes P1/P2 (commit seam + tail repair) and the process-kill
bar already met by the crash harness.

Every phase: suites x2 + smoke both platforms (pinned stdlib), docs
(including the claim table) + relay updates, signed commit, CI dry run
when the server changes.

## 6. Open questions / risks

- fsync cost per append on Windows (`FlushFileBuffers`); the store is
  low-rate so sync-on-ack is acceptable, but the soak scripts must add a
  latency check before the default flips.
- `xiom.kv` sync semantics are undocumented in the extracted package;
  treat kv as healing-only until the engine states its barrier (kv is
  opt-in, so this does not gate the 0.2.x line).
- Windows `fsync_dir` has no direct equivalent; the stdlib must state
  the platform semantics so the claim table stays honest.
- No local fault injection: power-loss testing stays out of CI; the
  evidence bar is code inspection + OS contracts + kill-test coverage.
- C-PULSE-14 (Linux RSS growth) is orthogonal but the soak additions in
  Phase A must not hide it.

## 7. Source index

- bbolt: `tx.go:170-283` (Commit), `:520-592` (write+sync), `:595-625`
  (meta+sync), `meta.go:42-58` (rotation+checksum), `db.go:1141-1162`
  (newest-valid-wins), `shared.go:141-158` (freelist pinning),
  `tx.go:391-468` (WriteTo snapshot), `db.go:45-55` (NoSync).
- PULSE: `src/store.xi` (seam, healing, compact), `src/audit.xi`
  (rotation), `server.xi` `audit_event`; `scripts/backup.{ps1,sh}`;
  `docs/DEPLOYMENT.md` §5/§9.
- Bus: `REL-20261011-0317-pulse-6`, `-pulse-5`, `-1550-orbitdb-3/-4/-7`,
  `-1550-packages`, `-1550-xvector-2/-8` (all acked).
