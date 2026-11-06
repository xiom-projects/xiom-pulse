# XIOM PULSE -- roadmap for the website (public-facing)

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Last updated:** 2026-11-02. **Use with:** `docs/STATUS-FOR-WEBSITE.md`
(current status, platform matrix, limitations). This file is the forward
plan; the status brief is the snapshot.

**Planning horizon:** effort-based (grant months), not calendar promises.
"Phase 3" is the next 12 months of focused work; Phase 4 follows it.

---

## 0. The one-paragraph vision

XIOM PULSE is a small, native web application server for teams that want to
own their stack: one hardened HTTP/1.1 core, two tiers (the embeddable
**PULSE Beacon** package and the full **PULSE Station** server), no VM or
interpreter in the serving path, and a supply chain you can verify. The goal
is not to out-feature the large frameworks. It is to be the **production-grade
tier** for self-hosted public-interest services: predictable memory, a
reviewed security surface, reproducible releases, documented operations,
external proof, and a scale-out story that is measured rather than assumed.

## 1. What "production grade tier" means here

A release is **production grade** only when all of these are true, with
evidence:

1. **Memory is flat under sustained load** -- a published 24-hour soak at a
   real rate with a hard RSS ceiling, plus a 72-hour confirmation.
2. **Security is reviewed** -- an independent, scoped review with remediation,
   parser fuzzing, a disclosure policy and a CVE process.
3. **Releases are verifiable** -- SHA-pinned artifacts with provenance, an
   SBOM, and a reproducible-build recipe with documented platform deltas.
4. **Operations are documented** -- operator/migration guides, a scaffold,
   edge-TLS templates, backup and upgrade procedures.
5. **Adoption is external** -- at least one public-interest deployment that is
   not the project's own dogfooding.
6. **Scale-out exists** -- a process supervisor with graceful drain and a
   measured 1/2-worker curve, not just a single-accept loop.

"Top-tier comparable" is a higher bar: the above plus published
cross-framework benchmarks, audit cadence, ecosystem, and years of production
history. The roadmap below separates the two.

## 2. Where we came from (shipped)

### Phase 0 -- protocol core (0.1.x)

- Hardened HTTP/1.1: TE/CL smuggling rules, chunked decoding,
  `Expect: 100-continue`, header/body caps, read/write/idle deadlines,
  keep-alive and pipelining.
- Router + middleware, sessions, CSRF, JWT HS256, CORS, rate limiting,
  metrics, jsonl/kv stores, static/site mode, multipart uploads, SSE and
  WebSocket (handshake, fragmentation, ping/pong, close).
- CLI, config validation, error envelope, request IDs, access/audit logs.

**Exit:** a complete application server, not a demo.

### Phase 1 -- release engineering (0.2.x)

- Multi-platform CI (Linux, Windows, macOS), release packaging, provenance
  attestations, a reproducible dry-run path.
- SQL store/repository layer (opt-in; stock app stays SQL-free), 21
  migrations, transactions, paging.
- Stream authentication (`PULSE_WS_AUTH=off|jwt|session`) with token
  redaction; Origin policy; WS fragmentation.
- Benchmark harness (bttger six-endpoint contract) and the first published
  baseline; the sequential-accept ceiling measured rather than assumed.
- A capability-parity tracker against the reference projects (fasthttp, h11,
  chi for the package class; Gin, Fastify, FastAPI for the framework class).

**Exit:** 0.2.2 deployed and operated; the hard part of the server exists and
is tested.

### Phase 2 -- toolchain consolidation (v0.65.x) -- **current**

- The compiler/stdlib/registry defects that blocked production were found,
  filed, reproduced and fixed upstream: arm64 printf/contract/packed-vec,
  socket ABI, `Vec[Struct]` durability, Int64 extern arg width, parser
  allocation, response-builder allocation.
- Result: **all five platforms** (linux-x64, linux-arm64, windows-x64,
  macOS x64, macOS arm64) build, pass the full fleet, and package.
- The per-request memory floor went **46 KB -> 22.3 -> 16.1 -> 15.5 KB**
  after the router cache and the gate route-match cut; the response builder
  is flat and the read buffer is per-connection. It is **not yet flat under
  soak** -- that is Phase 3.
- Current release: **0.2.2** on compiler **v0.65.6** + stdlib `6fdde4ee`.

**Exit:** the toolchain is no longer the blocker; the remaining gaps are the
server's memory, security assurance, adoption and scale-out.

## 3. Where we are going

### Phase 3 -- PULSE 1.0 (next 12 months of focused work)

Four bounded outcomes plus documentation. This is the production-grade tier.

**WP1 -- memory and sustained-load reliability.**
Upstream reclamation work (maps, strings, JSON values) plus app-path
allocation cuts, and a retention gate in CI.
*Acceptance:* 24 h at 100 req/s on the bttger mix with RSS <= 256 MB,
published with baseline and method; 72 h confirmation; the 1,000,000-request
benchmark unblocked.

**WP2 -- security and release integrity.**
A fixed-scope independent review (parser, auth/session, static/file, release
pipeline) in month 7, with months 8-10 reserved for remediation; parser and
multipart fuzzing; SBOM (CycloneDX/SPDX); SHA-pinned artifacts with
provenance; a reproducible-build recipe; a disclosure policy and a CVE
process.
*Acceptance:* review report + remediation summary, fuzz corpus, SBOM,
reproducible release, published policy.

