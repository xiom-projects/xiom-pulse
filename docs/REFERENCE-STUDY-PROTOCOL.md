<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Reference-Study Protocol (owner directive 2026-10-17)

**Status: STANDING RULE -- must not diverge.**

We do not design from memory and we do not reinvent solved wheels. The
cloned, battle-tested MIT projects under `E:\repos` are our design
source. Every unit converts their mechanics into XIOM before we write
our own.

## The method (per unit)

1. **Pick the references.** From `docs/PRODUCTION-REFERENCES.md` (the
   shelf catalog) select the repos that solve this exact problem --
   middleware -> gin/fastify; SQL migrations -> knex; jobs -> bullmq;
   durability -> bbolt; protocol state -> h11; routing -> chi;
   DI/OpenAPI -> fastapi; JWT -> jose; headers -> helmet; benchmarks ->
   `web-framework-benchmarks` / `-xlcaptain`.
2. **Crawl, don't skim.** Read the actual files and functions that
   implement the mechanic. Extract a compact matrix into the unit's
   design doc: `reference file:function -> mechanism -> what PULSE
   needs -> what XIOM needs`. The existing `docs/DESIGN-*.md` files are
   shaped this way -- keep extending them; the matrix is the lane's
   memory.
3. **Convert, don't copy.** Map the mechanism onto XIOM idioms
   (Vec-bracket literals, initialization discipline, typed errors,
   pinned toolchain). Port decisions and edge cases, never code.
4. **Apply from the matrix.** Implementation cites the extracted
   mechanism. If the answer is not in the matrix, go back to the
   reference files -- do not invent an answer.
5. **Blockers go upstream immediately.** If the mechanic needs a runtime
   primitive (stdlib wishlist), a registry package feature (packages
   wishlist), or hits a compiler bug (BUG item): file it on the relay
   with the extracted evidence + a minimal repro, take the documented
   fallback meanwhile, and **test back when the next release / package
   publish lands**. No silent workarounds that drift from the reference.
6. **Production bar, not MVP.** The goal is a #1-class production
   framework. Every adopted mechanic carries its tests and failure paths
   (caps, timeouts, crash/restart, soak) and the docs' claim language
   stays honest.

## Standing references

`docs/PRODUCTION-REFERENCES.md` is the MIT-verified shelf (h11, bbolt,
gin, fasthttp, fastify, fastapi, chi, jose, helmet, knex, bullmq) plus
the benchmark suites and language/tooling references shared across
lanes under `E:\repos` -- never edit those checkouts.

## Plan coupling

Every item in the SESSION.md queue names its reference(s) and the design
doc holding the extracted matrix. A unit that cannot name its
references has not started yet.
