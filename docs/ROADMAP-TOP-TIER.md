<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE top-tier roadmap: the #1-class goal

**Owner directive (2026-10-15):** PULSE is the multi-purpose full backend
framework -- any site (static or not), any app, APIs, realtime,
**load-balanced scale-out with the edge tier integrated and supported**,
safe / fast / secure, **modern AND legacy**. This document is the
standing map from today's baseline to that goal: acceptance criteria,
current capability truth, workstreams, milestones, and the lane-owned
roadblocks (filed on the relay bus 2026-10-15).

Companions: `docs/PRODUCTION-GAPS.md` (the 2026-10-12 baseline analysis
-- its wave-2 asks are all delivered; this doc supersedes it as the
current plan), `docs/FRAMEWORK-ROADMAP-PULSE.md` (milestone history),
`docs/PRODUCTION-REFERENCES.md` (adopt backlog), and the designs
(`docs/DESIGN-*.md`).

## 1. What "top-tier" means (acceptance criteria)

- **T1 Protocols.** HTTP/1.1 hardened (have) + keep-alive/pipelining
  (design ready) + HTTP/2 (edge-terminated first, native via TLS+ALPN
  next) + H3 via edge; WebSockets + SSE; gzip + RFC-7932 brotli + zstd
  with precompressed static sidecars and `Accept-Encoding` negotiation.
- **T2 Scale-out.** Multi-worker operation (K processes + supervisor,
  SO_REUSEPORT or N ports), zero-downtime reload/upgrade with drain,
  LB-first deployment (nginx upstream + a documented proxy-trust unit),
  and a stateless-app mode (shared sessions/rate/idempotency) so plain
  round-robin balancing works without stickiness.
- **T3 Safety/durability.** fsync-before-ack commit ordering, published
  renames, PITR-style backups with a rehearsed restore.
- **T4 Security.** Full header set + CSP (have), per-route/per-key rate
  policy, JWT (have) + OIDC-capable path, TLS (edge now; native later),
  smuggling hardening (have), signed dependencies (registry).
- **T5 Data.** SQL + migrations + connection pooling (driver
  co-verified; runner next), KV (have), store seam (have).
- **T6 DX.** HTML templates/SSR, test-runner harness, OpenAPI generated
  from the route table, CLI (have + extend).
- **T7 Observability.** metrics/logs/rid (have) + tracing (OTel)
  decision + export.
- **T8 Platforms/legacy.** linux + windows (have) + macOS (v0.64.6
  pair); HTTP/1.0-class clients and `Connection` semantics; JSONL
  no-DB deployments stay first-class; Windows x64 production template.
- **T9 Proof.** Published benchmark report (bttger six endpoints +
  xlcaptain scenarios), an LB scaling curve, soak stability, and the
  restore drill -- all with evidence under `probe-logs/`.

A release is "top-tier" when T1-T9 hold with evidence, including one
full public deployment topology: edge (TLS/h2/gzip) -> N workers ->
shared store.

## 2. Standing today (0.2.1, 2026-10-15)

- **0.2.1 shipped** on the v0.64.5 toolchain + stdlib pin `092dfa0c`
  (SIGILL fix included): HTTP/1.1 core with smuggling hardening, chunked
  decoding, multipart uploads, static + site mode, OpenAPI 3.1 +
  drift guard + `--check`, `/v1` alias, pagination, idempotency keys,
  JWT HS256, sessions, CSRF, CORS, global rate limit, envelope errors,
  schema validation, security headers (CSP opt-in), metrics, audit,
  access log + rids, SSRF-guarded outbound client, store seam
  (jsonl/kv) + backups, game control plane `/api/game/*`, release
  machinery (DCO, rulesets, dl mirror).
- **Upstream wave-2 primitives all delivered** (waves 119-123):
  deadlines, drain signals, `poll` + `SO_REUSEPORT`, chunked/stream
  writers, WebSocket helpers, fsync family incl. `fsync_dir`.
