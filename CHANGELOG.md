# Changelog

All notable changes to XIOM PULSE. Versions match the release tags
(`pulse-v<version>`); highlights for each release also appear in the
GitHub release body.

## [Unreleased]

### Added

- Error envelopes carry the HTTP status additively
  (`{"error":{"status":N,"code":...,"message":...}}` on every error path,
  including 405 with its `Allow` header) -- RFC 9457-friendly without
  changing the stable code/message contract.
- **Pagination on `GET /api/events`**: every event written by 0.2+ carries
  a durable `seq` cursor; pre-0.2 records fall back to their valid-record
  ordinal. Responses gain `next_cursor` and, while an older page exists,
  an RFC 8288 `Link: </api/events?limit=N&before=K>; rel="next"` header
  (the `kind` filter is preserved, percent-encoded). `?before=K` walks
  backwards; a malformed cursor is `400 invalid_cursor`. Identical
  behavior on the JSONL and kv backends.
- **Idempotency keys on event writes**: `POST /api/events` accepts an
  optional `Idempotency-Key` header (1-200 visible characters). A retry
  with a stored key replays the original `seq` with `"deduplicated":true`
  and appends nothing -- the marker lives inside the event record, so the
  guarantee is durable on both backends. Malformed keys are
  `400 invalid_idempotency_key`. Responses also carry `seq` now.
- **`/v1` versioned alias**: every route also resolves under `/v1`
  (`/v1/api/events` == `/api/events`, query preserved); new surfaces are
  introduced under `/v1` first, and pagination `Link` headers preserve
  whichever prefix the client used.
- CLI subcommands complete the documented set: `version` and
  `check-config` now mirror their flags (`openapi` and `routes` already
  ship).
- **Official icon art adopted**: the owner-provided `pulse.ico` (187,396 B)
  replaces the older art at the canonical path `resources/img/pulse-ico.ico`
  (used by `/favicon.ico`), and is now **embedded in the Windows exe** via
  pinned rcedit (fetched by CI; `scripts/build.ps1` resolves it from PATH,
  npm, or `%LOCALAPPDATA%\xiom-tools`). The compiler `xiom --icon` flag is
  still awaited; the rcedit hook retires when it ships.
- `GET /openapi.json` serves the OpenAPI 3.1 API contract; the version
  is substituted at request time from the running build, so the contract
  and `/api/version` can never drift apart.
- First CLI subcommands of the 0.2 contract slate: `pulse_app openapi`
  prints the contract document and `pulse_app routes` prints the route
  table (`METHOD PATH` per line).
- `PULSE_OPENAPI_PATH` (default `resources/openapi.json`).
- Smoke suite grew to 89 checks (contract route, CLI subcommands, error
  status field).
- Smoke suite now **100 checks** on both platforms: pagination page walk,
  `Link` cursor syntax, empty-page and `invalid_cursor` cases. The PS
  smoke twin also hardens its harness: server output goes to files (a full
  ~4 KiB pipe deadlocked the server mid-suite) and exit codes are read
  through a cmd wrapper (`Start-Process` left `ExitCode` empty).

## [0.1.2] - 2026-10-09

Maintenance release: rebuilt on XIOM v0.64.2 and completes the registry
session-store swap. Artifacts: `pulse-0.1.2-linux-x64.zip`,
`pulse-0.1.2-windows-x64.zip` (+ `.sha256`, combined `SHA256SUMS`).
(Note: `pulse-v0.1.1` was tagged mid-cut but never released -- its CI
gate failed on a stale version assertion in the test suite, and release
tags are immutable, so the fixed cut ships as 0.1.2.)

### Changed

- Built with XIOM **v0.64.2**: the Windows request-path memory growth is
  fixed upstream (flat RSS under load); `PULSE_BIND` now validates the
  address-only shape (an `addr:port` value warns at startup and in
  `--check-config`).
- Sessions are backed by the registry `xiom.session` 0.1.0 store
  (128-bit hex ids, explicit-clock expiry, opportunistic pruning) behind
  the same HTTP contract -- routes, cookies and CSRF behavior unchanged.

### Fixed

- Cross-module session-store crash (C-PULSE-09): resolved upstream in the
  v0.64.2 batch and adopted here; `probe_adopt_smoke` passes on both
  platforms.
- Release/backup script portability fixes; DCO workflow pinned; docs
  refresh (public set + framework roadmap).

### Known limits

- Linux RSS growth in the request path is still under investigation
  (upstream, C-PULSE-14): run with a memory limit + restart policy.
- No macOS artifacts yet (upstream darwin blockers); Linux x64 and
  Windows x64 only.

## [0.1.0] - 2026-10-09

First public release (beta). Artifacts: `pulse-0.1.0-linux-x64.zip`,
`pulse-0.1.0-windows-x64.zip` (+ `.sha256`, combined `SHA256SUMS`).
Built with XIOM v0.64.1.

### Added

- HTTP/1.1 core: router with path parameters and query strings, JSON
  envelope responses, security headers, `HEAD`/`OPTIONS`,
  `Expect: 100-continue`, `Transfer-Encoding: chunked` request decoding
  with a `TE`+`Content-Length` refusal (smuggling shape) and `501` for
  other transfer codings.
- Sessions with CSRF protection, HS256 JWT issue/verify, global
  token-bucket rate limiting, opt-in CORS allowlist (comma-separated).
- Events API: append/list/count/compact over a crash-safe JSONL store
  (default) or the embedded `xiom.kv` backend (opt-in), plus an audit
  log with size-based rotation.
- Prometheus metrics, structured access log, `/health`, `/api/version`
  with optional build provenance env.
- Showcase serving: `/assets/*` static files (ETag/304/Range/traversal
  guard) and `PULSE_LANDING_PATH` (read per request).
- Configuration: environment + JSON file overlay, `--check-config`,
  value validation warnings for invalid settings.
- Operations tooling: release packager, kv-aware backup/restore twins,
  HTTP/TCP soaks, crash/reopen tests, 78-check smoke suite, Dockerfile.

### Known limits

- Beta: single-threaded, no keep-alive or receive timeouts yet; no
  graceful SIGTERM drain.
- Memory-growth issue in the request path under investigation (run with
  a memory limit + restart policy).
- No credential/RBAC store; the login route is a demo.
- macOS artifacts are not published yet.
