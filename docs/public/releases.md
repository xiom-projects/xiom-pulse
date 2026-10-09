---
title: Release history
description: Published PULSE releases and their download locations.
---

# Release history

The full changelog lives in `CHANGELOG.md` in the repository root; each
GitHub release also carries highlights. The download mirror lists the
current tag in `https://dl.xiom-lang.org/pulse/latest.json`.

## 0.1.0 - 2026-10-09

First public release (beta).

Artifacts (each with a `.sha256`, plus a combined `SHA256SUMS`):

- `pulse-0.1.0-linux-x64.zip`
- `pulse-0.1.0-windows-x64.zip`

Download: `https://dl.xiom-lang.org/pulse/releases/pulse-v0.1.0/` and
`https://github.com/xiom-projects/xiom-pulse/releases/tag/pulse-v0.1.0`.

Highlights: HTTP core with chunked request decoding and smuggling
guards; sessions + CSRF, JWT, rate limiting, CORS allowlist; events
store (JSONL default, kv opt-in) with count/list/compact and audit
rotation; Prometheus metrics and structured access logs; showcase
serving (`/assets/*`, `PULSE_LANDING_PATH`); configuration with
validation warnings; release/backup tooling and the Dockerfile.

Notes: built with XIOM v0.64.1; release gate = suites x2 + 78-check
smoke + rate + crash + kv store soak (Linux) and suites + smoke
(Windows). macOS is not published yet.
