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

## Adopt backlog (PULSE-side, version-ordered)

- [0.3.x] **Keep-alive/deadlines design doc** using the h11 checklist;
  pairs with the stdlib socket-timeout/deadline bus asks.
- [0.3.x] **Store durability design**: bbolt ordering discipline for the
  store seam + backup story; pairs with the `fsync` bus ask and the
  orbitdb driver unit.
- [0.4] **Middleware chain** (gin pattern) + recovery guard + context
  reset discipline; precompute chains at registration.
- Watch: when upstream threads land, gin-style pooling becomes directly
  applicable.
