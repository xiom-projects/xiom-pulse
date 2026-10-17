<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Design: middleware chain + jobs layer (gin / fastify / bullmq)

Status: DESIGN (2026-10-11, PULSE session). Backlog order 6 (final) of
`docs/PRODUCTION-REFERENCES.md`. References: `E:\repos\gin`,
`E:\repos\fastify`, `E:\repos\bullmq` (MIT light clones).

## 1. Problem statement

Today the per-request pipeline is a hand-wired ladder in the accept loop
(`src/server.xi`) and everything else is sprinkled around it:

- Gate order is branch order at `server.xi:893-952`: parse-error (400,
  413 on "too large") -> `X-Pulse-Quit` -> CORS preflight OPTIONS -> CSRF
  -> rate limit -> dispatch. The order is load-bearing but only partially
  pinned by tests (smoke covers 405/CSRF/HEAD/OPTIONS/quit; **nothing
  pins CSRF-before-rate-limit, OPTIONS bypassing both, or quit after a
  malformed parse**).
- Access log and metrics are called at five different sites
  (`server.xi:909/923/935/952/989` and `907-988`); audit only in the
  dispatch branch (`990-992`); a new cross-cutting concern today means
  editing the ladder in several places.
- `reqctx` is one module-global rid (`src/reqctx.xi:9-21`); everything
  else is by-value (`PulseRequest`, `HandlerOut` at `server.xi:83-89`).
- There is no error stage: each failure branch builds its own envelope
  and returns.
- There is no deferred work at all: audit rotation, session pruning and
  compaction all run inline in the request path; any future background
  task needs new machinery.

## 2. Reference models

**gin** (flat precomputed chain): one `[]HandlerFunc` per route is
combined at registration (`routergroup.go:277-284`, stored on the tree
node `gin.go:400`); dispatch takes a pooled `Context`, resets it
(`context.go:103-118`), sets `c.handlers`, and runs `Next()`
(`context.go:197-205`); `Abort()` jumps `index` to `abortIndex`(127)
(`context.go:216-218`); `Recovery` is a normal middleware -- `defer
recover()` around downstream `Next()` (`recovery.go:58-91`) -- and must
be registered early; 404/405 chains are precomputed separately
(`gin.go:379-385`). Middleware added after a route never patches it
(chain built at registration).

**fastify** (named stages): ten hooks run in a fixed order -- onRequest
(no body) -> preParsing -> (body parse) -> preValidation -> (schema
validation) -> preHandler -> handler -> preSerialization -> (serialize)
-> onSend -> (write) -> onResponse; errors route to onError -> error
handler chain -> fallback (`docs/Reference/Lifecycle.md:12-42`,
`Hooks.md:54-55`; runners in `route.js:567-576`, `handle-request.js:89-146`,
`reply.js:213/565/974`). Per-route, per-stage chains are precomputed at
`preReady` with a null fast-path for empty stages
(`route.js:389-395`); a committed response short-circuits remaining
stage hooks (`hooks.js:410-413`). Recovery is per-call try/catch +
promise rejection funneling (`handle-request.js:189-209`), replacing
gin's panic guard.

**Convergent shape:** ordered linear stages; an error branch reachable
from every stage; response-side stages running reverse-ish; per-route
precomputation; empty-stage fast paths.

## 3. Adopted middleware model (PULSE 0.4)

### 3.1 The nine stages

| # | Stage | Runs | PULSE mapping |
|---|---|---|---|
| 0 | `request` | before body work | rid mint (`server.xi:889-890`), parse (`891-893`), parse-error envelope (400/413), quit header |
| 1 | `parse` | body availability | body->Str, TE/CL policy today inside `handle_route` (`234-242`) stays route-level for 0.4; kept as a stage for future streaming |
| 2 | `validate` | pre-handler | CSRF (`924-935`); route schema validation stays in the handler |
| 3 | `beforeHandler` | pre-handler | CORS preflight short-circuit (OPTIONS -> 204, `913-923`), rate limit (`936-952`), future auth |
| 4 | `handler` | the route | `dispatch_one` -> `route_match` -> `handle_route` (`210-224`) |
| 5 | `beforeSerialize` | handler result | error `status` decoration / envelope normalization |
| 6 | `beforeSend` | pre-write | HEAD trimming (`966-977`), `with_std_headers`, `with_cors`, security block |
| 7 | `afterResponse` | post-send | access log (`989`), metrics duration (`987-988`), audit (`990-992`) |
| 8 | `error` | any failure | single envelope builder; ends the chain |

