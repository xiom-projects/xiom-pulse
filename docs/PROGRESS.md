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

## 1. Overall score: **~43% of production grade**

_Delta 2026-10-05 (evening wave): 41% -> 43% -- `xiom.rate` 0.2.0 adopted
(global token bucket, `429` + `Retry-After`, `rate_smoke` green), latency
histogram + `dur_ms` access-log field, `docs/DEPLOYMENT.md` published
(proxy-first TLS). Evidence: suites x2 (`test_app` 75 checks), smoke 44/44,
rate smoke GREEN, probe `probe_module_pkg_init` (C-PULSE-07 filed)._

| # | Area | Weight | Done | Weighted | Status |
|---|---|---:|---:|---:|---|
| 1 | HTTP core (parse/build/limits) | 12% | 72% | 8.6 | query strings + header caps landed; keep-alive/chunked/HEAD missing |
| 2 | Routing | 8% | 78% | 6.2 | registry `xiom.router` adopted (multi-`:param`, 404/405 + Allow); no wildcards/groups |
| 3 | Middleware framework | 8% | 10% | 0.8 | logging/audit inline only |
| 4 | Configuration | 5% | 60% | 3.0 | env-based; no file/validation |
| 5 | Observability (log/metrics/audit) | 8% | 68% | 5.4 | JSON log + `dur_ms` + counters + histogram + audit; flush no-op |
| 6 | AuthN/AuthZ | 10% | 35% | 3.5 | sessions + JWT HS256; no credentials, RBAC, rotation |
| 7 | Storage | 10% | 35% | 3.5 | JSONL store + crash-safe append; no query/update/compaction |
| 8 | Security hardening | 12% | 30% | 3.6 | rate limit + security headers + head caps; no CORS/CSRF/schema validation; TLS via proxy (guide published) |
| 9 | Static / assets | 4% | 20% | 0.8 | favicon + landing only |
| 10 | Protocol extras (SSE/WS/REST/GraphQL/templates) | 8% | 0% | 0.0 | none started |
| 11 | Reliability & concurrency | 10% | 45% | 4.5 | 1h soak 13,198/13,198 + 30m v0.64.0 soak 6,543/6,543, flat memory; single-thread, no timeouts, no signals |
| 12 | Testing / CI / release | 5% | 60% | 3.0 | suites+smoke+rate-smoke+soak+WSL locally; no CI, no packaging |
| | **Total** | **100%** | | **43.0** | |

Two lenses to keep separate:

- **PULSE's own work:** ~72% of the Step 0-4 plan (Steps 0-3 core + most of
  the M4 hardening wave; only the proxy E2E run is left for Step 4).
- **Production-grade framework:** **~43%**. The gap is mostly *hardening*
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
envelope, env config, JSON access log with request ids and `dur_ms`,
structured metrics (counters + duration histogram), audit trail, cookie
sessions, JWT, crash-safe JSONL store, binary responses, request body
framing, global rate limiting (429 + `Retry-After`), graceful test
shutdown (`X-Pulse-Quit`).

**Load evidence:** 1h soak: PS driver 7,070/7,070 + WSL client 6,128, server
served **13,198/13,198** requests, 0 errors, clean shutdown, working set
+48 KB, handles 113 -> 113. 64 simultaneous connections served, 64/64.

**Module inventory** (`src/`, all green in `tests/test_app.xi` x2):

| Module | Lines (rough) | Purpose |
|---|---:|---|
| `server.xi` | ~330 | accept loop, dispatch, send_all, log/audit wiring |
| `http.xi` | ~250 | request parse, response build (text/json/bytes) |
| `store.xi` | ~120 | JSONL append store, torn-line healing |
| `router.xi` | ~200 | app route table wrapper over registry `xiom.router`; query parsing + decoding |
| `session.xi` | ~100 | in-memory sessions, cookie bindings |
| `config.xi` | ~80 | env config with defaults |
| `metrics.xi` | ~120 | counters + request-duration histogram, Prometheus render |
| `ratelimit.xi` | ~50 | global token bucket wrapper over registry `xiom.rate` |
| `envelope.xi` | ~40 | error envelope |
| `pulse.xi` | ~15 | version |

