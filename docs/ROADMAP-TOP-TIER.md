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
- **T8 Platforms/legacy.** linux-x64 + windows (have) + **linux-arm64
  native CI + release dry-run (2026-10-21)** + **macOS witness (2026-10-21,
  non-gating: `macos-14` + `macos-15-intel`)**; HTTP/1.0-class clients and
  `Connection` semantics; JSONL
  no-DB deployments stay first-class; Windows x64 production template.
- **T9 Proof.** Published benchmark report (bttger six endpoints +
  xlcaptain scenarios), an LB scaling curve, soak stability, and the
  restore drill -- all with evidence under `probe-logs/`.

A release is "top-tier" when T1-T9 hold with evidence, including one
full public deployment topology: edge (TLS/h2/gzip) -> N workers ->
shared store.

## 2. Standing today (0.2.1, 2026-10-15)

> **Updated 2026-11-02:** current release is **0.2.2** on compiler **v0.65.5**
> + stdlib 88f3c12; all five platforms (linux-x64/arm64, windows-x64,
> macOS x64/arm64) gate and package; the per-request floor is **16.5 KB**.
> The plan derived from the Restack application is in **section 10**.

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
edge-terminated; real brotli + zstd + dynamic-Huffman gzip [S/P --
brotli 0.1.0 landed at bindings, scope live; zstd 0.3.0 real];
response-compression unit + precompressed-static sidecars [Q].

**W3 Legacy & platform.** HTTP/1.0 + `Connection` semantics via the
keep-alive design (MUST_CLOSE path) [Q]; JSONL no-DB first-class [Q,
already default]; **linux-arm64 native CI leg [done 2026-10-21; arm64
release dry-run verified; next tag ships it]**; Windows x64 production template [O]; **macOS CI
witness added 2026-10-21 (`macos-14` + `macos-15-intel`; x64 green with
stdlib 05673f8 pre-pin, arm64 pending the compiler IR fix, Windows inline
payload index separate); release legs remain Q
behind `RELEASE_BUILD_MACOS`**; edge TLS-version/cipher floors for old
clients [O, documented].

**W4 Realtime.** SSE unit [Q, **done 2026-10-20**: chunked
`text/event-stream` takeover + `/api/sse` demo]; WebSocket unit [Q,
**done 2026-10-20**: 101 + masked frame loop + `/api/ws` echo], with
user-supplied stream handlers (patch `29dbd25` held until the v0.65.0
production pin; v0.64.9 is withdrawn), permessage-deflate and `wss://`
(after W2 TLS) as follow-ups
(fragmentation landed 2026-10-20); jobs core [Q, designed].

**W5 Data.** SQL migrations runner + pooling [Q; driver co-verified
24/24]; durability Phase A/B incl. `fsync_dir` publish ordering [Q,
designed]; PITR-style backups + restore drill [Q/O]; store seam stays
the single external touch.

**W6 Security.** per-route rate policy [Q, **done 2026-10-19**];
per-key policy [Q, after the peer-address primitive (S)]; OIDC/OAuth
surface [P]; native TLS [S, see W2]; secrets + rotation guidance [Q doc];
existing headers/audit/smuggling hardening stay locked.

**W7 Static / CDN-grade.** conditional GET (ETag/Last-Modified) + Range
in site/assets mode [Q]; precompressed sidecars + negotiation [Q over
S/P codecs]; immutable-asset guidance (hashed filenames) [docs/O].

**W8 DX.** HTML templates + escaping v0 [P delivered:
`xiom.template 0.2.0` live; Q consumer-verify queued]; test-runner
harness [Q, fn-ptr fixed]; OpenAPI `paths` generation (retire the
hand-written block) [Q]; CLI growth (`--workers`, `openapi --check`
exists).

**W9 Observability.** tracing decision + OTLP export [Q decision open;
P package delivered -- `xiom.otel 0.1.0` live]; metrics/logs/rid stay
locked; profiling hooks [S, phase 2].

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

