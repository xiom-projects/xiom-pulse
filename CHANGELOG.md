# Changelog

All notable changes to XIOM PULSE. Versions match the release tags
(`pulse-v<version>`); highlights for each release also appear in the
GitHub release body.

## [Unreleased]

### Added

- **stdlib-v0.64.9 adopted; compiler v0.64.9 WITHDRAWN:** `STDLIB_VERSION`
  is `aa8b656` (list_dir fix + JSON/YAML/TOML/CSV byte builders) and pins
  compiler v0.64.8 by design. The v0.64.9 compiler is **withdrawn**
  (`REL-20261022-1826-compiler`: release-mode nested-pattern/1451/1550
  defects), production stays v0.64.8, and **v0.65.0** is the next
  production gate. The user
  `StreamHandler` registry was implemented and then reverted with the
  held compiler (`29dbd25`/`5a927d3`); it returns from git history when a
  fixed archive passes. macOS x64 is gating with the stdlib list_dir fix;
  macOS arm64/22.04 remain blocked (0717/1529).
- **macOS witness (non-gating):** `macos-14` (arm64) and
  `macos-15-intel` (x64) join the matrix; `setup-xiom` uses the
  SHA256-pinned macOS toolchains and the Unix gates run. The arm64 leg is
  blocked by the compiler module-scope Vec IR defect
  (`REL-20261021-0717-pulse`, same as Linux clang 14). The x64 leg was
  red on macOS `list_dir`; with stdlib **05673f8** checked out pre-pin it
  is fully green (witness rc 0, migrations 21/21, SQL/stream/suites), so
  `REL-20261021-0918-pulse` is verified and lands with the next pin. The
  separate Windows compiler C-PULSE-17 inline `Result.value[i]` concat is
  `REL-20261010-1609-stdlib`. Both jobs report but do not gate the run
  until fixed; macOS release assets remain behind `RELEASE_BUILD_MACOS`.
- **linux-arm64 release leg:** the release matrix now packages
  `linux-arm64` natively on `ubuntu-24.04-arm` (the packager auto-detects
  aarch64 and emits `pulse-<ver>-linux-arm64.zip` + `.sha256`). Dry-run
  only; the next release will ship linux-x64, linux-arm64 and
  windows-x64 by default.
- **linux-arm64 CI leg:** the native `ubuntu-24.04-arm` runner is in the
  CI matrix; `setup-xiom` selects the SHA256-pinned
  `xiom-0.64.8-linux-arm64` toolchain (and installs clang when absent),
  and the arm64 build is verified with `file` before the full SQL,
  stream, suite, smoke and crash gates run natively. No arm64 release
  asset yet; macOS remains gated.
- **Workstation memory cap:** `scripts/capped_app.ps1` /
  `scripts/capped_app.sh` run the app under an RSS watchdog (default
  **2048 MB**, `PULSE_MAX_RSS_MB` override) and kill the process tree at
  the cap (exit 137). Use it for manual/long runs and benchmark servers;
  CI runners are isolated.
- **SQL store/repository layer (opt-in):** `src/sql.xi`
  (`xiom.pulse.station.sql`) over `xiom.sqlite` 0.4.1 -- integer
  connection handles, mandatory value binding (`p_text`/`p_int`/
  `p_real`/`p_null` through `prepare`/`bind_*`; identifiers are the only
  validated interpolated tokens), JSON row mapping with exact 64-bit
  integers, repository `find`/`list`/`count`/`insert`/`update`/`delete`,
  `limit+1` `has_more` paging, and explicit transactions. The serving
  binary does not import it; builds that do pass the vendored SQLite C
  source. Dedicated gate: 53/53 on Windows + WSL
  (`tests/test_sql.xi`); design + knex matrix in
  `docs/DESIGN-SQL-STORE.md`.
- **SSE + WebSocket units (W4):** the Station loop can hand the accepted
  fd to `src/stream.xi` after the frozen gate. `GET /api/sse` streams
  chunked `text/event-stream` events (events/interval knobs, CORS, proxy
  buffering off) and `GET /api/ws` performs the RFC 6455 handshake plus a
  masked echo frame loop (ping/pong, close, fragmented-message
  reassembly, 1 MiB cap, 1002/1003/1009 rules; plain GET returns 426).
  Browser `Origin` is same-origin by default, with the
  `PULSE_CORS_ORIGIN` allowlist and a 403 otherwise; authentication
  remains application-level. Stream routes live in a startup registry
  (`init`/`register`; built-in SSE/WS kinds), appear in the `routes` CLI,
  and accept per-route rate policy on their literal path. Pure gate
  `tests/test_stream.xi` (57 checks) and live `scripts/stream_smoke.*`
  (20 checks, launched under the RSS cap) run on both platforms; design +
  reference matrix in `docs/DESIGN-SSE-WEBSOCKET.md`. User-supplied stream
  handlers and permessage-deflate remain follow-ups.