---

## 3. What is missing, area by area (the honest list)

**HTTP core (72%)**
- No `keep-alive` (always `Connection: close`) -- the biggest perf item.
- No chunked transfer-encoding (request or response).
- No `HEAD` handling, no `Expect: 100-continue`, path not percent-decoded
  (query values are decoded).
- Head caps landed (16 KiB head, 100 headers, 1 MiB body); no per-route or
  per-connection byte-rate limits.
- Status is far from 100% even if all of the above land: response
  streaming, compression, HTTP/2 (proxy's job).

**Routing (78%)**
- Registry `xiom.router` 0.1.0 adopted: `src/router.xi` is a thin app
  wrapper (route ids + query parsing); consumer probe 8/8.
- Still missing: wildcards, optional segments, route groups, per-route
  middleware hooks, path percent-decoding.

**Middleware (10%)**
- Request-id/logging/audit are hardcoded in the loop.
- No composable chain, no recover-to-500, no CORS/CSRF helpers.

**Config (60%)**
- Env only; no config file, no schema validation, no startup warnings for
  missing production values (e.g. dev JWT secret).

**Observability (68%)**
- JSON access log with `rid`/status/bytes/`dur_ms`; counters + request
  duration histogram + `/metrics`; audit trail.
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

**Security hardening (30%)**
- TLS: front-proxy by design (Caddy/nginx); `docs/DEPLOYMENT.md` published
  with configs, supervision and a through-proxy verification checklist;
  the actual proxy E2E run is pending a proxy install.
- Global rate limiting landed (`xiom.rate` 0.2.0, `PULSE_RATE_LIMIT`,
  429 + Retry-After, `scripts/rate_smoke.ps1` green); per-client keys wait
  on `socket_peer_addr` (stdlib stub).
- No CORS/CSRF/schema validation; HSTS/CSP belong at the proxy.
- Header size/count caps landed (16 KiB / 100); no recv timeouts yet
  (stdlib queued) -- a half-open request can still hold the loop.

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
| C-PULSE-07 module-scope package ctor -> undefined call/crash | OPEN | package aggregates stay caller-owned |
| C-PULSE-02 deps not mapped to catalog roots | OPEN | `xiom.toml source-roots` wiring per package |
| No exe icon embedding | feature gap | icon served at `/favicon.ico` for now |
| stdlib deadlines/timeouts, write_all, request parser, real flush | queued wave | slow-client guard, streaming, HTTP parse duplication, log lag |
| `xiom.router` 0.1.0 | **LIVE and adopted by PULSE** (probe 8/8, suites x2) | routing hardened; wildcards/groups remain package roadmap |
| `xiom.session`/`static`/`http.middleware` | incubating; publish gated on allowlist delta | module replacement + middleware framework |
| Concurrency primitives (threads/select) | absent on the pin | caps throughput; single-threaded design |

Resolved on v0.64.0: C-PULSE-01, runtime-link (R65), crypto-link (m195).

---

## 5. Milestones (what "done" means next)

| Milestone | Criteria | State |
|---|---|---|
| **M1 -- Thin slice** | plaintext HTTP/1.1, routes, JSON, 404/405, curl + 64 concurrent + soak | **DONE** (2026-10-05) |
| **M2 -- App skeleton** | router, envelope, config, log, metrics, audit, sessions, JWT | **DONE** (core; hardening items above) |
| **M3 -- Storage** | durable store, schema, crash/reopen, soak | **DONE core** (JSONL; query/migrations pending) |
| **M4 -- Hardening** | timeouts, limits, keep-alive, rate limit, CORS/CSRF, validation, graceful shutdown, latency metrics | ~40% (queries, caps, security headers, rate limit, histogram landed) |
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
- [x] Request/header caps + query-string parsing
- [x] Rate limiting (global token bucket; per-client blocked on `socket_peer_addr`)
- [ ] Keep-alive + chunked + HEAD
- [ ] CORS + CSRF (HSTS/CSP at the proxy)
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
