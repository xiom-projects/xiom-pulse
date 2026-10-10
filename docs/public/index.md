---
title: Introduction
description: What XIOM PULSE is, what it ships, and its beta status.
---

# XIOM PULSE

PULSE is the official XIOM web backend: a single, self-contained HTTP
server binary written in XIOM, built for small production services and
showcases. It runs behind a TLS-terminating proxy (nginx is the
supported shape), binds loopback by default, and keeps its state in a
crash-safe append store with an audit trail.

- Source: https://github.com/xiom-projects/xiom-pulse (MIT OR Apache-2.0)
- Releases: https://github.com/xiom-projects/xiom-pulse/releases
- Downloads (mirror): https://dl.xiom-lang.org/pulse/latest.json
- Live demo: https://pulse.xiom-lang.org

## What it ships

- HTTP/1.1 core: router with path parameters, query strings, JSON
  envelope responses, security headers, `HEAD`/`OPTIONS`, chunked
  request bodies.
- Sessions + CSRF, JWT tokens, rate limiting, an opt-in CORS allowlist.
- An events API over a crash-safe store (JSONL by default; an embedded
  `xiom.kv` backend is available), an audit log with rotation, Prometheus
  metrics, and a structured access log.
- An OpenAPI 3.1 contract served at `/openapi.json` plus a full CLI
  (`openapi`, `routes`, `version`, `check-config`), and a `/v1` alias
  for every route.
- Paginated event listing (durable `seq` cursor, RFC 8288
  `Link: rel="next"`), idempotent event writes (`Idempotency-Key`), and
  bounded `multipart/form-data` uploads (`POST /api/uploads`).
- An outbound HTTP client base with an SSRF guard (blocklist by default,
  `PULSE_HTTP_ALLOWLIST` for strict egress) for integrations.
- Showcase serving: a per-site landing page (`PULSE_LANDING_PATH`) and
  `/assets/*` static files with ETag/304/Range support.

## Beta status

PULSE 0.1.x is an **honest beta**. The core paths are load-tested and
the release gate runs the full suite on Windows and Linux, but there are
real limits: it is single-threaded with no keep-alive or receive
timeouts yet, has no credential/RBAC store, and a memory-growth issue is
under investigation (see [Security and beta limits](./security.md)).
Do not treat the demo as a hard production deployment yet.

Start with [Install](./install.md) and [Quick start](./quickstart.md).