- **Measured:** ~55.4% production grade (docs/PROGRESS.md); wave-2 full
  sweep green on both platforms (fleet 12/12, suites x2, smoke 119/119
  jsonl+kv) -- the baseline is solid; the top-tier delta is what this
  doc maps.

## 3. Upstream capability truth table (inventoried 2026-10-15)

Truth from the actual trees (`E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`):

| Capability | State | Detail |
|---|---|---|
| TLS (server/client), ALPN | **none** | cert name/parse helpers only; `docs/TLS_DECISION.md` routes to a schannel/OpenSSL FFI binding |
| HTTP/2 / HPACK / h2 framing | **none** | the `smoke_net_http2.xi` test is misnamed (cookie/mime tests) |
| gzip / deflate / zlib | **real** | producer is fixed-Huffman only (weak ratios) |
| brotli | **non-RFC** | custom frame; `Content-Encoding: br` cannot be served |
| zstd | **none** | absent; planned FFI package only |
| sendfile / splice / writev | **stubs** | documented Err; no TransmitFile |
| file watch (inotify) | **Windows only** | POSIX path is a documented Err |
| process spawn | **partial** | blocking + shell-string; no pipes/popen; posix_spawn stubs |
| threads / threadpool | **simulated** | closures run inline; no OS threads |
| signals (SIGTERM/INT) | **yes** | poll-based `signal_wait`; callbacks unavailable |
| socket options | **partial** | REUSEADDR/REUSEPORT/timeout/nonblock/shutdown; **no TCP_NODELAY**; backlog hardcoded 128 |
| poll/select | **partial** | `socket_poll_read/write` (1024-fd cap, bounded waits); epoll/kqueue/IOCP/select are stubs |
| chunked/SSE/WebSocket | **yes** | wire formats + WS helpers real; SSE connection fns are stubs; `wss://` needs TLS |
| multipart / URL / HTML escape | **yes** | pure primitives; no template engine |
| ACME / systemd socket activation | **none** | LISTEN_FDS + `sd_notify` absent |

## 4. What the reference league ships (table stakes vs differentiators)