**Lane replies folded (2026-10-16, post-wrap-18):** the packages
`-2202-pulse-3` slate is COMPLETE -- `xiom.template 0.2.0` LIVE
(eco-v0.1.186; consumer-verify 15/15 x2), `xiom.ssl 0.1.0` LIVE
(eco-v0.1.189; the TLS headline is closed on the packages path;
consumer-verify 14/14 live x2 + 4/4 SKIP x2),
`xiom.brotli 0.1.0` LIVE (eco-v0.1.189; consumer-verify 11/11 x2),
`xiom.otel 0.1.0` LIVE
(eco-v0.1.188; OTLP core), `xiom.zstd 0.3.0` real (vendored 1.5.7).
**`xiom.pulse` (Beacon) extraction GREEN + IN-TREE** (`053cab87`;
125/125 x2 on the pin; PULSE co-verify: all PROVENANCE hashes match at
`56eb9f8`, the verbatim pairs byte-identical) -- ops scope asked,
publish path next (`REL-20261016-1515/-1516-packages`). The remaining
top-tier delta sits with stdlib (`-2202-pulse`; TLS/ALPN), compiler
(`-2202-pulse-2`) and ops (`-2202-pulse-4`).

**2026-10-22 retention isolation (supersedes the JSON-only reading):**
the per-request RSS growth is compiler-owned and hits the plain serving
path. On v0.64.8 + stdlib tag `aa8b656` (Windows x64), the product
`pulse_app` retains **55-60 KB per `GET /health`** (keep-alive and
connection-per-request alike); bttger retains 39 KB for a 13-byte
response, 89-96 KB for `POST /insert`, and **1.14 MB** for
`GET /serialize/big`. Standalone bisect: Vec 139 B, Map 289 B, Str 47 B
per iteration, but a one-field JSON build+stringify is 2,152 B and a
trivial `json_type` on the same value is 1,885 B -- by-value
`JsonValue` copies amplify the missing-drop-glue class (m375). The HTTP
floor is the per-read 64 KiB `socket_recv` Vec. Evidence:
`scripts/post_retention_probe.ps1`,
`tests/probes/probe_alloc_aggregate.xi`,
`probe-logs/post-retention-20261022.log`. Bus: compiler
`REL-20261010-1549-pulse-4` (v0.65.0 P0 ask + acceptance), stdlib
`REL-20261020-1704-pulse` (reference-API ask) and new stdlib
`REL-20261022-2049-pulse` (`socket_recv_into` reuse). This is a
production gate for sustained load, including the 0.3.0 decision.

## 8. Proof discipline

Every milestone ships with: full sweeps on both platforms (fleet, suites
x2, smoke jsonl+kv), updated evidence under `probe-logs/`, bus updates
on every lane ask, and the SESSION.md digest + PROGRESS delta. The
benchmark report is the public-facing proof of the T9 gate; the LB
scaling curve is the proof of T2.

## 9. Product split: PULSE Beacon (embeddable) + PULSE Station (hosted)

Owner directive (2026-10-16): everything stays **PULSE**; codenames
distinguish the two tiers, matching the ecosystem pattern (orbitdb
satellite/station, xvector mote/lattice; codename convention
`REL-20261016-1446-packages`): **tier 1 = the registry tier** (**PULSE
Beacon**, the embeddable `xiom.pulse` package), **tier 2 = the standalone
tier** (**PULSE Station**, the hosted product) -- one core,
usage-separated; some integrate it into their app (Beacon), others host it
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
   and its own CI -- **IN FLIGHT (2026-10-16)**: the packages porter is
   carving the frozen pair `56eb9f8` into `packages/xiom-pulse`
   (`REL-20261016-1429-packages`; verbatim carve, `xiom.std` only,
   0.1.0, hardening fixtures carry over). Stages relay as they land.
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
## 10. PULSE 1.0 plan (derived from the Restack application, 2026-11-02)

The Restack application lives outside the repository and is not edited from
here. This section is the in-repo execution plan: the same work packages,
milestones and acceptance criteria, with the current status. It is scoped to
**PULSE 1.0** (the product), not to the whole XIOM stack.

**Shape:** 12 months, 760 hours, four bounded outcomes plus project
management. The 1.0 release is a finishing plan on the shipped 0.2.x line,
not a rewrite.

