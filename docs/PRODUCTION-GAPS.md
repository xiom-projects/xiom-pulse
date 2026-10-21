<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE production-grade gap analysis + cross-lane requirements relay

Status: 2026-10-12, PULSE session (owner request: "what PULSE needs to be
a full production-grade backend framework in the league of top
webframeworks"). Companion to the designs in this repo and the
reference shelf (`E:\repos\`: fastify, gin, fasthttp, h11, helmet,
bbolt, knex, bullmq; nginx terminates TLS in the target deployment).

**Status update 2026-10-15:** the wave-2 asks in section 2.1 are all
delivered and reporter-verified; the current plan (top-tier directive,
capability truth table, milestones, lane asks) lives in
`docs/ROADMAP-TOP-TIER.md`.

## 0. Where PULSE is today (0.2.x on main)

Shipped and CI-green (v0.64.3 toolchain + stdlib pin `3df0843`):
HTTP/1.1 core with smuggling hardening, chunked decoding, multipart
uploads, static + site mode, OpenAPI 3.1 served + drift-guarded,
`/v1` alias, pagination, idempotency keys, JWT HS256, sessions, CSRF,
CORS, global token-bucket rate limit, envelope errors, schema
validation, helmet-derived security headers (CSP opt-in), metrics,
audit, structured access log, request ids, outbound client with SSRF
guard, store seam (jsonl/kv) with torn-tail healing + backups, release
machinery (DCO, rulesets, dl mirror, ops runbooks). x64 linux+windows;
macOS gated.

Not yet production-grade for real products. Two classes of gaps:
**(A) lane-owned primitives** (stdlib/compiler/packages) and
**(B) PULSE-owned units**. Both listed below with owners.

## 1. Parity matrix vs the reference shelf

Legend: ✅ shipped · 🟡 designed/partial · ❌ missing.
Owner: S=stdlib, C=compiler, P=packages, Q=PULSE, O=ops.

| # | Capability (top-league reference) | PULSE | Owner / ask |
|---|---|---|---|
| 1 | HTTP/1.1 parsing, smuggling hardening (h11) | ✅ | -- |
| 2 | Keep-alive + pipelining, MUST_CLOSE semantics (h11) | 🟡 designed `docs/DESIGN-KEEPALIVE-DEADLINES.md` | S: deadlines (`0317-pulse`, `-2`); Q: impl |
| 3 | Named read/write/idle timeouts; 408 vs silent close (fasthttp) | 🟡 designed | S same; Q impl |
| 4 | Graceful shutdown + in-flight drain (gin/fastify `close()`) | ❌ | **S: signals (SIGTERM/SIGINT) + drain hooks (new)** |
| 5 | Fair accept: accept timeout, poll/select; multi-process scale via `SO_REUSEPORT` (fasthttp workers, nginx upstream) | ❌ | **S: poll/select + accept deadline + SO_REUSEPORT (new)** |
| 6 | Half-close + `shutdown(fd)` control (h11) | ❌ | S: `shutdown` is in the `0317-pulse` ask; needs landing |
| 7 | Static: conditional GET (ETag/If-None-Match, Last-Modified) + Range requests (fastify-static, nginx) | ❌ | Q (no lane dependency) |
| 8 | Response compression gzip/deflate (fastify-compress; nginx alt) | ❌ | **S: gzip/deflate primitives (new)**; O may front with nginx |
| 9 | Streaming responses / SSE / chunked out (fastify, h11) | ✅ | SSE connection unit + chunked server writer + `/api/sse` demo (`docs/DESIGN-SSE-WEBSOCKET.md`); startup stream registry + routes CLI + per-route rate landed; user stream handlers Q |
| 10 | WebSockets (fastify-ws, gin) | ✅ | 101 handshake + server frame loop + `/api/ws` echo; same-origin/CORS Origin policy; masking/ping/close/fragmentation/limits covered; auth, permessage-deflate + `wss://` (edge TLS) still Q |
| 11 | Multipart uploads (fastify-multipart) | ✅ | -- |
| 12 | Cookies/sessions (fastify-cookie/session; registry pkgs) | ✅ | -- |
| 13 | JWT auth (fastify-jwt) | ✅ | -- |
| 14 | CSRF (csrf-csrf etc.) | ✅ | -- |
| 15 | CORS (fastify-cors) | ✅ | -- |
| 16 | Rate limiting (fastify-rate-limit) | 🟡 global + per-route buckets | Q: per-key after the peer-address primitive |
| 17 | Security headers (helmet) | ✅ | -- |
| 18 | OpenAPI: serve + drift guard (fastify-swagger) | 🟡 served + guarded | Q: generate `paths` from the route table; retire hand-written block |
| 19 | Schema validation (fastify schema, pydantic) | ✅ | -- |
| 20 | Middleware/hooks chain (fastify hooks, gin chain) | 🟡 designed `docs/DESIGN-MIDDLEWARE-JOBS.md` | Q: impl (order tests first) |
| 21 | Background jobs: retries/backoff/delayed/stalled (bullmq) | 🟡 designed | Q: impl (no lane gate; loop-boundary runner) |
| 22 | Durable acks: commit ordering, fsync-before-2xx, rename publish (bbolt) | 🟡 designed `docs/DESIGN-STORE-DURABILITY.md` | S: shared fsync bundle (`0317-pulse-5/-6`, `1134-pulse` fsync_dir, `1550-orbitdb-3/4/7`, `1550-xvector-2`, `1550-packages`); Q impl |
| 23 | SQL class + migrations, runner contract (knex) | 🟡 designed `docs/DESIGN-SQL-MIGRATIONS.md` | **P: SQL driver (vendored sqlite first; `1548-bindings-11` hook); new priority item** |
| 24 | Backup/snapshot with point-in-time semantics (bbolt WriteTo) | 🟡 scripts + fence design | Q impl with #22 |
| 25 | Observability: metrics/logs/health/rid | ✅ | -- |
| 26 | Distributed tracing (OTel in top stacks) | ❌ | optional; no lane gate (decide later) |
| 27 | Multi-worker operation (K processes behind nginx) | ❌ | S: `SO_REUSEPORT` (#5); O: unit/systemd template |
| 28 | Outbound HTTP client with guard (undici/axios class) | ✅ | -- |
| 29 | Platform parity | ✅ linux-x64/win + linux-arm64 + macOS CI witness | C: macOS release assets (`1609-pulse`, `-2`); arm64 release asset Q |
| 30 | Toolchain reliability for adoption | 🟡 v0.64.4 held | C: kv-mode exit-0 (`REL-20261012-1418-pulse`); SIGILL (`1615`) gates 0.2.1 |

## 2. Lane asks (self-contained)

### 2.1 stdlib -- "production server primitives, wave 2"

**Status update 2026-10-13:** the critical path is DONE -- deadlines,
socket options, fsync family and fsync_dir all fixed and reporter-verified
(closed: `0317-pulse`, `-2`, `-5`, `-6`, `1134-pulse`). Wave 121 landed
the WebSocket helpers + chunked/stream writers + `send_all`; wave 122
landed `socket_poll_read/write` + `socket_set_reuseport`. **Only signal
delivery remains.** Triage additionally resolved two asks pre-emptively:
`json_parse` is linear since wave 111 (byte-lexer), and gzip/deflate
already exist in `xiom.compress`. Runtime rows are effective at the next
re-vendoring pin (`XIOM_RUNTIME_DIR` interim on v0.64.4).

Existing asks stay as filed (`0317-pulse`, `-2`, `-5`, `-6`, `1131`,
`1134`, orbitdb/xvector/packages fsync bundle). NEW asks from this
analysis:

1. **Signals**: deliver SIGTERM/SIGINT to the process (handler or
   subscribe) so a server can finish the in-flight request, stop
   accepting, flush, exit 0. (Graceful drain; #4.)
2. **Readiness/poll primitives**: `select`/`poll` over sockets with a
   timeout -- enables accept deadlines, idle waits without SO_RCVTIMEO
   stickiness, and future multi-fd service loops. If poll is out of
   scope short-term, an accept-timeout wrapper is the minimum. (#5.)
3. **`SO_REUSEPORT`** (Linux) for multi-process scale-out; document the
   Windows story (no equivalent -- N ports + nginx upstream). (#27.)
4. **Response streaming**: a chunked-transfer writer primitive
   (`write_chunk`/`end_chunks`) plus raw stream send; SSE is then a
   PULSE unit on top. Without this, long-poll/SSE/LLM-style streaming
   endpoints are impossible. (#9.)
5. **WebSocket primitives**: upgrade handshake accept (compute
   Sec-WebSocket-Accept), frame encode/decode incl. masking, close
   codes. PULSE builds the route/API layer. (#10.)
6. **gzip/deflate** compress/decompress primitives. -- **RESOLVED
   upstream**: `xiom.compress` already ships roundtrip + interop; no
   ask; a PULSE response-compression unit is optional (nginx fronts).
7. **`json_parse` performance**: -- **RESOLVED upstream**: linear
   since wave 111 (byte-lexer; the xvector acceptance closed
   `REL-20261011-1453`). Keep as a benchmark watch only.
8. Confirm `shutdown(fd)` lands with the `0317-pulse` socket-options
   batch (half-close correctness).
9. Note (already filed elsewhere): durable `flush_stdout`, `fsync`,
   `fsync_dir`, held append handle -- the durability bundle.

Interface sketches (for discussion, not mandates): signal subscribe
callback or `os.signal_wait(timeout_ms)`; `net.poll(fds, timeout_ms) ->
Vec[Int]`; `socket_set_reuseport(fd)`; `stream_begin_chunked(fd)`,
`stream_chunk(fd, bytes)`, `stream_end(fd)`; `ws_accept_key(key)`,
`ws_encode_frame(opcode, payload, mask)`, `ws_decode_frame(buf)`.

### 2.2 compiler

No new asks from this analysis; the existing gates cover production
adoption: **`1615` SIGILL** (0.2.1 + ops redeploy), **`1609-pulse` +
`-pulse-2`** (macOS), **`REL-20261012-1418-pulse`** (kv-mode exit-0
under v0.64.4 -- the toolchain-adoption blocker). Context: the stdlib
lane's fresh v0.64.4 red evidence (poisoning discriminator) suggests
v0.64.4 needs one more hardening pass before PULSE (and likely other
apps) can adopt it.

### 2.3 packages

1. **SQL driver priority**: `docs/DESIGN-SQL-MIGRATIONS.md` fixes the
   runner contract; the missing piece is a driver package. Vendored
   sqlite is the first target (`REL-20261010-1548-bindings-11`
   build-hook). Needed by real products for relational storage;
   without it the SQL class stays designed-not-shipped. (#23.)
2. **Compression package** (if gzip primitives land in stdlib, a thin
   middleware-shaped package is optional; skip if redundant).
3. **HTML templates + escaping**: `escape_html`, minimal template
   render (or a package). Server-rendered pages are a top-league
   baseline; PULSE currently returns JSON/bytes only. (#: new row.)
4. Keep the existing registry-pinned set healthy (the shared store
   wipe is resolved operationally; ops added the snapshot tool).

### 2.4 ops

1. Multi-worker unit template (N processes, SO_REUSEPORT or N ports +
   nginx upstream) once #5/#27 land.
2. Restore runbook exercise: backups are only production-grade once a
   restore has been rehearsed; the fence manifest (#24) gives the
   checklist.

## 3. PULSE-internal backlog additions (no lane gate)

Ordered by dependency-readiness:

1. **Static: conditional GET (ETag/Last-Modified) + Range** in
   site/assets mode (#7).
2. **Middleware chain refactor** + the order tests designed in
   `docs/DESIGN-MIDDLEWARE-JOBS.md` (#20).
3. **Jobs core** per the same design (#21).
4. **Keep-alive Phase B** immediately after stdlib deadlines (#2/#3).
5. **Durability Phase A/B** as the fsync bundle lands (#22/#24).
6. **OpenAPI `paths` generation** (finish the partial item) (#18).
7. **Per-route rate policy** (#16).
8. **SSE unit** (after streaming primitives) + **WebSocket unit**
   (after WS primitives) (#9/#10).
9. **Test-runner harness** using the now-fixed module-scope fn-ptr
   (`0317-pulse-7`) to replace manual check unrolling.
10. Optional: tracing decision (#26).

## 4. Definition of "production-grade" for PULSE

A real product can deploy PULSE as the only app server (nginx for
TLS/gzip edges) when ALL of these hold:

- One stuck client cannot stall the server (deadlines) and one process
  cannot lose acknowledged writes (fsync-before-ack + publish order).
- Connections are reused (keep-alive) and scale horizontally
  (multi-worker), with graceful restarts/upgrades (drain).
- The contract (OpenAPI) is generated, guarded, and versioned; the app
  layer has a middleware chain and durable background jobs.
- Relational storage is available (driver + migrations) with tested
  restore paths.
- Streaming (SSE) and WebSockets are available for realtime products.
- The toolchain it ships on is stable (no held adoptions) and the
  platform matrix is at least linux+windows(+macOS).

Today: 12/30 matrix rows fully green; 10 designed and gated on lanes;
8 missing (see the matrix). The lane asks in section 2 unblock most of
the designed ones; the rest are PULSE units.

## 5. Sequencing

1. **stdlib wave 2** (deadlines first; then accepted primitives) +
   **compiler gates** (1615 for 0.2.1; kv for toolchain adoption) --
   both in other lanes' hands; PULSE implements keep-alive Phase A and
   durability Phase A the week each lands.
2. **packages SQL driver** (parallel track).
3. PULSE-internal units in dependency order (section 3).
4. Re-run the full wave sweep + release checklist at each adoption.