Ordering contract: stages run in numeric order; stage 8 is reachable
from 0-6; a response committed by an earlier stage skips the rest
(fastify's sent-guard). The **existing gate order is preserved exactly**
(stage order 0 -> 2 -> 3 for parse/CSRF/rate respectively), so behavior
is unchanged in a mechanical refactor.

### 3.2 Mechanics

- **Seam:** wrap the main ladder (`server.xi:893-993`); `dispatch_one`
  (`210-224`) remains the inner handler seam. Both are already plain
  function calls -- the chain is nested calls, no state machine needed
  in single-threaded XIOM.
- **Registration:** a static module table (stage -> Vec of step ids)
  built once at startup; route-specific precomputation only when a
  route-level hook table exists (structural copy of fastify's per-route
  arrays). No per-request allocation: steps are enum-like ids resolved
  to function calls, or a Vec of small descriptors built at startup and
  read.
- **Reset contract (formal):** per-request state lives in
  `PulseRequest`/`HandlerOut` by value; the only module-global is the
  rid, which `request` stage assigns and no stage may leave set after a
  response. Any future pooled context gets an explicit `reset()` list
  (gin's 14-field discipline, `context.go:103-118`) before pooling.
- **Guard:** XIOM has no panics, so the "recovery middleware" port is
  the error stage's guarantee: every stage returns either a response or
  an error descriptor; the runner converts an unhandled error descriptor
  to a 500 envelope (with rid) and always runs stages 7-8. The compiler
  crash class (REL-20261010-1854/2122) is out of in-process reach; those
  remain bus-watched.
- **Observability first:** stages 7's single call site replaces the five
  duplicated log/metrics sites; the audit emission rule becomes
  `method != GET && response committed` in one place.
- **Perf note:** today `route_match` rebuilds the registry table per
  call (documented negligible); the chain must not add per-request
  allocation beyond what exists. If profiling ever demands it, the
  gin pattern (precomputed flat array per route) is the escape hatch.

### 3.3 Compatibility tests -- LANDED 2026-10-17

`scripts/gate_order.py` starts its own server (CSRF + rate limit enabled,
isolated store/audit dirs) and pins 11 checks before the refactor:
CSRF 403 beats rate 429 for mutating cookie requests (bucket emptied
first and verified with a 429); OPTIONS 204 bypasses both; a malformed
head carrying `X-Pulse-Quit` gets 400 and the loop stays alive; the
well-formed quit closes silently and exits 0; oversized CL bodies get
413. Both smoke scripts invoke it (one smoke check; the score is now
135/135). CI dry run `39051902537` is green on both platforms with the
harness wired in.

**Found while writing the pin:** a plain `Content-Length` body above the
1 MiB cap was silently truncated by `read_request` and dispatched (the
route then answered 400 `invalid_json`), instead of 413. The ladder now
checks the declared CL against `MAX_BODY` before the CSRF/rate stages and
answers 413 `payload_too_large` without dispatching; the package note
(`REL-20261017-1533-pulse`) asks `parse_request` to reject a truncated
declared body too.

**Stage 7 landed (2026-10-17):** `after_response()` is now the single
afterResponse call site -- send, metrics, access log, and the audit
decision for every response path (408/parse/204/403/429/dispatch); the
eight duplicated tails are gone. Behavior is unchanged (suites x2 + smoke
135/135 x2 + crash x2 green both platforms; CI dry run `39062233020`
green on both platforms).

**Stages 0-3 landed (2026-10-17):** `gate_request()` owns parse/too-large
-> quit -> OPTIONS -> CSRF -> rate and returns a `GateResult`
(action 0 dispatch / 1 send / 2 quit), preserving the frozen order.
`gate_order.py` (11 checks) plus suites x2 + smoke 135/135 x2 + crash x2
are green on both platforms. Next: stages 4-6 (`build_dispatch_response`
extraction: dispatch -> build -> HEAD trim -> std headers/CORS), then the
static stage table if the profiling note still wants it.

Smoke and both suites keep passing unchanged otherwise.

## 4. Adopted jobs model (PULSE 0.4, bullmq port)

### 4.1 Portable core (what bullmq teaches, minus Redis)

| Mechanic | bullmq source | PULSE port |
|---|---|---|
| States: waiting / delayed / active / completed / failed | `queue-keys.ts:8-27`, `job-type.ts:3-9` (state = set membership) | explicit state field on an in-memory job record |
| Attempts + backoff (fixed / exponential `2^(n-1)*delay`, jitter, `-1` cancels) | `backoffs.ts:11-62`, predicate `job.ts:706-725` | same pure math; retry delay computed from the failing attempt, before terminal write |
| Delayed promotion (due-time ordered) | `getDelayedScore.lua:7-24`, `promoteDelayedJobs.lua:16-43` | min-heap keyed by `(due_at, seq)`; promote due jobs at every loop boundary |
| Retry scheduling: delay>0 -> delayed; 0 -> immediate requeue; attempts++ on requeue | `job.ts:742-791`, `moveToDelayed-11.lua:66-76` | same branch; counter increments on requeue, not success |
| Lock + heartbeat: token + deadline, renew at `lockDuration/2`, CAS on token | `worker.ts:295`, `lock-manager.ts:97-127`, `extendLocks-1.lua:31-45` | per-active-job `{token, heartbeat}`; in-process ownership check |
| Stalled sweep: two-phase (candidates one interval ago + missing heartbeat now), `LREM active` guard, maxStalled -> deferred failure applied on next pickup | `moveStalledJobsToWait-9.lua:44-120`, `worker.ts:1142-1154` | same two-phase scan over the in-memory active set |
| Terminal transitions verify ownership atomically with active-removal | `moveToFinished-14.lua:122-173`, `removeLock.lua:1-18` | single-threaded atomicity; still check token to catch logic bugs |

### 4.2 What does not port

Redis key layout + Lua scripts, blocking-marker wake-ups, event streams,
priorities/dedup/waiting-children, schedulers, sandboxed workers
(`worker.ts:346-397`) -- a single process gets atomicity from one thread
and wake-ups from the accept loop.

### 4.3 The single-threaded runner constraint

PULSE has no timers and (until the stdlib socket wave) no deadline to
wake on. The jobs runner therefore:

- runs at loop boundaries: before `socket_accept` and after each request,
  bounded (max K jobs or max N ms by `time.monotonic_ms()` per
  iteration) so it can never starve accept;
- never sleeps/blocks: delayed jobs are promoted when `due_at <= now` at
  a boundary; the heartbeat check piggybacks on the same boundaries;
- persists nothing in 0.4: jobs are in-memory and lost on restart
  (documented); durable jobs ride the store when the durability phase
  lands (`docs/DESIGN-STORE-DURABILITY.md`);
- when Phase B keep-alive lands (`docs/DESIGN-KEEPALIVE-DEADLINES.md`),
  the idle deadline becomes the natural runner wake point.

### 4.4 First adopters (after the core lands)

1. Audit rotation (today inline in `audit_event`, `server.xi:650-651`).
2. Store compaction (today manual-only via `POST /api/events/compact`)
   with a scheduled policy.
3. Session pruning (today opportunistic in `session_create`,
   `session.xi:61`).
Each move must keep the request-path guarantee: the request never waits
on a job.

## 5. Phased plan

- **Phase A -- middleware chain refactor (no behavior change):** add the
  order tests first; extract the nine stages; single call sites for
  log/metrics/audit; suites + smoke + regression sweep + CI dry run.
- **Phase B -- jobs core:** job record + states + backoff math + delayed
  heap + lock/heartbeat + stalled sweep + bounded runner; tests per
  mechanic (incl. a deliberately stalled job and an exhausted-attempts
  job); no production adopters yet.
- **Phase C -- adopters + persistence:** move rotation/pruning/compaction
  onto the queue; persist job records via the store once fsync lands;
  ops docs (job states in `/metrics` or a `/api/jobs` surface -- decide
  then).

Every phase: suites x2 + smoke both platforms (pinned stdlib), docs +
relay updates, signed commit, CI dry run.

## 6. Open questions / risks

- XIOM function-pointer reassignment is limited (bus item
  `REL-20261011-0317-pulse-7`: module-scope fn-pointer reassignment
  unsupported) -- the chain may need dispatch-by-id switch instead of
  stored function pointers; decide in Phase A.
- Chain precompute vs today's per-call route table rebuild: keep both
  simple until profiling says otherwise.
- The error stage must not leak internals: envelope builder already
  centralizes codes/messages (`envelope.xi:14-23`).
- Jobs observability and shutdown semantics (in-flight jobs on SIGTERM)
  interact with the graceful-drain gap; document the guarantee per
  phase.
- Stage naming stability matters for hooks documentation; freeze the
  nine names at Phase A and version any additions.

## 7. Source index

- gin: `routergroup.go:96-115, 277-284`; `gin.go:196-255, 363-408,
  691-808`; `context.go:57, 103-118, 197-226, 261-277`; `recovery.go:35-116`.
- fastify: `docs/Reference/Lifecycle.md:12-48`; `docs/Reference/Hooks.md:54-310`;
  `lib/hooks.js:11-91, 230-266, 410-413`; `lib/route.js:389-403, 526-607, 651-666`;
  `lib/handle-request.js:24-209`; `lib/reply.js:156-214, 959-1016`;
  `lib/error-handler.js:30-132`; `lib/plugin-override.js:28-74`.
- bullmq: `src/classes/backoffs.ts:11-81`; `src/classes/job.ts:652-821,
  1181-1254`; `src/classes/lock-manager.ts:46-127`;
  `src/commands/moveStalledJobsToWait-9.lua:44-120`;
  `src/commands/moveToFinished-14.lua:95-205`;
  `src/commands/includes/promoteDelayedJobs.lua:16-43`;
  `src/classes/worker.ts:612-1140, 1422-1537`.
- PULSE: `src/server.xi` (ladder, stages' current sites); `src/reqctx.xi`;
  `src/envelope.xi`; `src/validate.xi`; `tests/test_http.xi`,
  `tests/test_app.xi`, `scripts/http_smoke.*` (order pins).