| Work package | Hours | Deliverable and acceptance | Status 2026-11-02 |
|---|---:|---|---|
| WP1 -- memory and sustained-load reliability | 220 | Upstream reclamation fixes with repros + app-path allocation cuts; CI retention gate; **24 h at 100 req/s on the bttger mix with RSS <= 256 MB**, published baseline; 72 h confirmation | Partial: floor is **16.5 KB/req** (from 46); response builder flat, per-connection buffer in place; 24 h/1M gate still open |
| WP2 -- security and release integrity | 160 | Fixed-scope review in month 7 (Ã¢â€šÂ¬3,000), months 8-10 remediation; parser/multipart fuzzing; SBOM (CycloneDX/SPDX); SHA-pinned artifacts + provenance; reproducible-build recipe; disclosure policy + CVE process | Partial: SHA256SUMS + provenance; fuzz gate + disclosure/CVE policy; CycloneDX SBOM with registry hashes + release attach; reproducible recipe + audit scope docs. Still open: the external review itself and a cross-host/zip reproducible gate |
| WP3 -- external adoption and operational proof | 180 | One external public-interest pilot (bounded, not a migration); operator guide, migration guide, one-command scaffold; benchmark report; 72 h soak; final public report (CC BY 4.0) | Partial: internal dogfooding only (pulse.xiom-lang.org); benchmark report published 2026-11-01; guides partial; no external pilot |
| WP4 -- scale-out foundation | 160 | Process supervisor + --workers N; SO_REUSEPORT (Linux), N ports (Windows); graceful drain; zero-downtime reload; proxy-trust unit; 1/2-worker scaling curve; rollback procedure | Not started: the single-accept loop is the measured ceiling (10 connections add no throughput) |
| WP5 -- project management and dissemination | 40 | Monthly public notes; issue triage; release coordination; final report; one remote community presentation | Ongoing: changelog, relay, progress and benchmark reports |

### Milestones

- **M1 (month 3):** memory harness + CI gate; 24 h soak baseline published;
  compiler/stdlib fixes with repros; security review scope fixed; pilot
  candidate identified.
- **M2 (month 6):** memory budget met in CI; supervisor/drain prototype;
  edge-TLS deployment template; benchmark harness; pilot integration plan.
- **M3 (month 9):** security review complete; remediation underway; 2-worker
  scaling curve; external pilot deployed; 72 h soak at the WP1 workload.
- **M4 (month 12):** PULSE 1.0 release; SBOM + reproducible artifacts;
  benchmark report; operator and migration guides; final public report.

### Scope boundary

**1.0:** memory budget + retention gate; review + remediation + fuzzing +
SBOM + reproducible release + disclosure policy; one external pilot;
supervisor/drain/reload + 1/2-worker curve; all five release platforms
(linux-x64, linux-arm64, windows-x64, macOS x64, macOS arm64).

**Post-1.0:** native TLS (xiom.ssl) and certificate reload; HTTP/2 and
HTTP/3 at the edge; response/WebSocket compression; shared-state stateless
mode; 4+ workers; richer SQL drivers; OIDC/OAuth; distributed tracing.

### How it maps to the rest of this roadmap

- WP1 closes the production blocker in section 6/7 and is the gate for the
  capped bttger 5k/1M run.
- WP2 is the proof-discipline item in section 8.
- WP4 is the W1 scale-out gap; until it lands, throughput claims are bounded
  by the single-accept loop.
- The parity program (docs/PARITY-VISION.md, docs/PARITY-MATRIX.md) is
  the capability scorecard; the 1.0 scope targets its P0 gaps.
- Release 0.3.0 is the next product tag; 1.0 follows the four outcomes above.
## 11. Backlog: game backend profile (agreed 2026-11-04)

The owner's question ("can PULSE host XIOM Engine multiplayer games?") has a
clear split, recorded in docs/GAME-BACKEND-POSITIONING.md: **PULSE is the
game backend and dedicated-server control plane; XIOM Engine owns the tick
path.** This is the same split Nakama/PlayFab/GameLift use. The backlog below
turns that into a product profile without turning PULSE into a game server.