From the shelf (`E:\repos\`: fastify, gin, fasthttp, h11, helmet, bbolt,
knex, bullmq + the two benchmark suites):

- **Table stakes:** HTTP/1.1; edge deployment with proxy-trust headers
  (fastify `trustProxy`, gin `SetTrustedProxies`); gzip somewhere in the
  stack; static conditional GET; TLS at app or edge; structured logging;
  metrics as add-ons; stateless header-token sessions.
- **Differentiators:** in-framework scale-out -- fasthttp ships
  `prefork` (fd-passing/reuseport + child restart) and its static layer
  negotiates `br > zstd > gzip` with precompressed sidecars; native
  HTTP/2 -- fastify (h2+h2c), gin (h2c + HTTP/3 via quic-go); fasthttp
  native TLS + an autocert example; zero global state under prefork is
  the explicit scale-out rule (shared stores mandatory).
- **Absent league-wide** (handled by other tiers): sticky sessions,
  `Cache-Control: immutable` policy, cluster orchestration inside the
  framework.

## 5. Workstreams and gates

Owner tags: Q=PULSE unit, S=stdlib, C=compiler, P=packages, O=ops.

**W1 Runtime & scale-out.** keep-alive A/B [Q, **done 2026-10-16**];
worker supervisor + CLI (`--workers`) [Q] over S: spawn-with-pipes +
real threads or a blessed process model; TCP_NODELAY/backlog [S];
trust-proxy unit [Q]; drain/reload [Q over S signals (done)]; systemd +
nginx templates [O]; stateless mode: shared sessions/rate/idempotency
[Q, after W5].

**W2 Modern protocol.** TLS server+client + ALPN [S, the ceiling];
native h2 framing/HPACK [S scoping + Q unit] after TLS; h3 stays
edge-terminated; real brotli + zstd + dynamic-Huffman gzip [S/P];
response-compression unit + precompressed-static sidecars [Q].

**W3 Legacy & platform.** HTTP/1.0 + `Connection` semantics via the
keep-alive design (MUST_CLOSE path) [Q]; JSONL no-DB first-class [Q,
already default]; Windows x64 production template [O]; macOS legs
[C v0.64.6 pair, then Q re-test]; edge TLS-version/cipher floors for
old clients [O, documented].

**W4 Realtime.** SSE unit [Q] over S: SSE connection helpers
(completing stubs); WebSocket unit [Q] over the delivered WS helpers,
`wss://` after W2 TLS; jobs core [Q, designed].

**W5 Data.** SQL migrations runner + pooling [Q; driver co-verified
24/24]; durability Phase A/B incl. `fsync_dir` publish ordering [Q,
designed]; PITR-style backups + restore drill [Q/O]; store seam stays
the single external touch.

**W6 Security.** per-route/per-key rate policy [Q]; OIDC/OAuth surface
[P]; native TLS [S, see W2]; secrets + rotation guidance [Q doc];
existing headers/audit/smuggling hardening stay locked.

**W7 Static / CDN-grade.** conditional GET (ETag/Last-Modified) + Range
in site/assets mode [Q]; precompressed sidecars + negotiation [Q over
S/P codecs]; immutable-asset guidance (hashed filenames) [docs/O].

**W8 DX.** HTML templates + escaping v0 [P + Q wrapper]; test-runner
harness [Q, fn-ptr fixed]; OpenAPI `paths` generation (retire the
hand-written block) [Q]; CLI growth (`--workers`, `openapi --check`
exists).

**W9 Observability.** tracing decision + OTLP export [Q decision, P
package]; metrics/logs/rid stay locked; profiling hooks [S, phase 2].

**W10 Proof.** bench baseline on the six bttger endpoints
(`/serialize`, `/serialize/big`, `/plain/text`,
`/query/{userId}/tools/{offset}`, POST `/insert`, `/calculate`) with
autocannon (10 conns, 1M reqs; no pipelining by design) + the xlcaptain
scenarios (`/api/health`, GET/POST `/api/users`, k6 ramp + rate);
pre/post keep-alive curves; 1/2/4-worker scaling behind nginx;
soaks extended to the multi-worker topology; benchmark report
markdown in-repo.

## 6. Milestones

- **0.3 (data + realtime + static):** keep-alive A/B (**done
  2026-10-16**); durability A/B;
  middleware + jobs; SQL runner; SSE + WS units; static
  conditional/Range; bench baseline (pre-keep-alive numbers); templates
  v0 if the package lands.
- **0.4 (scale-out + edge integration):** multi-worker supervisor +
  systemd/nginx templates; trust-proxy unit; per-route rate; precompressed
  static; OTel decision; macOS legs live; 2-worker scaling evidence.
- **1.0 (top-tier gate):** native TLS + h2 via ALPN; real brotli/zstd;
  zero-copy static send; parity matrix >= 28/30 (PRODUCTION-GAPS
  legend); published benchmark report + LB scaling curve; restore drill
  executed; T1-T9 evidenced.

## 7. Roadblocks filed (2026-10-15, relay bus)

| Lane | Item | Ask headline |
|---|---|---|
| stdlib | `REL-20261015-2202-pulse` | 10-item scale/protocol plan; TLS/ALPN first |
| compiler | `REL-20261015-2202-pulse-2` | FFI hardening + `xiom-ffigen` C-headers (the TLS/h2 multiplier) + standing gates |
| packages | `REL-20261015-2202-pulse-3` | templates/escaping, TLS binding package, OTLP exporter, real brotli/zstd |
| ops | `REL-20261015-2202-pulse-4` | nginx h2/gzip/brotli edge template, multi-worker systemd template, restore drill |
| all | `REL-20261015-2202-pulse-5` | broadcast: directive + the headline finding |

The ceiling: **no TLS exists anywhere in-tree** today -- it gates native
HTTPS, `wss://`, h2-via-ALPN, and ACME. Everything downstream of it is
sequenced in W2/W4. Dismissed during this analysis: the apparent 2x
compile slowdown on v0.64.5 (controlled A/B: 117/68s vs 76/84s --
machine-state variance, no finding).

## 8. Proof discipline

Every milestone ships with: full sweeps on both platforms (fleet, suites
x2, smoke jsonl+kv), updated evidence under `probe-logs/`, bus updates
on every lane ask, and the SESSION.md digest + PROGRESS delta. The
benchmark report is the public-facing proof of the T9 gate; the LB
scaling curve is the proof of T2.

## 9. Product split: PULSE Beacon (embeddable) + PULSE Station (hosted)

Owner directive (2026-10-16): everything stays **PULSE**; codenames
distinguish the two usage editions, matching the ecosystem pattern
(orbitdb-satellite / orbitdb-station): one core, usage-separated
products -- some integrate it into their app (Beacon), others host it
on docker/kubernetes (Station).

- **PULSE Beacon** -- the embeddable edition: the light framework
  package on the registry (id `xiom.pulse`) that you add to an existing
  XIOM app -- routes, handlers, run-in-three-lines; engine control
  endpoints, playground workers, xvector services, docs tooling, user
  apps.
- **PULSE Station** -- the hosted edition: the full product we ship
  today (sessions, metrics, store, static, game CP, release machinery;
  docker/k8s deployment) -- what most people mean by "run PULSE".

(Working names considered: pulse-sails, pulse-satellite, pulse-sonde.
"Beacon" won: radio-native fit with "pulse", clean contrast with
"Station", and it stays distinct from the orbitdb pair while sharing
one ecosystem vocabulary.)

The rule that makes it work: **one protocol core, two editions -- never
a fork.** The core IS the engine: request parser + response builders +
connection loop (deadlines, keep-alive) + router + envelope. Beacon IS
that core as a package; Station imports it and adds the extras -- most
of which are already registry packages (`xiom.session`, `xiom.static`,
`xiom.kv`, `xiom.metrics`, `xiom.rate`, `xiom.http.middleware`,
`xiom.sqlite`).

Structurally this is ~80% ready today: the hard-won correctness
(smuggling hardening, TE/CL rules, chunked, 100-continue, site mode,
now the deadline/keep-alive core) already lives in separately-seamed
modules (`src/http.xi`, `src/router.xi`, `src/envelope.xi`,
`src/server.xi`). The Flask analogy is exact: Flask = Werkzeug
(protocol) + Jinja (templates) + WSGI (runner); here: `xiom.pulse`
(protocol + router + runner) + the templates package (wishlist filed)
+ the existing package set.

Sequence:

1. ~~Finish keep-alive Phase A + B~~ **DONE (2026-10-16)**: both phases
   landed and verified (smoke 134/134 x2 on both platforms) -- the
   core's connection semantics are frozen; the freeze gate is GREEN.
2. Extract `xiom.pulse` (the Beacon core) with a `minimal.xi` example
   and its own CI -- the NEXT step; the packages porter flow is armed
   (`REL-20261016-1108-pulse` acked, slot reserved).
3. The PULSE Station product consumes the package; the extras stay
   Station-side.
4. Publish via the packages lane; the registry reserves the name and
   sets up the read-path canary (`REL-20261013-1707` flow).

What Beacon is **not**: no sessions/metrics/store/static by default
(those become opt-in package composition). What it keeps: the full
protocol hardening -- the light path must never be the unsafe path.

Bus: publish/coordination ask `REL-20261016-1108-pulse` (packages;
acked -- `xiom.pulse` slot free, porter-flow scoping agreed at the
keep-alive A+B freeze); codename decision `REL-20261016-1121-pulse`.