- **Per-route rate policy (W6):** `PULSE_RATE_ROUTES` adds token buckets
  keyed by `METHOD PATH=RATE[/BURST]` (method `*` allowed; PATH is a route
  template) on top of the global bucket, which still runs first. Invalid
  entries are named at startup and in `--check-config`; `--help` and
  `DEPLOYMENT.md` document the syntax. Unit coverage in `test_http`;
  `scripts/rate_smoke.*` now proves the 200/429/refill path end to end on
  both platforms.

## [0.2.2] - 2026-10-19

### Added

- Connection deadlines (keep-alive Phase A): `PULSE_READ_TIMEOUT` /
  `PULSE_WRITE_TIMEOUT` / `PULSE_IDLE_TIMEOUT` bound every client wait
  -- a slowloris gets `408 Request Timeout`, a stalled reader is
  dropped mid-write, and one slow client can no longer hold the loop.
  `--check-config` prints the values and warns on `0` (dev only).
- Connection reuse (keep-alive Phase B): HTTP/1.1 connections serve
  sequential requests without closing (`PULSE_KEEPALIVE=0` restores
  close-per-request); `Connection: close` and HTTP/1.0 peers close
  correctly; pipelined requests are answered in order with no data
  loss; idle connections close silently after `PULSE_IDLE_TIMEOUT`;
  and an incomplete body never leaks into the next request.

### Changed

- Site mode now answers `301` (query preserved) when a slash-less
  directory path resolves to its index page, so relative asset URLs in
  the page resolve against the directory instead of its parent -- the
  nginx convention; found re-testing the full xiom-lang.org tree
  (`REL-20261015-2156-website-2`).
- **Middleware Phase A complete**: the request ladder is four named
  units -- read, `gate_request()` (parse/too-large/quit/OPTIONS/CSRF/rate
  with a `GateResult`), `build_dispatch_response()` (dispatch/build/HEAD
  trim/beforeSend headers+CORS), and `after_response()` (send/metrics/
  access log/audit, one call site). No behavior change; the gate order is
  locked by `scripts/gate_order.py`.
- **Station consumes the published `xiom.pulse` 0.3.1 core** (Beacon):
  the byte-identical `http`/`envelope`/`reqctx`/root modules are gone;
  the product loop lives in `xiom.pulse.station.core` and the version in
  `src/version.xi`. 0.3.1 adds the stateful `HookCtx` hook seam, the
  unmatched-route fallback hook (site/static), HEAD-as-GET header-only
  responses, the Server-token seam (the wire now advertises the Station
  release), and the package-side 413 for oversized declared bodies.
  Built on XIOM v0.64.8 + stdlib `112c5b6` with latest registry deps
  (`xiom.http` 0.1.8, `xiom.cookie` 0.1.2, `xiom.jwt` 0.2.1). One core,
  never a fork (`docs/DESIGN-STATION-CONSUMES.md`).
### Fixed

- Site-mode file responses no longer emit `Content-Length` twice: the
  static engine's copy is dropped and `http.build_response_bytes()` owns
  framing. nginx rejected the duplicate header with a 502, blocking the
  xiom-lang.org dogfood switch (`REL-20261017-1141-ops`); the suite now
  locks a single CL on a site file response.
- The smoke write-stall check reads the response head first, so the
  write-deadline clock starts when the server begins the response rather
  than while it is still reading/building the 50 MB body (removed a WSL
  drvfs timing flake); the crash harness waits for the listener and
  tolerates the Windows taskkill exit race.
- A plain `Content-Length` body above the 1 MiB cap now answers `413
  payload_too_large` before dispatch instead of being silently truncated
  and handed to the route (found while pinning the middleware gate order;
  the new `scripts/gate_order.py` also locks CSRF-before-rate, the
  OPTIONS bypass, and quit-after-parse).

## [0.2.1] - 2026-10-15

### Changed

- **Rebuilt on the released XIOM v0.64.5 toolchain** (paired stdlib pin
  `092dfa0c`): carries the upstream startup-crash family fix
  (`Path.is_dir` implicit-self recursion) that kept the Linux production
  demo on 0.1.0. CI pins in every workflow moved to v0.64.5 + the four
  archive SHA256s, and the `&HandlerOut` reference-parameter helper is
  re-landed in the suite as a permanent compiler regression lock
  (batch-5 witness).
- The registry `xiom.sqlite` 0.4.1 SQL driver artifact is consumer
  co-verified green (24/24) on this toolchain; the SQL migrations unit
  follows post-release.

### Added

