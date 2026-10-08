<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- Progress Tracker

**Last updated:** 2026-10-08 (PULSE continuation: Windows re-verify + stdlib adoption)
**Purpose:** one page the owner can read to see what a full
production-grade XIOM web backend consists of, what already works, and
what is still missing. Updated by the PULSE session at every step wrap.

**How to read the score:** each area has a weight (share of a
production-grade framework) and a completion %. The overall score is the
weighted sum. Scores are intentionally strict: "works in the soak" counts
only with evidence attached, and an area is not 100% until it survives
load, failure, and restart, not just the happy path.

---

## 1. Overall score: **~52.6% of production grade**

_Delta 2026-10-08 (schema round): 51.8% -> ~52.6% -- **JSON schema helper**
(`src/schema.xi`: typed rule list, required/optional, length + numeric
bounds, first-failure `code`/`field`/`message`) wired into the login and
token routes with field-specific 400s (probe 14/14); **flaky JWT tamper
check fixed** (append instead of replacing the last base64url char -- one
Windows run flaked on trailing-bit equivalence). Remaining M4 items
(keep-alive, recv timeouts, signals) are all gated on stdlib capabilities
already filed._

_Delta 2026-10-08 (ops items): 51.5% -> ~51.8% -- **audit rotation**
(`PULSE_AUDIT_MAX_BYTES`, single generation, probe + app E2E), **CLI
`--version`/`--help`** and **build-info fields in `/api/version`**
(commit/build from runtime env; compile-time define filed as a toolchain
ask). Signal handling checked: no stdlib handler-install API -> SIGTERM
graceful stop stays blocked; keep-alive stays gated on recv timeouts
(`socket_set_timeout` stub) because one idle keep-alive client would
stall the single-threaded loop._

_Delta 2026-10-08 (continuation): 51.2% -> ~51.5% -- **Windows
re-verify of the registry wave GREEN** (pkg installs + suites x2 + smoke
61/61 + crash 6/6 + rate); **stdlib adoption**: `TcpStream.write_all`
replaces the hand-rolled send loop, and `server_parse_request` now backs
PULSE's HTTP parser behind the same caps with invalid-Content-Length
hardening (differential probe pins parity on both platforms). Module
renamed `xiom.pulse.server` -> `xiom.pulse.app` (C-PULSE-12 alias
collision). Ops answered `docs/OPS-REQUEST.md`: staging parked by owner,
Linux toolchain source pinned on dl (v0.64.0 archive), CI mechanics ready
for greenlight._

_Delta 2026-10-07 (Linux/registry wave): 46.9% -> ~51.2% -- the **Linux
target verified end-to-end** (native ELF from the same v0.64.0 source:
suites x2 with 0 failures, smoke 61/61, crash 6/6, store-soak 20s,
proxy E2E 11/11 through Linux nginx 1.24 TLS on the extracted-package
path; crypto KAT env-free), **12 `.sh` twins** written and verified from
WSL, and the **registry wave**: `xiom.metrics` 0.2.0 (labeled counters +
latency preset), `xiom.static` 0.1.0 (ETag/Cache-Control/Range/304 +
traversal guard) and `xiom.http.middleware` 0.1.0 (CSRF/CORS) adopted
green. `xiom.session` store-integration and `xiom.kv` are filed as
C-PULSE-09/10 with repros; local store + JSONL remain the documented
fallbacks._

