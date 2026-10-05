<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- Progress Tracker

**Last updated:** 2026-10-05 (PULSE session, v0.64.0 wave)
**Purpose:** one page the owner can read to see what a full
production-grade XIOM web backend consists of, what already works, and
what is still missing. Updated by the PULSE session at every step wrap.

**How to read the score:** each area has a weight (share of a
production-grade framework) and a completion %. The overall score is the
weighted sum. Scores are intentionally strict: "works in the soak" counts
only with evidence attached, and an area is not 100% until it survives
load, failure, and restart, not just the happy path.

---

## 1. Overall score: **~37% of production grade**

| # | Area | Weight | Done | Weighted | Status |
|---|---|---:|---:|---:|---|
| 1 | HTTP core (parse/build/limits) | 12% | 60% | 7.2 | working, edge cases + limits missing |
| 2 | Routing | 8% | 50% | 4.0 | exact + 1 param; no query/wildcards/groups |
| 3 | Middleware framework | 8% | 10% | 0.8 | logging/audit inline only |
| 4 | Configuration | 5% | 60% | 3.0 | env-based; no file/validation |
| 5 | Observability (log/metrics/audit) | 8% | 55% | 4.4 | JSON log + counters + audit; no latency histograms; flush no-op |
| 6 | AuthN/AuthZ | 10% | 35% | 3.5 | sessions + JWT HS256; no credentials, RBAC, rotation |
| 7 | Storage | 10% | 35% | 3.5 | JSONL store + crash-safe append; no query/update/compaction |
| 8 | Security hardening | 12% | 15% | 1.8 | no TLS/rate-limit/CORS/CSRF/validation; TLS via proxy by design |
| 9 | Static / assets | 4% | 20% | 0.8 | favicon + landing only |
| 10 | Protocol extras (SSE/WS/REST/GraphQL/templates) | 8% | 0% | 0.0 | none started |
| 11 | Reliability & concurrency | 10% | 45% | 4.5 | 1h soak 13,198/13,198, flat memory; single-thread, no timeouts, no signals |
| 12 | Testing / CI / release | 5% | 60% | 3.0 | suites+smoke+soak+WSL locally; no CI, no packaging |
| | **Total** | **100%** | | **36.5** | |

Two lenses to keep separate:

- **PULSE's own work:** ~55% of the Step 0-4 plan (Steps 0-3 core done,
  Step 4 TLS decision pending).
- **Production-grade framework:** **~37%**. The gap is mostly *hardening*
  and *ecosystem maturity*, not basic function.

---

## 2. What works today (evidence-backed)

Run `out\pulse_app_v4.exe` and these work end-to-end (smoke 44/44):

| Method | Path | What it does |
|---|---|---|
| GET | `/health` | liveness JSON |
| GET | `/api/version` | name + version |
| POST | `/api/echo` | echoes request JSON (400 on invalid) |
| GET | `/api/items/:id` | path-parameter demo |
| POST | `/api/session/login` | creates session, `Set-Cookie: sid` (HttpOnly, SameSite=Lax) |
| GET | `/api/me` | session lookup (401 without/expired) |
| POST | `/api/session/logout` | drops session, clears cookie |
| POST | `/api/token` | issues JWT HS256 (registry `xiom.jwt` 0.2.0) |
| POST | `/api/token/verify` | verifies signature + `exp`, returns payload |
| POST | `/api/events` | appends JSONL event (crash-safe) |
| GET | `/api/events` | last 10 events + count |
| GET | `/api/events/count` | event count |
| GET | `/metrics` | Prometheus text counters |
| GET | `/favicon.ico` | official app icon (270,398 bytes, chunked send) |
| GET | `/` | landing page linking the icon |

Cross-cutting, working: router with 404/405+`Allow`, uniform error
envelope, env config, JSON access log with request ids, audit trail,
structured metrics, cookie sessions, JWT, crash-safe JSONL store, binary
responses, request body framing, graceful test shutdown (`X-Pulse-Quit`).

