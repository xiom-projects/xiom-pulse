<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- framework roadmap (production-grade, all OSs)

Owner request (2026-10-09): plan PULSE as a well-rounded, fully
production-grade web framework that showcases what XIOM can do, with
security, integrations and a full CLI -- comparable to modern backend
frameworks -- and use it to fully test and harden the whole XIOM
ecosystem (packages -> bindings -> stdlib -> compiler). This document is
the target contract; milestones are cut as releases only when their
gates are green.

## 1. Strategy: the framework is the ecosystem's hardest consumer

PULSE's hardening value comes from being a real application on top of
every lane. Each roadmap item below therefore names the **upstream asks**
it creates; every integration ships with a **conformance probe** in the
PULSE fleet, so "supported" always means "probed green on both/all
platforms". Findings flow back through the three relay docs
(`COMPILER-FINDINGS-PULSE.md`, `STDLIB-WISHLIST-PULSE.md`,
`PACKAGE-WISHLIST-PULSE.md`) with minimal repros and acceptance gates.

## 2. Capability map (target: production grade)

| Area | Today (0.1.x) | Target | Upstream asks |
|---|---|---|---|
| HTTP lifecycle | close-per-request, no recv timeouts, single-thread | keep-alive, recv/header deadlines, chunked responses, gzip, worker threads, SIGTERM drain, backpressure | stdlib (timeouts, signals), runtime (threads), C-PULSE-16 bind |
| API contract | stable JSON envelope, `?limit/kind`, HEAD/OPTIONS | OpenAPI 3 export, RFC 9457 problem+json, pagination + Link, idempotency keys, versioning, conditional GET | none (PULSE-side) |
| AuthN/Z | demo login, sessions+CSRF, JWT HS256 | users/RBAC/permissions, API keys, PATs, OIDC/OAuth2 client, scopes, per-identity limits | packages (OIDC via HTTP client) |
| Data | JSONL default, kv opt-in, event API | driver seam: event store (have), relational/embedded (**OrbitDB**), vector (**XVector**), SQL via bindings; migrations | packages (orbitdb, xvector, sqlite/libpq bindings) |
| Integrations | none outbound | HTTP client (SSRF-guarded), payments (Stripe first), email (provider/SMTP client), outbound webhooks, object storage | packages (http client, crypto/KMS), bindings (S3), lane lanes |
| Realtime | none | multipart uploads, SSE, WebSockets | stdlib (streaming sockets), runtime (threads) |
| CLI/DevEx | `--version`, `--help`, `--check-config` | subcommands: `openapi`, `routes`, `migrate`, `new` (scaffold), `worker`; test client; SDK generation | none (PULSE-side) |
| Security | caps, smuggling guard, CSRF, CORS list, headers, audit, rate limit | SBOM per release, parser fuzzing, SSRF/webhook guards, secrets hygiene, disclosure/CVE process, security.txt | CI (SBOM tooling) |
| Ops | metrics/logs/audit, Dockerfile, systemd, backup, provenance | dashboards, readiness/liveness split, zero-downtime restarts (drain), incident runbooks | stdlib (signals) |
| Realtime-ish | -- | kv-backed jobs/queue, scheduled tasks | none (kv driver + PULSE) |

Definition of done for "production grade" (1.0): every P0 upstream item
landed (timeouts, keep-alive, drain, threads, bind enforcement, Linux
memory profile), security review + fuzz pass, SBOM + provenance on all
artifacts, stable public API contract (OpenAPI committed), performance
numbers published, and the demo running the same build.

## 3. Milestones

### 0.1.1 -- "clean platform" (next candidate; see section 4)

### 0.2 -- framework foundations (PULSE-side, mostly unblocked)
- Driver seam formalized as a versioned package contract
  (`xiom.pulse.driver` naming agreed with the packages lane).
- **Auth core**: users/roles/permissions store, API keys, per-identity
  rate keys; OIDC prepared (package in 0.4).
- **API contract**: OpenAPI 3 export + `pulse openapi` + `pulse routes`;
  problem+json error bodies; pagination + idempotency conventions;
  `/v1` prefix on new surfaces.
- **Uploads**: multipart parsing PULSE-side (caps already exist).
- **HTTP client package** (SSRF-guarded) as the base for all outbound.
  **(2026-10-09: base SERVED -- `xiom.http` 0.1.4 ships the
  real-libcurl GET/POST client; PULSE bumps to it in 0.2 and adds the
  SSRF guard + convenience wrappers.)**
- `pulse new` scaffold proving the DX story.
- Gates: suites/smoke extended per feature; driver-seam probe; fleet
  green on all shipped OSs; upstream asks listed per feature.

### 0.3 -- data drivers
- **OrbitDB driver** (embedded default candidate; B-tree/WAL/query
  engine): conformance probe + soak + crash/reopen.
- **XVector driver** (vector index): upsert/search/filter probe; a
  hybrid retrieval example (events + embeddings).
- **SQL class** via bindings (sqlite first, then libpq); migrations.
  **(2026-10-09: bindings SERVED -- `xiom.sqlite` 0.2.0, `xiom.libpq`
  0.2.0, `xiom.odbc` 0.2.0 published+signed; sqlite waits on the
  `--c-source` build-hook story for registry consumers; libpq/odbc are
  dynamic-loader.)**