| # | Area | Weight | Done | Weighted | Status |
|---|---|---:|---:|---:|---|
| 1 | HTTP core (parse/build/limits) | 12% | 76% | 9.1 | query strings, header caps, HEAD; shared stdlib parser + invalid-CL reject; keep-alive/chunked/Expect missing |
| 2 | Routing | 8% | 78% | 6.2 | registry `xiom.router` adopted (multi-`:param`, 404/405 + Allow); no wildcards/groups |
| 3 | Middleware framework | 8% | 30% | 2.4 | registry CSRF/CORS/error helpers adopted; still no composable chain |
| 4 | Configuration | 5% | 75% | 3.8 | env + JSON file (env-wins) incl. `PULSE_STATIC_DIR`; no schema validation of values |
| 5 | Observability (log/metrics/audit) | 8% | 80% | 6.4 | registry metrics (labeled counters, latency-bounds histogram, exposition) + JSON log + audit with **rotation** + rid + gauges; flush no-op |
| 6 | AuthN/AuthZ | 10% | 35% | 3.5 | sessions + JWT HS256 + CSRF (constant-time via registry); no credentials, RBAC, rotation |
| 7 | Storage | 10% | 55% | 5.5 | JSONL store, crash-safe append, `?limit`/`?kind`, compaction, 10m soak; `xiom.kv` blocked (C-PULSE-10), no fsync |
| 8 | Security hardening | 12% | 44% | 5.3 | rate limit + CSRF + opt-in CORS + security headers + caps + static traversal guard + schema helper (typed field rules); no RBAC |
| 9 | Static / assets | 4% | 55% | 2.2 | registry `xiom.static`: mime/ETag/Cache-Control/304/Range + favicon; no directory serving |
| 10 | Protocol extras (SSE/WS/REST/GraphQL/templates) | 8% | 0% | 0.0 | none started |
| 11 | Reliability & concurrency | 10% | 45% | 4.5 | 1h soak 13,198/13,198 + 30m v0.64.0 soak 6,543/6,543, flat memory; single-thread, no timeouts, no signals |
| 12 | Testing / CI / release | 5% | 73% | 3.7 | suites+smoke+soak+probes on **Windows and Linux**; `.ps1`+`.sh` twins; `--version` + build-info surfaces; flake-free tamper gate; no CI, no packaging |
| | **Total** | **100%** | | **52.6** | |

Two lenses to keep separate:

- **PULSE's own work:** ~80% of the Step 0-4 plan (Steps 0-3 core, the M4
  hardening wave, proxy E2E green on Windows and Linux, the Linux port +
  `.sh` twins, and the registry adoption wave except the two blocked
  packages).
- **Production-grade framework:** **~46%**. The gap is mostly *hardening*
  and *ecosystem maturity*, not basic function.

---

## 2. What works today (evidence-backed)

Run `out/` (Linux) or `out\pulse_app_v9.exe` (Windows); smoke 61/61 and
suites x2 on both platforms, these work end-to-end:

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

**HTTP core (74%)**
- No `keep-alive` (always `Connection: close`) -- the biggest perf item.
- No chunked transfer-encoding (request or response).
- `HEAD` supported (GET semantics, body omitted); no `Expect: 100-continue`,
  path not percent-decoded (query values are decoded).
- Head caps landed (16 KiB head, 100 headers, 1 MiB body); no per-route or
  per-connection byte-rate limits.
