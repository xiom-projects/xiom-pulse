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

## 4. Next candidate release -- 0.1.1, all OSs

**Content (all PULSE-side, already on `main` or one unit away):**
1. Rebuild on **v0.64.2** (pins already in CI; Windows memory is flat on
   v0.64.2 -- the user-visible fix for Windows).
2. **Session-store swap retry** (C-PULSE-09 closed): `xiom.session`
   behind the existing HTTP session contract; suites x2 + smoke after.
   **(DONE 2026-10-09: verified both platforms, ships in 0.1.1.)**
3. `PULSE_BIND=addr:port` validation warning + all companion fixes.
4. Portability fixes (lsof wait_listen, gtimeout, shasum) and macOS
   packaging legs.

**Artifact matrix (this is the "all OSs" plan):**

| Artifact | Runner | Status |
|---|---|---|
| `pulse-0.1.1-linux-x64.zip` | ubuntu-latest | ready (dry run green on v0.64.2) |
| `pulse-0.1.1-windows-x64.zip` | windows-latest | ready (dry run green on v0.64.2) |
| `pulse-0.1.1-macos-x64.zip` | macos-15-intel | gated: darwin blockers (see below) |
| `pulse-0.1.1-macos-arm64.zip` | macos-14 | gated: darwin blockers |

**macOS gate (the release decision):** the darwin blockers are filed and
re-confirmed on v0.64.2 -- stdlib runtime C (`_SC_AVPHYS_PAGES`
Linux-only; `fp128_helpers.c` x86 asm on arm64) and the darwin codegen
`llvm.memset` report. If the lanes land them before the cut: set
`RELEASE_BUILD_MACOS=true`, dry-run all four legs green, and 0.1.1 ships
**all four artifacts**. If not: cut 0.1.1 on linux+windows (macOS button
stays "soon"; don't block the release), and carry macOS into 0.1.2.

**Sequence:** swap unit green (both platforms) -> full fleet + dry run
(all four when macOS is un-gated, or two otherwise) -> bump
`src/pulse.xi` to 0.1.1 + `CHANGELOG.md` entry -> tag `pulse-v0.1.1` ->
CI publishes (guard/fleet/packages/provenance) -> ops mirrors at :17 ->
website wires buttons (auto via `latest.json`; macOS only when assets
exist) -> ops redeploys the demo (Linux memory still open: keep
`MemoryMax` + restart; the release does not change the Linux profile).

**Risks:** session-swap regressions (mitigate: suites x2 + smoke before
the cut; keep the local store behind the same contract for rollback);
macOS upstream timing (handled by the gate); store-wipe-after-toolchain
maintenance (verify `xiom doctor` before tagging).

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