**Shipped today (do not rebuild):** /api/game/* (server register with
build/protocol/map/mode/capacity/region, per-server bearer, config revision,
heartbeat with drain/shutdown commands, config feed by revision/ETag, compat,
match report, telemetry, ops-gated admin state), sessions/JWT/CSRF/CORS/rate/
idempotency/event store/audit/metrics/OpenAPI, WebSocket text+binary with
fragmentation and stream auth, SSE, and the five-platform binary.

**Backlog, in priority order:**

1. **GAME-BACKEND v2 positioning note** -- refresh the 2026-10-13 note with
   the shipped WS/SSE/control-plane state and this backlog. Documentation
   only; no code.
2. **Game backend profile** -- a pulse game scaffold/template set covering
   lobby metadata, matchmaking queues (metadata), leaderboards, telemetry
   ingest and receipts, built on PULSE 1.0. Acceptance: one turn-based/lobby
   pilot, a 24 h soak at its real rate, and an operator guide page.
3. **Jobs/queues** -- matchmaking pools, retry/backoff for webhook and match
   report delivery, pruning. Blocked on the jobs layer (designed, not
   shipped); Phase 3.
4. **Workers + shared lobby state** -- supervisor/drain (WP4) plus sticky
   routing or a shared store for lobby affinity. Sessions are in-process
   today; multi-node needs one of the two.
5. **Dedicated-server allocator** -- allocate/spawn/drain/capacity and region
   placement. Register/heartbeat/drain exist; the allocator is a separate
   post-1.0 service (Agones-like), not a core framework feature.
6. **Connection hygiene** -- per-IP connection caps and a separate rate
   policy for telemetry/auth routes (per-route rate already exists).
7. **Later, engine-side** -- UDP/QUIC/WebTransport transport and an optional
   relay binary; WebTransport at the edge. Engine lane owns it.

**Non-goals:** tick simulation, prediction/rollback, lag compensation, NAT
traversal, voice, and a built-in load balancer. The edge (nginx/Caddy) owns
LB; PULSE adds workers and SO_REUSEPORT, not an L4/L7 balancer. Do not claim
"first" game backend: Nakama, PlayFab, GameLift, Agones and Steamworks exist;
the differentiator is a small native backend + control plane for XIOM Engine
with a verifiable supply chain.
## 12. Backlog: multi-page site server (2026-11-06)

**What is already shipped (static multi-page):** PULSE_SITE_DIR site mode
serves a directory tree with / -> index.html, clean URLs
(/about -> about.html), directory index (/sub/ -> sub/index.html),
a 301 from /sub to /sub/ (query preserved), a custom 404.html, asset
MIME types (JS/WASM), ETag/304, Cache-Control, a traversal guard and a single
Content-Length. A static multi-page site works today; 	tests/test_app.xi
covers it.

**Dynamic site status (2026-11-06):**

1. **Templating / SSR** (P1, parity row W-13): layouts, partials, loops,
   conditionals, auto-escaping. `xiom.template` 0.2.0 (signed registry
   package) is delivered and consumer-verified; it has sections, loops,
   inverted sections, dotted paths and auto-escaping, but no partials.
   `examples/site/` composes a shared layout and partials by fragment
   injection. **First slice shipped**; see `docs/SITE-SERVER.md`.
2. **`application/x-www-form-urlencoded` parsing** (P1, R-09): HTML forms.
   `xiom.pulse.urlenc` is the shared decoder (query + form) with
   `form_is_urlencoded`, `parse_form`, `parse_pairs` and `form_value`;
   covered by `tests/test_app.xi` and the site smoke. **Shipped.**
3. **HTML escaping helpers** (P0 for safety): `xiom.pulse.html.html_escape`
   (`& < > " '`) for handlers; templates auto-escape the same set. **Shipped.**
4. **Compression** (P1, P-15): gzip/brotli for HTML/CSS/JS; large pages and
   assets benefit most. **Not implemented in-process** (the edge `encode`
   covers deployments today).
5. **Dynamic caching/revalidation** (P1, D-10): cache keys, TTL, ETag for
   rendered pages. **Not implemented.**
6. **Site ergonomics** (P2): redirects, canonical URLs, robots/sitemap, i18n,
   a dev reload loop (O-10). **Not implemented.**
7. **Edge story**: TLS and HTTP/2 stay at nginx/Caddy; the template is in
   `docs/DEPLOYMENT.md`, and `docs/SITE-SERVER.md` adds the site shape.
   **Documented.**

**Phased path and status:**

- **A. Static site profile (done):** site mode is documented (README,
  `docs/DEPLOYMENT.md`, `docs/SITE-SERVER.md`) and `examples/site/` is the
  runnable scaffold with a shared layout, assets and a custom 404. The
  static half is covered by `tests/test_app.xi`.
- **B. Dynamic site (first slice shipped):** `xiom.template` for
  layouts/loops/conditionals/auto-escaping, `xiom.pulse.urlenc` for forms,
  `xiom.pulse.html` for handler escaping, and a 6-page Beacon scaffold
  (`examples/site/`) with one POST form, a 404, assets and a smoke
  (`scripts/site_smoke.ps1`/`.sh`). The unit tests are in
  `tests/test_app.xi`. Remaining polish: template caching at startup,
  richer form helpers, and a Station-native template route if the product
  needs one.
- **C. Production site (next):** compression, dynamic caching,
  i18n/redirects; then the 24 h memory/soak gate on the site workload.
  HTTP/2/3 at the edge.

**Non-goals:** a full CMS, admin panel, WYSIWYG editor, e-commerce. Those are
ecosystem packages on top of the site profile, not framework core.