- Gates: driver conformance probes, 1h soak per driver, backup/restore
  round-trips.

### 0.4 -- integrations
- Payments package (Stripe first: intents, webhooks, idempotency),
  email package (provider + SMTP client), outbound webhooks,
  OIDC/OAuth2 client, kv-backed jobs/queue + scheduler.
- Gates: per-integration probes (sandbox/test modes), webhook signature
  tests, retry/queue soak.

### 1.0 -- production grade
- P0 upstream all landed; security review + parser fuzz pass; SBOM +
  provenance on every artifact; published benchmarks; OpenAPI frozen;
  multi-tenancy groundwork; SSE/WS as post-1.0.

## 4. Next candidate release -- 0.2.0, all OSs (macOS included)

**Owner direction (2026-10-09): the next cut must matter -- macOS x64 +
arm64 artifacts and real gap coverage, not another maintenance release.**
0.1.2 is the current shipped release (session swap on v0.64.2); the
`pulse-v0.1.1` tag exists but was never released (immutable-tag
version-literal gate; documented in the changelog).

**macOS gate (critical path, all upstream -- fix sketches filed):**
1. stdlib `runtime/xiom_runtime.c:4222` -- `_SC_AVPHYS_PAGES` is
   Linux-only (guard + Apple fallback).
2. stdlib `runtime/fp128_helpers.c` -- x86 asm compiled on arm64 (arch
   guard + portable/aarch64 fallback).
3. compiler codegen -- the typed `@llvm.memset.p0i8.i64` emission
   (`xiom-codegen` emitter.rs:859, expr.rs:3774, stmt.rs:713/1131)
   breaks LLVM 15+ IR verification; emit the declaration or the untyped
   form.
When a compiler/stdlib pairing carries all three: set
`RELEASE_BUILD_MACOS=true`, dry-run all four legs green, and 0.2.0 ships
`pulse-0.2.0-{linux-x64,windows-x64,macos-x64,macos-arm64}.zip`.

**PULSE-side content for 0.2.0 (the "matters" slate, in order):**
1. **API contract**: OpenAPI 3 document served at `/openapi.json` +
   `pulse openapi` export; additive problem+json fields on the error
   envelope; pagination `Link` headers; idempotency keys on event
   writes; `/v1` prefix on new surfaces. **(DONE 2026-10-09/10: OpenAPI
   served + CLI export + additive error `status`; pagination Link
   (seq-in-record cursor); idempotency keys; `/v1` alias.)**
2. **CLI**: subcommands `openapi`, `routes`, `version`,
   `check-config` (promoting the current flags). **(All four DONE
   2026-10-09.)**
3. **HTTP client base**: bump `xiom.http` to 0.1.4, add the
   SSRF-guarded outbound wrapper + probe (foundation for all
   integrations). **(DONE 2026-10-10: pin bumped; `xiom.pulse.outbound`
   guard + `probe_outbound_guard` in the fleet; the libcurl transport
   seam (`src/outbound_transport.xi`) adopts once the package
   `--c-source` build hook is ergonomic.)**
4. **Multipart uploads** (PULSE-side parsing + caps).
5. Docs/public-set refresh; version-bump checklist run (SESSION
   gotchas) with the pinned stdlib before tagging.

**Carried, upstream-gated (not release blockers unless they land):**
keep-alive, recv timeouts, SIGTERM drain, threads (stdlib/runtime);
BIND enforcement (C-PULSE-16); Linux memory (C-PULSE-14). If any land
before the cut, they join the release notes.

**Sequence:** execute the PULSE-side slate (suites x2 + smoke + probes
per feature) -> darwin fixes land -> dry-run all four legs green ->
bump to 0.2.0 + CHANGELOG -> tag `pulse-v0.2.0` -> CI publishes ->
ops mirrors (:17) -> website lights the macOS button and the refresh.

**Risks:** darwin timing (macOS is a headline deliverable this time --
escalate through the relay docs if the lane queue slips); feature scope
(keep each item additive; full suites after each); toolchain
maintenance wiping the store (check `xiom doctor` before tagging).

## 5. Cross-lane asks index (framework-driven)

- **Compiler/runtime**: recv timeouts, keep-alive, SIGTERM drain,
  threads/backpressure, address-aware bind (C-PULSE-16), Linux memory
  profile (C-PULSE-14), darwin codegen, enum/alias items as filed.
- **Stdlib**: socket deadlines + reuse-addr, `TcpStream` streaming,
  signal handler API, `io.flush_stdout`, reusable socket buffers,
  /proc-safe file reads, darwin runtime C fixes.
- **Packages**: `xiom.http` client half, crypto/KMS helpers, OIDC,
  orbitdb, xvector, queue/cache conveniences, `xiom.pulse.driver`
  contract package.
- **Bindings**: sqlite, libpq, S3/object storage, email transports.

## 6. Non-goals / anti-patterns

- No universal "connect anything" ORM: three storage interface classes,
  explicit drivers, capability flags.
- No SMTP server in-process; email is an outbound client.
- GraphQL and WebSockets: post-1.0, as packages, after concurrency.
- Core stays small: integrations are packages; the API contract and
  driver seam live in core because every app needs them.
- No integration without a conformance probe; no release without the
  fleet green on every shipped OS.
