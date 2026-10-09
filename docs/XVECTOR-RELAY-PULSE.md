<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE -> XVector lane (relay, 2026-10-09) -- consumer integration handshake

**Owner:** hand this file to the XVector lane. It is a request for ONE
file in your repo that PULSE will read locally (read-only; we never edit
your tree).

## Why now

PULSE (`E:\xiom-projects\xiom-pulse`, the official XIOM web backend) has
XVector as the **vector-index driver** target in its framework roadmap
(`docs/FRAMEWORK-ROADMAP-PULSE.md`, milestone 0.3), alongside OrbitDB
(embedded) and the event store. We consume packages behind stable seams
with **conformance probes** -- "supported" means "probed green on every
shipped OS". Your v0.64.2 re-test wrap is the signal we plan around,
pre-alpha or not: the probe starts minimal and grows with you.

## The ask: create `docs/PULSE-INTEGRATION.md` in your repo

One page, kept current; PULSE re-reads it every wrap. Contents checklist:

1. **Embedding API surface for a consumer today** -- module import path
   and the operations you actually support (open/close, upsert,
   exact/knn search, payload filters, delete), with 2-3 minimal XIOM
   usage snippets, including the vector representation (element type,
   dimension limits).
2. **Build + link contract** -- the `[dependencies]` key + version to
   consume; whether a C ABI / `extern` layer exists (PULSE bindings can
   wrap either); **platform matrix**: linux-x64 / windows-x64 /
   macos-x64 / macos-arm64 status today (our CI builds all four; macOS
   is currently blocked upstream for everyone by stdlib runtime C
   items).
3. **Pin + stability** -- the commit/release we should pin; what is
   guaranteed vs experimental; on-disk layout (index files, WAL) since
   PULSE ships backup/restore for every store it drives.
4. **Consumer-affecting findings** -- open bugs a multi-project consumer
   would hit, with your IDs; lifecycle notes: thread/global state (PULSE
   is single-threaded today), recovery semantics under kill -9, and
   **memory behavior under sustained upsert/search** -- PULSE tracks RSS
   profiles obsessively (see C-PULSE-14) so any known growth pattern
   helps us set expectations.
5. **Conformance test proposal** -- the exact scenarios you want PULSE
   to run as the acceptance gate (e.g., upsert/search round-trip, filter
   combinations, index persistence across reopen, top-k edge cases,
   dimension limits, empty index).
6. **Cross-project asks** -- anything you need from PULSE, and any
   questions for our side.

## What PULSE will do next

- Read `docs/PULSE-INTEGRATION.md` locally, then build a minimal probe
  (`tests/probes/probe_pkg_xvector.xi`) matching your proposal and run
  it in the fleet on both platforms (Linux + Windows first; macOS when
  the toolchain allows).
- File cross-project findings minimally through our relay docs and reuse
  your acceptance scenarios in the 0.3 driver work.
- Driver shape we are planning for your class: `upsert(id, vector,
  payload) / search(top_k, filter) / delete`, capability flags (exact
  vs knn, filtering, persistence) -- tell us where that diverges from
  your actual API and we adapt to yours. A hybrid retrieval example
  (rows in OrbitDB, embeddings in XVector) is the intended showcase,
  so cross-lane consistency with their shapes matters to us.

## Context from our side

PULSE is a JSON/REST backend: the near-term vector use cases are
semantic search over the events API and RAG-style endpoints behind auth.
There is no vector infrastructure in core today -- XVector would be the
first and only one, exactly like `xiom.kv` was for key-value. Keep this
in mind when describing persistence and memory guarantees: predictable
crash/reopen behavior is the property we must not lose.

---

## PULSE response (wrap 14, 2026-10-10) -- handshake ACCEPTED, probe GREEN

`xiom-xvector/docs/PULSE-INTEGRATION.md` received and read; the first
conformance probe is built and green on **both platforms (Linux pinned
stdlib 4dd8844 + Windows lane)**:

- `tests/interop/xvector/probe_pkg_xvector.xi` -- **30/30 PASS, exit 0**
  (source-level composition via `tests/interop/xvector/xiom.toml`,
  `source-roots = ["../../../../xiom-xvector/src"]`, the same pattern as
  the ORBITDB hybrid probe). Scenarios: roundtrip vs the exact Flat
  baseline (k=1/k=5/k=10000), top-k edges (k>live, empty index),
  dimension limits (dim=1 and dim=65536 accepted, dim>65536 rejected,
  query dim mismatch rejected), delete/re-add, duplicate-id overwrite
  (never duplicate hits), reopen integrity (`wal_persist` -> `wal_load`
  -> `engine_recover`), and WAL torn-tail tolerance (cut the last line ->
  prefix recovers, identity intact, >= 99 live points).
- **Trap note for your §5 item 4/5 wording:** raw `search(k=0)` and
  `create_collection(dim=0)` are CONTRACT TRAPS (`requires: k > 0` /
  `requires: dim >= 1`), not Err returns -- a single-process probe
  cannot assert a trap. We assert `dim > 65536 -> Err` instead and keep
  k >= 1 at the driver seam; if you want trap coverage, we will add a
  runner-level negative probe (spawn + expected nonzero exit).
- Scenario 2 (filter combinations) and 9 (hybrid join) are the next
  tranche; the hybrid join already has your ORBITDB-side probe to reuse.

### Answers to your §6 asks

1. **Driver shape probed:** the documented separate calls
   (`upsert(id, vec)` then `set_payload(id, payload)`; `delete_point`),
   not a combined upsert-with-payload. We will adapt if M-Q adds it.
2. **Score semantics:** the driver will expose raw distance and a
   derived `score = 1 - distance` for Cosine (documented per metric);
   tell us if you prefer a different presentation for Dot/Euclidean.
3. **Single-threaded composition confirmed** (PULSE is single-threaded
   today); no process-level snapshot reads needed yet.
4. **Probe scenarios:** implemented list above; we will send additions
   as the 0.3 driver grows.
5. **Volume profile (initial):** events-driven upserts, batch sizes
   100-1000, retention unbounded today; concrete numbers follow the 0.3
   driver design -- we will mirror them in your M-G bench request.
