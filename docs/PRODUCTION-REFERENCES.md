<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Production references (PULSE lane) -- patterns to steal, legally

**Owner permission (2026-10-11):** the PULSE lane may clone reference
repositories under `E:\repos` and use them for ideas/patterns/mechanics.
House rule: **MIT-licensed (or looser) only**, so even code-level
inspiration is cleared. We copy *patterns and mechanics*, never code
(XIOM is a different language anyway).

Cloned and studied so far (all verified MIT):

| Repo | What it is | Why it matters to PULSE |
|---|---|---|
| `E:\repos\h11` | HTTP/1.1 protocol state machine, sans-IO (python-hyper) | the reference for connection state, keep-alive and framing edge cases |
| `E:\repos\bbolt` | embedded B+tree KV, crash-safe commit (etcd) | the reference for durable commit ordering (store/audit/`xiom.kv`/orbitdb) |
| `E:\repos\gin` | Go HTTP framework | the reference for middleware chains, context lifecycle, recovery |
| `E:\repos\fasthttp` | high-performance Go HTTP server | server runtime mechanics: named timeouts, concurrency caps, buffer reuse |
| `E:\repos\fastify` | Node HTTP framework | hook taxonomy, encapsulation, schema-driven validation/serialization |
| `E:\repos\fastapi` | Python framework | dependency injection, OpenAPI generated from route types, background tasks |
| `E:\repos\chi` | Go router | route groups with isolated middleware; declare-then-freeze ordering |
| `E:\repos\jose` | JOSE/JWT library (panva) | token verification hardening options (alg allowlist, claims, age) |
| `E:\repos\helmet` | security headers middleware | the named policy set for our security headers |
| `E:\repos\knex` | SQL query builder + migrations | migration lock table + applied-tracking discipline for the SQL class |
| `E:\repos\bullmq` | Redis-backed job queue | jobs mechanics: attempts/backoff, delayed jobs, stalled-lock renewal |

All MIT-verified at clone time (light clones, `--depth 1`, no history;
owner-authorized policy on this shelf).

---

## h11 -- connection state machine (sans-IO)

**Mechanics worth adopting**

1. **Explicit two-sided state machine.** `our_state`/`their_state`
   (`IDLE -> SEND_RESPONSE -> DONE / MUST_CLOSE`) with legal-transition
   tables, instead of inferring connection health from reads/writes.
   PULSE today has no per-connection state model; when keep-alive lands,
   adopt a small enum + transition check per connection.
2. **Sans-IO split.** Protocol decisions are pure; sockets/timeouts are
   the caller's layer. PULSE's `read_request` blends both -- split into a
   pure frame decoder (testable without sockets) + a thin IO wrapper.
3. **Keep-alive derived from the message.** `_keep_alive()` = HTTP
   version + `Connection` header + framing presence; protocol errors set
   MUST_CLOSE and no recovery is attempted mid-message (send 400, close).
   Use as the written checklist for our keep-alive/`Connection: close`
   handling and framing-error paths (we already 400 on TE+CL).
4. **EOF is an event, not an error.** `ConnectionClosed` is state-driven
   (paused until the current message reaches DONE) -- the model that
   avoids half-message corruption on abrupt client disconnects.

**Maps to:** keep-alive + deadline work (paired with the stdlib socket
timeout asks `REL-20261011-0317-pulse*`), and `src/http.xi`'s future
parser hardening.

## bbolt -- crash-safe commit ordering

**Mechanics worth adopting**

1. **Data-before-meta, fsync in between.** Commit = spill dirty pages ->
   write pages -> **fdatasync** -> write meta page (txid + checksum,
   alternating meta0/meta1) -> fsync. A crash at any point leaves the
   previous meta valid; torn writes are detected by checksum. This is the
   blueprint for honest durability claims in our store seam (PULSE today
   only heals torn tails; see the `fsync` bus ask `...pulse-6`).
2. **Two-phase freelist.** Pages freed by a tx are reusable only after
   that tx is durable -- prevents overwriting live data on rollback.
   Relevant if compaction ever moves from full-rewrite (current
   `store_compact` rename, safe) to in-place rewriting.
3. **Read-snapshot isolation.** Readers pin the meta they started with;
   one writer at a time. Informs the reader/writer seam for the future
   embedded store (orbitdb driver) and safe backup tooling.
4. **Documented tradeoffs**: `NoFreelistSync` is an explicit, named
   durability/perf knob -- the same philosophy as our
   `PULSE_SITE_MAX_AGE` / store options: opt-in, named, documented.

**Maps to:** the store/durability bus asks, `xiom.kv` adoption depth,
orbitdb driver design (0.3).

## gin -- framework mechanics

**Mechanics worth adopting**