**WP3 -- external adoption and operational proof.**
One external public-interest pilot (bounded, not a full migration); operator
guide (Docker, systemd, nginx/Caddy edge TLS, backups, upgrades); migration
guide; one-command scaffold; benchmark report (1/2-worker curve, 72 h soak);
final public report.
*Acceptance:* a real deployment with an integration note; the guides and
report published; the internal XIOM sites are **not** counted as adoption.

**WP4 -- scale-out foundation.**
Process supervisor and `--workers N` over SO_REUSEPORT (Linux) / N ports
(Windows); graceful drain; zero-downtime reload; proxy-trust unit; a 1/2-worker
scaling curve; rollback procedure.
*Acceptance:* measured throughput gain across workers, drain/reload proven by
fault injection, templates for systemd and nginx/Caddy.

**WP5 -- project management and dissemination.**
Monthly public notes, issue triage, release coordination, the final report and
one remote community presentation.

**Phase 3 exit (1.0):** the six production-grade conditions in section 1 are
met on all five platforms. Not "top-tier comparable" yet -- no
cross-framework ranking, no audit cadence, no ecosystem.

### Phase 4 -- post-1.0 (top-tier path)

- **Protocol breadth:** native TLS through `xiom.ssl` with certificate reload;
  HTTP/2 and HTTP/3 at the edge; response and WebSocket compression.
- **Scale:** shared-state stateless mode, 4+ workers, richer proxy/load-balancer
  integration.
- **Ecosystem:** OIDC/OAuth, richer SQL drivers, templating/rendering,
  background jobs/queues, caching, distributed tracing, a middleware/plugin
  surface.
- **Assurance:** audit cadence, fuzzing in CI, a public CVE history, an LTS
  line and a contributor guide.
- **Proof:** published cross-framework benchmarks and independent production
  users. Only then is "top-tier comparable" an honest claim.

## 4. Phase map at a glance

| Phase | Theme | Status | Exit criterion |
|---|---|---|---|
| 0 | Protocol core | **shipped** | complete HTTP/1.1 server with auth, stores, streams |
| 1 | Release engineering | **shipped** | 0.2.x fleet, SQL opt-in, benchmark, parity tracker |
| 2 | Toolchain consolidation | **current** | five platforms green and packaged; toolchain no longer the blocker |
| 3 | PULSE 1.0 | planned (12 months) | flat memory, audited security, reproducible releases, external pilot, scale-out |
| 4 | Top-tier path | post-1.0 | TLS/HTTP2/3, ecosystem, audit cadence, cross-framework proof |

## 5. What is already true today (for the site's "now" block)

- **0.2.2** deployed; source MIT OR Apache-2.0.
- **All five platforms** build, pass the full suite and package.
- Test evidence: suites 95/239/4; HTTP smoke 135/135 (jsonl + kv); crash 6/6;
  migrations 21/21; SQL 53/53; streams 83/83 unit + 20/20 live; stream auth
  11/11; rate-limiter smoke; gate order 11/11.
- Benchmark baseline published (bttger six endpoints, single connection):
  1,923 / 421 / 1,670 / 928 / 1,083 / 377 req/s on v0.65.4, zero errors;
  10 connections add no throughput (the scale-out gap Phase 3 fixes).
- Memory: **15.5 KB/request** on 60 s probes after the router cache + gate
  route-match cut (15.2-15.6; 17.6 reference; from 46); not flat yet.
- Supply chain: SHA-pinned toolchain/archives, provenance attestations,
  signed-off release dry-runs.

## 6. What we do **not** claim yet (keep this on the site)

- Not "production grade for sustained high-rate load" until the Phase 3
  memory gate is met.
- Not "top-tier comparable" to Actix/Axum/Gin/Fastify; the parity tracker is
  a measurement, not a ranking.
- No in-process TLS, no HTTP/2, no HTTP/3, no response/WS compression yet.
- No 1,000,000-request benchmark result; the run is blocked by the memory
  gate.
- No external production users yet; the XIOM sites are internal dogfooding.

## 7. Suggested website treatment

- **Roadmap page:** the phase table, then one card per phase with 3-5 bullets
  and the exit criterion; mark Phase 0-1 "shipped", Phase 2 "current", Phase 3
  "next 12 months", Phase 4 "post-1.0".
- **Landing:** "0.2.2" badge, the five-platform matrix from the status brief,
  and one line: "hardening toward a production-grade 1.0: flat memory,
  audited security, reproducible releases, external proof, scale-out."
- **Status page:** the known limitations from `STATUS-FOR-WEBSITE.md`
  (memory floor, edge-only TLS, no HTTP/2, no 1M run) and the current
  benchmark/memory numbers.
- **Do not** put dates on Phase 3 beyond "next 12 months of focused work";
  the plan is effort-based.
- **Internal references stay internal:** relay item IDs and run IDs are for
  the lane, not the public page (use release names and links instead).

## 8. For the website lane

- Source of truth for the plan: this file plus
  `docs/ROADMAP-TOP-TIER.md` section 10 (execution detail) and
  `docs/PARITY-VISION.md` (scorecard).
- Source of truth for the snapshot: `docs/STATUS-FOR-WEBSITE.md`.
- When a phase moves, update the phase table and the "now" block; ping the
  PULSE lane if a claim needs a new number.
- The Restack application is outside the repo and is not edited; this file is
  the public translation of that plan.