**Load evidence:** 1h soak: PS driver 7,070/7,070 + WSL client 6,128, server
served **13,198/13,198** requests, 0 errors, clean shutdown, working set
+48 KB, handles 113 -> 113. 64 simultaneous connections served, 64/64.

**Module inventory** (`src/`, all green in `tests/test_app.xi` x2):

| Module | Lines (rough) | Purpose |
|---|---:|---|
| `server.xi` | ~330 | accept loop, dispatch, send_all, log/audit wiring |
| `http.xi` | ~250 | request parse, response build (text/json/bytes) |
| `store.xi` | ~120 | JSONL append store, torn-line healing |
| `router.xi` | ~120 | route table, params, 404/405 |
| `session.xi` | ~100 | in-memory sessions, cookie bindings |
| `config.xi` | ~80 | env config with defaults |
| `metrics.xi` | ~70 | counters, Prometheus render |
| `envelope.xi` | ~40 | error envelope |
| `pulse.xi` | ~15 | version |

---

## 3. What is missing, area by area (the honest list)

**HTTP core (60%)**
- No `keep-alive` (always `Connection: close`) -- the biggest perf item.
- No chunked transfer-encoding (request or response).
- Query strings are not split: `/api/items/1?x=1` currently 404s.
- No header/request-line size caps (body cap 1 MB only) -- DoS surface.
- No `HEAD` handling, no `Expect: 100-continue`, no URL-decoding.
- Status is far from 100% even if all of the above land: response
  streaming, compression, HTTP/2 (proxy's job).

**Routing (50%)**
- Multiple params (`/a/:x/b/:y`), wildcards, optional segments.
- Query-string parsing, route groups, per-route middleware hooks.
- `xiom.router` 0.1.0 is incubating in the packages lane -- likely
  replaces this module once published.

**Middleware (10%)**
- Request-id/logging/audit are hardcoded in the loop.
- No composable chain, no recover-to-500, no CORS/CSRF helpers.

**Config (60%)**
- Env only; no config file, no schema validation, no startup warnings for
  missing production values (e.g. dev JWT secret).

**Observability (55%)**
- Counters only; no latency histograms/summaries, no per-route breakdown.
- `io.flush_stdout()` is an empty body in the current stdlib -> logs can
  lag until process exit (stdlib wave queued).

**AuthN/AuthZ (35%)**
- Login trusts any username (no credential store/verification).
- Sessions are memory-only (lost on restart), no rotation on login.
- JWT: HS256 only, single static secret (dev default), no key rotation,
  no scopes/roles, no refresh tokens.
- No RBAC/authorization layer at all.

**Storage (35%)**
- Append + read last N + count. No update/delete/query/filtering.
- No migrations framework (only a schema marker), no compaction, no
  backup/restore, no indexes (fine at small scale).
- `xiom.kv` is the proposed packages-lane replacement.

**Security hardening (15%)**
- TLS: front-proxy by design (Caddy/nginx), not implemented here; no
  TLS tests yet.
- No rate limiting (`xiom.rate` 0.2.0 exists, not wired).
- No CORS, CSRF, security headers (HSTS/CSP/frame-options).
- Input validation is minimal (JSON object check only) -- no schema.
- No slow-client timeouts (stdlib queued); half-open request can hold the
  single-threaded loop.

**Static/assets (20%)**
- Favicon + landing page only; no directory serving, MIME map,
  ETag/Range/Cache-Control.

**Protocol extras (0%)**
- Templates, SSE, WebSocket, REST helpers, GraphQL: not started.
  Registry has `xiom.websocket`/`xiom.realtime`; GraphQL stays behind an
  interface (compiler-gated item).

**Reliability & concurrency (45%)**
- Single-threaded sequential accept (pin has no threads/select); 64
  concurrent works only because requests are short and queued by the OS.
- No transport timeouts; one stalled client blocks everyone.
- No signal handling / graceful in-flight drain (test-only QUIT).
- A trap anywhere kills the process (no supervisor/restart policy).

**Testing/CI/release (60%)**
- Local: 3 suites, smoke (44), crash/reopen (6), soak drivers (PS+WSL),
  15+ probes, byte-level lint greps. All manual/watchdog-run.
- No CI pipeline, no coverage number, no fuzzing, no packaging/release
  process, DCO-only workflow.

---

## 4. Ecosystem blockers affecting PULSE (not PULSE's own code)

| Blocker | State on v0.64.0 | PULSE impact |
|---|---|---|
| C-PULSE-04 bare `&mut Int` read -> address | OPEN | keeps `*p` discipline; blocks cursor-style parsing in lane code |
| C-PULSE-05 const-receiver `.to_str()` W005 -> abort | OPEN (worse: 0x80000003) | `convert.int_to_string` workaround stays |
| C-PULSE-06 missing struct field -> garbage | OPEN | every struct literal must list all fields |
| C-PULSE-02 deps not mapped to catalog roots | OPEN | `xiom.toml source-roots` wiring per package |
| No exe icon embedding | feature gap | icon served at `/favicon.ico` for now |
| stdlib deadlines/timeouts, write_all, request parser, real flush | queued wave | slow-client guard, streaming, HTTP parse duplication, log lag |
| `xiom.router`/`session`/`static`/`http.middleware` | incubating; publish gated on allowlist delta | module replacement + middleware framework |
| Concurrency primitives (threads/select) | absent on the pin | caps throughput; single-threaded design |

Resolved on v0.64.0: C-PULSE-01, runtime-link (R65), crypto-link (m195).

---

## 5. Milestones (what "done" means next)

| Milestone | Criteria | State |
|---|---|---|
| **M1 -- Thin slice** | plaintext HTTP/1.1, routes, JSON, 404/405, curl + 64 concurrent + soak | **DONE** (2026-10-05) |
| **M2 -- App skeleton** | router, envelope, config, log, metrics, audit, sessions, JWT | **DONE** (core; hardening items above) |
| **M3 -- Storage** | durable store, schema, crash/reopen, soak | **DONE core** (JSONL; query/migrations pending) |
| **M4 -- Hardening** | timeouts, limits, keep-alive, rate limit, CORS/CSRF, validation, graceful shutdown, latency metrics | ~15% |
| **M5 -- Production ops** | TLS (proxy integrated + tested), CI pipeline, packaging, config files, runbooks, backup/restore | ~5% |
| **M6 -- Public release** | self-host compiler + mature stdlib/packages, full security review, versioned API, docs site | not started (owner gate) |

---

## 6. Production gates checklist (what 100% requires)

- [x] HTTP/1.1 plaintext service with parse+response builder
- [x] Routing with params, 404/405
- [x] Uniform JSON errors
- [x] Cookie sessions + JWT HS256
- [x] Durable append store with crash-safe reopen
- [x] Structured logs, metrics endpoint, audit trail
- [x] 1h load soak with flat memory/handles
- [ ] Keep-alive + request/header limits + query-string parsing
- [ ] Real timeouts (recv deadline) and slow-client shedding
- [ ] Rate limiting + CORS + CSRF + security headers
- [ ] Schema validation for all inputs
- [ ] Credentials + RBAC; session persistence/rotation
- [ ] Graceful shutdown/signal handling + supervisor story
- [ ] TLS end-to-end test through the proxy
- [ ] CI (suites+soak on push) + release packaging
- [ ] Static/templates/SSE/WS/REST extras (framework surface)
- [ ] Crash/chaos suite (kill -9 matrix, disk-full, corrupt store)
- [ ] Stable self-hosted toolchain (ecosystem gate)

---

## 7. How this score is updated

At every PULSE wrap: adjust only the areas with new **evidence** (soak,
smoke, suite, or repro), recompute the weighted total, and note the delta
in one line at the top. Evidence lives in `SESSION.md`, `docs/repro/`,
`probe-logs/`, and the smoke/suite scripts. Do not raise an area for
"code written" -- raise it when a test or soak proves the behavior.
