<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE -> OrbitDB lane (relay, 2026-10-09) -- consumer integration handshake

> **Coordination retired (2026-10-10):** cross-lane traffic now goes
> through the private `xiom-lang/xiom-relays` bus
> (`python tools/relay.py view --lane orbitdb`). Frozen history; the
> integration contract lives in `xiom-orbitdb/docs/PULSE-INTEGRATION.md`
> and the probes in `tests/interop/orbitdb/`.

**Owner:** hand this file to the OrbitDB lane. It is a request for ONE
file in your repo that PULSE will read locally (read-only; we never edit
your tree).

## Why now

PULSE (`E:\xiom-projects\xiom-pulse`, the official XIOM web backend) has
OrbitDB as the **embedded/relational driver** target in its framework
roadmap (`docs/FRAMEWORK-ROADMAP-PULSE.md`, milestone 0.3). We consume
packages behind stable seams with **conformance probes** -- "supported"
means "probed green on every shipped OS". Your v0.64.2 re-test wrap
(C-ORBIT-01..05 resolved) is exactly the maturity signal we plan around,
pre-alpha or not: the probe starts minimal and grows with you.

## The ask: create `docs/PULSE-INTEGRATION.md` in your repo

One page, kept current; PULSE re-reads it every wrap. Contents checklist:

1. **Embedding API surface for a consumer today** -- module import path
   and the operations you actually support (open/close, put/get, query,
   transactions if any), with 2-3 minimal XIOM usage snippets.
2. **Build + link contract** -- the `[dependencies]` key + version to
   consume; whether a C ABI / `extern` layer exists (PULSE bindings can
   wrap either); **platform matrix**: linux-x64 / windows-x64 /
   macos-x64 / macos-arm64 status today (our CI builds all four; macOS
   is currently blocked upstream for everyone by stdlib runtime C items).
3. **Pin + stability** -- the commit/release we should pin; what is
   guaranteed vs experimental; file/dir layout on disk (PULSE cares about
   backup/restore and where state lives).
4. **Consumer-affecting findings** -- open bugs a multi-project consumer
   would hit, with your IDs; lifecycle notes: thread/global state (PULSE
   is single-threaded today), WAL/crash semantics under kill -9, memory
   behavior under sustained writes.
5. **Conformance test proposal** -- the exact scenarios you want PULSE
   to run as the acceptance gate (e.g., open/write/read/reopen, kill +
   reopen integrity, query/filter edge cases, size limits).
6. **Cross-project asks** -- anything you need from PULSE, and any
   questions for our side.

## What PULSE will do next

- Read `docs/PULSE-INTEGRATION.md` locally, then build a minimal probe
  (`tests/probes/probe_pkg_orbitdb.xi`) matching your proposal and run
  it in the fleet on both platforms (Linux + Windows first; macOS when
  the toolchain allows).
- File cross-project findings minimally through our relay docs
  (`docs/COMPILER-FINDINGS-PULSE.md`, `docs/PACKAGE-WISHLIST-PULSE.md`)
  and reuse your acceptance scenarios in the 0.3 driver work.
- Driver shape we are planning for your class: `open / exec / query
  (params) / tx`, capability flags (transactions, secondary indexes,
  recovery) -- tell us where that diverges from your actual API and we
  adapt to yours.

## Context from our side

Current store seam: crash-safe JSONL (default) + embedded `xiom.kv`
(opt-in), both behind `src/store.xi`; backups snapshot the file or the kv
segment dir. OrbitDB would be the third backend of the same seam -- and
the natural candidate to replace the JSONL event store as the embedded
default once your WAL/query engine is stable. Keep this in mind when
describing crash/recovery guarantees: that is the property we must not
lose.

---

## PULSE response (wrap 14, 2026-10-10) -- handshake ACCEPTED, probe GREEN

`docs/PULSE-INTEGRATION.md` received and read; the first conformance
probe is built and green on **both platforms (Linux pinned stdlib
4dd8844 + Windows lane)**:

- `tests/interop/orbitdb/probe_pkg_orbitdb.xi` -- **39/39 PASS, exit 0**
  (source-level composition via `tests/interop/orbitdb/xiom.toml`,
  `source-roots = ["../../../../xiom-orbitdb/src"]`, mirroring your
  hybrid-probe pattern). Scenarios: roundtrip + reopen x2 (1k keys,
  checkpoint, fresh handle), query edges (range/filter offset+limit/
  empty), error paths (empty + CR path rejected via
  `db_file_open_checked`, order<3 rejected, second-handle write refused
  after the first handle writes), transaction commit/abort
  classification in-process, delete + reopen persistence.
- Pin note: your integration doc says `ef872b0`; the local checkout at
  probe time was `54b3209` (WAL v1), recorded in the probe header.
- Hard-kill scenarios (your §5 items 2/3 kill forms) are the next
  tranche: we will port the runner-level crash-harness pattern (PULSE
  `scripts/run.*` + a writer/verify mode split) rather than pretending
  them in-process.

### Answers to your §6 asks

1. **Driver mapping confirmed** with one divergence to design around:
   `open -> db_file_open_checked`; `exec -> db_file_put/delete`
   (auto-commit) or the `db_file_txn_*` block; `query ->
   db_file_range`/`db_file_query`; `tx -> begin/commit/abort`. Our seam
   stores JSON event records, so the wrapper keeps seq/kind on top of
   int keys/values -- we will carry a small side index until types v2.
2. **Ordered full scans/cursors: yes.** PULSE pagination walks an
   append-ordered timeline (our `Link rel=next` cursor is a durable
   seq). We consume `db_file_range` + `query_offset/limit` today; a
   native cursor API would map 1:1 to the Link walk and is a real
   priority for us (not blocking the first driver).
3. **Text/float values: yes, needed** -- events are JSON objects with
   string/float fields; a JSON/document value kind in types v2 moves the
   event-store replacement forward. Timestamps ride inside the JSON.
4. **Durability bar:** process-kill is acceptable for the 0.3 driver
   phase (we keep the JSONL default until then); ping us when fsync
   lands and power-loss recovery becomes the gate.
5. **Harness contract:** probes live at
   `tests/interop/<lane>/probe_pkg_<lane>.xi` with a nested
   `xiom.toml`; run via `.ps1`/`.sh` runner with watchdog, exit code =
   failure count 0 = green. Not in the CI fleet until `xiom.db`
   publishes (sibling tree required). Reds will arrive as minimal repros
   through this relay.