- Status is far from 100% even if all of the above land: response
  streaming, compression, HTTP/2 (proxy's job).

**Routing (78%)**
- Registry `xiom.router` 0.1.0 adopted: `src/router.xi` is a thin app
  wrapper (route ids + query parsing); consumer probe 8/8.
- Still missing: wildcards, optional segments, route groups, per-route
  middleware hooks, path percent-decoding.

**Middleware (30%)**
- Request-id/logging/audit are still wired inline in the loop.
- Registry `xiom.http.middleware` 0.1.0 adopted for CSRF token/validate and
  CORS header building; no composable chain, no recover-to-500.

**Configuration (75%)**
- Env-based with a JSON file (`PULSE_CONFIG`) for all eleven settings;
  environment variables win over file values.
- No value schema/range validation beyond per-setting parsers/fallbacks.

**Observability (78%)**
- On registry `xiom.metrics` 0.2.0: labeled status-class counters, the
  11-bound latency-preset histogram, Prometheus exposition; JSON access
  log with `rid`/status/bytes/`dur_ms`; audit trail; request ids embedded
  in error envelopes; gauges (`pulse_app_info`, `pulse_store_records`,
  `pulse_uptime_seconds`).
- `io.flush_stdout()` is an empty body in the current stdlib -> logs can
  lag until process exit (stdlib wave queued).

**AuthN/AuthZ (35%)**
- Login trusts any username (no credential store/verification).
- Sessions are memory-only (lost on restart), no rotation on login.
- JWT: HS256 only, single static secret (dev default), no key rotation,
  no scopes/roles, no refresh tokens.
- No RBAC/authorization layer at all.

**Storage (55%)**
- Append + read last N (`?limit=1..100`) + `?kind=` field filter + count +
  compaction (temp file + atomic replace; drops torn lines); **10m soak:
  841 writes, 0 fail, compact/reopen counts intact, 0 mismatches**
  (`scripts\store_soak.ps1`). No update/delete, migrations framework, or
  indexes (fine at small scale).
- No `fsync` in the runtime: durability today = torn-tail healing, not
  power-loss safety (stdlib wishlist row added).
- `xiom.kv` is the proposed packages-lane replacement.

**Security hardening (38%)**
- TLS: front-proxy by design (Caddy/nginx); `docs/DEPLOYMENT.md` published
  with configs, supervision and a through-proxy verification checklist;
  the actual proxy E2E run is pending a proxy install.
- Global rate limiting landed (`xiom.rate` 0.2.0, `PULSE_RATE_LIMIT`,
  429 + Retry-After, `scripts/rate_smoke.ps1` green); per-client keys wait
  on `socket_peer_addr` (stdlib stub).
- CSRF double-submit on session-authenticated mutations (403 without the
  token; smoke-verified); opt-in CORS with preflight (204).
- Field length validation for `user`/`token`; no general schema library.
- Header size/count caps landed (16 KiB / 100); no recv timeouts yet
  (stdlib queued) -- a half-open request can still hold the loop.

**Static/assets (55%)**
- Favicon served through registry `xiom.static` 0.1.0: MIME map, ETag,
  Last-Modified, Cache-Control, `If-None-Match` 304, `Range` 206/416,
  traversal guard; landing page dynamic. No directory serving yet.

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

**Testing/CI/release (68%)**
- Local, both platforms: 3 suites (x2), smoke (61), crash/reopen (6),
  soak drivers (PS + shell), rate/store soaks, 20+ probes, byte-level
  lint greps. Every script ships as `.ps1` + `.sh` (LF enforced); WSL
  verification of all 12 twins.
- No CI pipeline, no coverage number, no fuzzing, no packaging/release
  process, DCO-only workflow.

---

## 4. Ecosystem blockers affecting PULSE (not PULSE's own code)

| Blocker | State on v0.64.0 | PULSE impact |
|---|---|---|
| C-PULSE-04 bare `&mut Int` read -> address | OPEN | keeps `*p` discipline; blocks cursor-style parsing in lane code |
| C-PULSE-05 const-receiver `.to_str()` W005 -> abort | OPEN (worse: 0x80000003) | `convert.int_to_string` workaround stays |
| C-PULSE-06 missing struct field -> garbage | OPEN | every struct literal must list all fields |
| C-PULSE-07 module-scope package ctor -> undefined call/crash | OPEN | package aggregates stay caller-owned (Vec-holder pattern pinned by `probe_pkg_state_holder`) |
| C-PULSE-08 m212 dotted-key roots (latent, lane source) | latent | `source-roots` workaround stays; gate `docs/repro/dep-roots-name-form` |
| C-PULSE-09 xiom.session store integration crash via wrapper modules | OPEN | session store swap deferred; local store retained (`probe_adopt_smoke` vs `probe_session_inline`) |
| C-PULSE-10 xiom.kv kv_get Str corruption + bytes truncation | OPEN (classification) | `xiom.kv` adoption blocked; JSONL fallback documented (`docs/repro/kv-get-str-corruption`) |
| C-PULSE-11 package type alias invisible cross-module (defaults to i64) | OPEN | use wrapper structs, never `pub type X = PackageType` |
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
| **M4 -- Hardening** | timeouts, limits, keep-alive, rate limit, CORS/CSRF, validation, graceful shutdown, latency metrics | ~72% (registry metrics latency preset, static ETag/Range/304, CSRF via registry, caps, histogram, HEAD, stdlib write_all + parser, audit rotation, CLI surfaces, schema helper with typed field errors; recv timeouts + signal handling blocked on stdlib) |
| **M5 -- Production ops** | TLS (proxy integrated + tested), CI pipeline, packaging, config files, runbooks, backup/restore | ~22% (TLS E2E green on Windows **and** Linux; `.sh` twins; deployment runbook + ops answers with the pinned Linux toolchain; `--version`/build-info surfaces; CI/packaging pending greenlight) |
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
- [x] CSRF double-submit + opt-in CORS
- [ ] Keep-alive + chunked + Expect: 100-continue
- [ ] Schema validation library (field length caps landed)
- [ ] Real timeouts (recv deadline) and slow-client shedding
- [ ] Rate limiting + CORS + CSRF + security headers
- [ ] Schema validation for all inputs
- [ ] Credentials + RBAC; session persistence/rotation
- [ ] Graceful shutdown/signal handling + supervisor story
- [x] TLS end-to-end test through the proxy (Windows nginx + Linux nginx 1.24, 11/11 both)
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
