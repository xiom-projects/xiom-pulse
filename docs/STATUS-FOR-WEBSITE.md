# XIOM PULSE -- status for the website lane

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Last updated:** 2026-10-31 16:25Z (PULSE lane). **Source of truth:** this file for
website copy; `docs/PROGRESS.md` for the full tracker; `SESSION.md` for the
session handoff. README's status block predates the v0.65.1 adoption -- use
this file, not README, for the site until README is refreshed.

## One-paragraph summary

**XIOM PULSE** is the official XIOM full web backend: a plaintext HTTP/1.1
service written in XIOM, shipped as two tiers -- **PULSE Beacon** (tier 1,
the embeddable registry package `xiom.pulse`) and **PULSE Station** (tier 2,
the standalone product this repository ships, `pulse-v*` releases). It pairs
a hardened HTTP/1.1 core (smuggling rules, chunked bodies, 100-continue,
deadlines, keep-alive/pipelining) with sessions/CSRF, JWT, CORS, rate
limiting, metrics, jsonl/kv stores, static/site mode, multipart uploads,
SSE and WebSocket streams, and CLI tooling. TLS is deliberately terminated
by a front proxy; PULSE serves plaintext on loopback.

## Current release

- **Product:** PULSE **0.2.2** (tag `pulse-v0.2.2`), ops-accepted.
- **Toolchain pin:** compiler **v0.65.4** + **stdlib-v0.65.4**
  (`407c92d`). v0.64.9 is withdrawn; v0.65.0-0.65.2 are superseded
  (v0.65.2 had a durable-lane push regression and is not used).
- **Release cadence:** 0.3.0 is prepared but **not tagged** -- it waits on
  the owner's SQL-serving decision and on the memory work below.

## Platform support (be precise on the site)

| Platform | Status | Notes |
|---|---|---|
| linux-x64 | **supported** | gating CI leg |
| windows-x64 | **supported** | gating CI leg |
| macOS x64 | **supported** | gating CI leg |
| linux-arm64 | **preview / not shipped** | compiler chain + socket ABI are clear; blocked by the compiler lowering an **Int64 extern argument as i32** (`@fseek`; `REL-20261031-1619-pulse`). Witness leg, packaging held |
| macOS arm64 | **preview / not shipped** | same compiler arg-width bug; witness + packaging held |

Do **not** advertise arm64 as supported yet. The remaining gate is a
compiler fix for Int64 extern-argument width (`REL-20261031-1619-pulse`);
PULSE re-enables arm64 gating and packaging when it lands.

## Feature set (Station)

- Hardened **HTTP/1.1**: request smuggling rules (TE/CL), chunked decoding,
  `Expect: 100-continue`, header/body caps, read/write/idle deadlines,
  keep-alive with pipelining, correct 408/413/400/501 paths.
- **Router** + middleware chain, path params, per-route rate policy,
  OpenAPI document + JSON envelope errors.
- **Sessions** (cookie + store), **CSRF** tokens, **JWT HS256** issue/verify,
  **CORS** allowlist, **rate limiting** (global + per route).
- **Metrics** (Prometheus text: requests, latency, store gauge, uptime),
  access log + rotating audit log.
- **Stores**: jsonl (crash-safe append/heal) and kv backends; pagination,
  idempotency keys, compaction; 21 migrations; SQL driver co-verified
  (opt-in serving proposal in `docs/DESIGN-SQL-SERVING.md` -- not enabled
  in the stock app).
- **Static/site mode** with ETag/304 and traversal guard, multipart uploads.
- **Realtime**: SSE (chunked, tick helpers) and WebSocket (handshake,
  fragmentation, ping/pong, close, Origin policy) with **opt-in stream
  auth** (`PULSE_WS_AUTH=off|jwt|session`; JWT via Authorization,
  subprotocol carrier, or query string; tokens redacted from logs).
- **CLI**: `version`, `--check-config`, `routes`, `openapi`, plus `--serve`.

## Quality evidence (for badges / a "tested" section)

- Suites: **95 / 239 / 4** checks green (twice per gate).
- HTTP smoke: **135/135**, twice (jsonl + kv backends).
- Crash/durability: **6/6**, twice. Migrations **21/21**. SQL **53/53**.
- Streams: **83/83** unit, **20/20** live, **11/11** auth.
- Rate-limiter smoke green; gate-order **11/11**.
- CI x64 legs green on linux-x64, windows-x64, macOS x64
  (arm64 witnesses non-gating); release dry-run **`41219227263` success**
  (same three; publish skipped).

## Known limitations (state these honestly)

1. **Sustained-load memory (the main blocker).** On the v0.65.3 pin the
   server retains roughly **22 KB per request** (down from 44-50 KB on
   v0.65.1; measured with a keep-alive probe). The residual is app-path
   router/header lookups plus Map/JSON values; the HTTP parser is now
   ~1.6 KB and the response builder ~1.4 KB per cycle. Short demos and
   bounded runs are fine; **do not describe the current build as suitable
   for long-lived high-rate production without an RSS cap/restart**. Tracked
   as `REL-20261010-1549-pulse-4`.
2. **arm64 not shipped** (see the matrix).
3. **TLS is edge-only by design** (Caddy/nginx terminates; PULSE speaks
   plaintext HTTP/1.1 on loopback). Do not claim in-process TLS.
4. **HTTP/2 is not implemented** -- HTTP/1.1 is deliberate.
5. **WebSocket permessage-deflate and subprotocol negotiation** are pending.
6. **The 1M-request benchmark is blocked** until the memory work lands; do
   not publish 1M numbers.
7. **SQL serving** is a proposal (`docs/DESIGN-SQL-SERVING.md`), pending
   owner approval; the stock app is SQL-free.

## What's next (public roadmap wording)

- **stdlib patch tag** for the socket FFI widths
  (`REL-20261030-1628-pulse`) -> re-enable **arm64** CI gating and
  packaging. The compiler (v0.65.3) and `xiom.http` 0.1.11 are already
  clear.
- Memory: the response builder is fixed; the remaining floor is the HTTP
  parser plus app-path allocations, then the capped bttger 5k/1M
  benchmarks.
- **0.3.0**: SQL serving decision, version bump, CHANGELOG, tag, fleet
  watch.
- Realtime: permessage-deflate, subprotocol negotiation.

## Suggested site treatment

- Landing: one-line pitch + "0.2.2" badge and the x64 support matrix;
  link the docs set (`README.md`, `docs/DEPLOYMENT.md`,
  `docs/DESIGN-SSE-WEBSOCKET.md`, `docs/DESIGN-SQL-SERVING.md`,
  `docs/ROADMAP-TOP-TIER.md`).
- Status page: the platform table above, plus a single "known issue:
  sustained-load memory (fix in progress)" note. Link the relay item or
  the tracker, not raw numbers, unless the tracker still says the same.
- Avoid: "top-tier complete", "production-ready at any rate", "arm64
  supported", "in-process TLS", "HTTP/2", "1M benchmark".

## Links

- Repo: https://github.com/xiom-projects/xiom-pulse
- Live demo: https://pulse.xiom-lang.org
- Tracker: `docs/PROGRESS.md` -- Roadmap: `docs/ROADMAP-TOP-TIER.md`
- Deployment: `docs/DEPLOYMENT.md` -- Realtime: `docs/DESIGN-SSE-WEBSOCKET.md`
- SQL proposal: `docs/DESIGN-SQL-SERVING.md`