1. **Middleware chain = flat handler slice + index cursor.**
   `Next()` walks `index++` over `[]HandlerFunc`; `Abort()` sets
   `index = abortIndex` (a large sentinel) so no further handlers run.
   No nested closures; composable, cheap, debuggable. Blueprint for the
   PULSE middleware chain (0.4: request-id, access log, CORS, CSRF over
   the envelope), replacing our inline if/else ordering.
2. **Precomputed chains.** `combineHandlers` builds each route's full
   chain (group middleware + route handlers + NoRoute/NoMethod) at
   registration time. PULSE rebuilds its router per call (acceptable
   now); precomputation is the documented upgrade path.
3. **Context lifecycle discipline.** `sync.Pool` acquire + full reset of
   every field on release; `index = -1` on reuse. XIOM has no threads
   yet, but the reset-everything discipline maps to our per-request
   structs/buffers (no stale state across requests).
4. **Recovery middleware.** `recover()` -> 500 + log + `c.Abort()`,
   process survives; debug vs release behavior switch. PULSE's analogue
   is contract traps -- currently fatal by design; catching them is an
   open question for the compiler lane (noted, not promised).
5. **Options struct pattern** (trusted proxies, redirects, body limits)
   mirrors our env/JSON config surface -- keep validating each new knob
   explicitly (we do).

**Maps to:** 0.4 integrations (middleware/jobs) and the router
precomputation path; nothing blocking today.

---

## fasthttp -- server runtime mechanics

- **Three named timeouts, explicit semantics**: `ReadTimeout`
  (headers+body), `WriteTimeout`, `IdleTimeout` -- and **IdleTimeout
  falls back to ReadTimeout when zero**. Plus `MaxRequestBodySize` and
  concurrency caps (`DefaultConcurrency`, per-IP). Adopt these names and
  the fallback rule when PULSE adds keep-alive/deadlines; our config
  surface should expose all three, not one.
- **Per-worker pooled buffers / zero-alloc handlers**: reuse over
  allocation, with explicit reuse boundaries. XIOM can't mirror the
  unsafe pooling, but the discipline maps to explicit buffer clears.

**Maps to:** keep-alive/deadlines design (0.3.x) with the stdlib
socket-timeout bus asks.

## fastify -- hooks, encapsulation, schemas

- **Hook taxonomy** (use this list as our middleware stage names):
  `onRequest`, `preParsing`, `preValidation`, `preHandler`,
  `preSerialization`, `onSend`, `onResponse`, `onError`, plus
  application hooks (`onRoute`, `onRegister`, `onReady`) and per-route
  hooks. Custom properties are injected per scope.
- **Encapsulation**: plugins get isolated contexts; children inherit
  parents' hooks -- route groups that can add middleware without
  leaking sideways.
- **Schema-driven validation + serialization**: one schema validates
  input and speeds serialization. Pairs directly with our OpenAPI
  contract: derive runtime validation from the same schema (validation
  unit, later).

**Maps to:** 0.4 middleware chain; validation/contract unit.

## fastapi -- DI and OpenAPI-from-types

- **Dependency injection** (`Depends`) with per-test overrides -- the
  grown-up version of our `reqctx`; services (config, store, session)
  become injectable and test-swappable.
- **OpenAPI is generated from route signatures/models** (operation ids,
  components). We hand-maintain `resources/openapi.json` today; the
  direction of travel is generating it from route metadata.
- **Background tasks** bound to the response lifecycle -- the small-job
  seam ahead of the full queue.

**Maps to:** contract generation; DI for the 0.4 services layer.

## chi -- router groups and middleware ordering

- Middleware is **appended then frozen**: `Use()` after routes panics
  ("all middlewares must be defined before routes"). PULSE rebuilds its
  router per call (fine now) but should adopt declare-once/freeze when
  the table stabilizes.
- **Groups** create sub-routers with their own middleware, composed
  with parents -- the shape for `/v1`, `/api`, and future admin
  surfaces.

**Maps to:** router precomputation + route groups (0.3/0.4).

## jose -- JWT/JOSE verification hardening

- Verify options worth mirroring in our token path: **algorithm
  allowlist** (never accept `none`), `issuer`/`audience` checks,
  `clockTolerance`, **`maxTokenAge`**, `requiredClaims`; per-algorithm
  key binding.
- Errors are typed by cause (expired vs signature vs claim) -- better
  401/403 distinctions for clients.

**Maps to:** `xiom.jwt` 0.2.0 consumer hardening + auth unit.

## helmet -- security header policy

