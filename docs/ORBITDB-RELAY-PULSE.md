<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE -> OrbitDB lane (relay, 2026-10-09) -- consumer integration handshake

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