- **Game control plane (`/api/game/*`, P8 forward contract with the
  XIOM Engine lane)**: `register` (build/protocol/map/mode/capacity/
  region -> server id + per-server bearer token + config revision +
  heartbeat cadence), `heartbeat` (liveness/load; the response carries
  pending commands -- `drain_requested`/`shutdown` piggyback, no inbound
  route to game servers), `config` (document with revision/ETag;
  `304` on If-None-Match; `409 incompatible_build`), `compat`
  (min/current build + protocol facts), `match-report` + `telemetry`
  (per-server bearer + `Idempotency-Key`, duplicate keys replay
  `deduplicated`), and ops-gated `admin/command` (state: `active` |
  `drain_requested` | `shutdown`). Records append to `PULSE_GAME_PATH`
  (kind-tagged, latest-wins per server); config document at
  `PULSE_GAME_CONFIG_PATH`; admin token `PULSE_GAME_ADMIN_TOKEN`
  (unset = admin disabled); new config keys `game_path`,
  `game_config_path`, `game_heartbeat_secs`.
- **`pulse_app openapi --check`**: verifies the served OpenAPI contract
  still covers every router route (exit 1 with the missing list on
  drift) -- the release-gate companion to the route-table drift guard.
- **Security headers (helmet-derived reviewed defaults)**: every response
  now carries `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`, `Cross-Origin-Opener-Policy: same-origin`,
  `Cross-Origin-Resource-Policy: same-origin`, `Origin-Agent-Cluster: ?1`,
  `Strict-Transport-Security: max-age=15552000; includeSubDomains`,
  `X-DNS-Prefetch-Control: off`, `X-Permitted-Cross-Domain-Policies: none`,
  and `X-XSS-Protection: 0`. `Content-Security-Policy` is opt-in via
  `PULSE_CSP` (or the `csp` JSON key): site mode serves pre-built trees
  whose inline scripts a strict default policy would break.
- **Static site mode** (`PULSE_SITE_DIR`): serves a whole pre-built
  directory tree for unmatched `GET`/`HEAD` and `/assets/*` -- index
  resolution, clean URLs (`/about` -> `about.html`), a custom `404.html`
  served with status 404, and `application/wasm` for `.wasm` bundles
  (playground/editor bundle ready). Cache via `PULSE_SITE_MAX_AGE`
  (default 3600). API routes always win; traversal stays rejected by
  the static engine. Configured by env or the `site_dir`/`site_max_age`
  JSON keys.

### Fixed

- The OpenAPI document declared an `uploads` path tagged `uploads`
  without declaring the tag; the tag is now present. A new route-table
  drift guard in the test suite fails when a router route never reaches
  the served contract, so the document can no longer silently lag the
  router (the route table itself is now single-source in
  `router.route_defs()`).

## [0.2.0] - 2026-10-10

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
- **Outbound HTTP client base**: `xiom.http` pin bumped to **0.1.4**
  (manifest + CI). New `xiom.pulse.outbound` SSRF guard -- http/https
  only, userinfo refused, `localhost`/`.local`/`.internal`/`.home.arpa`
  refused, every inet_aton numeric IPv4 form refused when loopback/
  private/CGNAT/link-local/multicast/reserved, IPv6 loopback/ULA/
  link-local/v4-mapped refused; `PULSE_HTTP_ALLOWLIST` switches to a
  strict allowlist and `PULSE_HTTP_MAX_BYTES` caps responses.
  `probe_outbound_guard` (42 checks) runs in the fleet on both
  platforms. The libcurl transport seam (`src/outbound_transport.xi`)
  lands behind the package `--c-source` build hook (same family as
  sqlite), so the server binary stays libcurl-free.
- **Multipart uploads**: `POST /api/uploads` (0.2 surface, also
  `/v1/api/uploads`) parses `multipart/form-data` PULSE-side with
  per-part (`PULSE_UPLOAD_MAX_BYTES`, default 1 MiB) and part-count
  (`PULSE_UPLOAD_MAX_PARTS`, default 8) caps. Files go to
  `PULSE_UPLOAD_DIR` under generated names -- client filenames are
  never path components -- and the JSON response lists
  `name`/`original`/`bytes`/`content_type`. Stable errors: `415
  unsupported_media_type`, `400 boundary_not_found`/`malformed`, `413
  part_too_large`/`too_many_parts`. Smoke suite at **119 checks**.
- Config JSON file overlay completed: `store_backend`/`kv_dir`/
  `kv_prefix` (documented but previously not applied) and the 0.2 keys
  (`upload_dir`, `upload_max_bytes`, `upload_max_parts`,
  `http_allowlist`, `http_max_bytes`) now load from `PULSE_CONFIG`
  files; environment variables still win.
- **Outbound client is real**: `xiom.http` bumped to **0.1.5** (ships the
  curl-free bridge shims + the verified consumer recipe). The libcurl
  transport (`src/outbound_transport.xi`) is proven end-to-end on both
  platforms with `scripts/outbound_transport_probe.{ps1,sh}` (guard
  blocks loopback -> `PULSE_HTTP_ALLOWLIST` opt-in -> real GET 200
  through libcurl 8.22.0); evidence-only, not in the standard fleet.
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