- The named policy set to adopt as PULSE's reviewed defaults:
  **CSP** (+ directives), **HSTS** (includeSubDomains/preload),
  `X-Content-Type-Options: nosniff`, frameguard
  (`X-Frame-Options`/CSP frame-ancestors), `Referrer-Policy`, and the
  cross-origin family (COOP/COEP/CORP). We ship minimal headers today;
  this is a small, high-value unit.

**Maps to:** security-headers unit (0.2.x/0.3.x).

## knex -- migrations discipline (SQL class)

- **Migration lock table** (`knex_migrations_lock` via
  `getLockTableName`) + a typed `MigrationLocked` error + an explicit
  `forceFreeMigrationsLock()` escape hatch; applied migrations tracked
  in `knex_migrations`. Blueprint for the sqlite-backed SQL class:
  lock row, applied table, deliberate force-free.
- Immutable query-builder chains compiled to SQL -- the shape for our
  query layer.

**Maps to:** SQL class migrations (0.3, after the `--c-source` story).

## bullmq -- jobs/queue mechanics

- **attempts/`attemptsMade` + backoff classes**; delayed jobs;
  `removeOnComplete/Fail` policies; **stalled-job detection via
  periodic lock renewal**; atomic state moves via scripts. Use as the
  blueprint for the 0.4 kv-backed jobs/scheduler: named states
  (waiting/delayed/active/completed/failed), attempts+backoff, and a
  lock-renewal watchdog.

**Maps to:** 0.4 jobs/queue + webhook retries.

---

## Adopt backlog (PULSE-side, version-ordered)

- [x] **Keep-alive/deadlines design doc** using the h11 checklist
  and fasthttp's three-timeout model; pairs with the stdlib
  socket-timeout/deadline bus asks. -- **DESIGN LANDED 2026-10-11**
  (`docs/DESIGN-KEEPALIVE-DEADLINES.md`): three named timeouts
  (`PULSE_{READ,WRITE,IDLE}_TIMEOUT`; 408 on read expiry, silent close on
  idle expiry), the h11 keep-alive state rules, and a two-phase
  implementation plan (A: deadlines -- blocked on the stdlib runtime
  wave; B: keep-alive on top).
- [x] **Store durability design**: bbolt ordering discipline for the
  store seam + backup story; pairs with the `fsync` bus ask and the
  orbitdb driver unit. -- **DESIGN LANDED 2026-10-11**
  (`docs/DESIGN-STORE-DURABILITY.md`): sync-before-ack commit points
  (store + audit, `PULSE_STORE_SYNC`/`PULSE_AUDIT_SYNC`), compaction
  rename ordering + `fsync_dir` ask, seq-in-record as the commit marker,
  backup fence manifests, explicit claim table; three-phase plan.
- [x] **Security headers unit** (helmet checklist) -- **ADOPTED
  2026-10-11**: the reviewed default set ships in both response builders
  (`X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`,
  COOP/CORP `same-origin`, `Origin-Agent-Cluster`, HSTS 180d
  includeSubDomains, X-DNS-Prefetch-Control off, X-Permitted-Cross-Domain
  none, X-XSS-Protection 0); CSP is opt-in via `PULSE_CSP`/`csp` (site
  mode safety). Evidence: test_http +12 checks (74 green, both builders),
  csp-check integration run (header set/absent wired end to end),
  `probe-logs/regress-20261011/`.
- [x] **SQL class migrations discipline** (knex lock/applied). --
  **DESIGN LANDED 2026-10-11** (`docs/DESIGN-SQL-MIGRATIONS.md`): knex
  model (lock table + applied tracking + batches + UTC-lexicographic
  names) with PULSE corrections (stale-lock heartbeat instead of
  destructive unlock, idempotent first-run DDL, strict missing-file
  validation, per-migration transaction rule incl. sqlite/MySQL
  caveats), explicit CLI runner + backup-fence gate. Gated on a SQL
  driver package (vendored sqlite).
- [0.3/0.4] **OpenAPI generation from route metadata**
  (fastapi/fastify direction) -- eventually retires the hand-maintained
  document. -- **PARTIAL 2026-10-11**: route table is now single-source
  (`router.route_defs()`; dispatch, CLI and guards derive from it), a
  structural drift guard (`openapi.openapi_missing_routes`, run by
  test_app) fails the suite when a route never reaches the contract, and
  the undeclared `uploads` tag is fixed. Remaining: emit the `paths`
  object from the table (static overlay for prose/refs), `openapi
  --check` CLI mode, retire the hand-written paths block.
- [0.4] **Middleware chain** (gin pattern + fastify stage names) +
  recovery guard + context reset discipline; precompute chains.
- [0.4] **Jobs/queue mechanics** (bullmq) for retries/backoff/stalled
  locks.
- Watch: when upstream threads land, gin-style pooling becomes directly
  applicable.
