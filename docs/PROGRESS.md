<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- Progress Tracker

**Last updated:** 2026-10-10 (0.2 pagination: `Link` + seq-in-record cursor; smoke 100/100 both platforms)

_Delta 2026-10-08 (v0.64.1 sweep): toolchain updated in place to
**v0.64.1**; **C-PULSE-08 CLOSED** (m212 dash+dot gates green, no
source-roots), **C-PULSE-10 CLOSED** (`probe_pkg_kv` green -- kv_get
returns stored text), C-PULSE-11 alias fix noted; full regression green
on v0.64.1 (suites x2, smoke 73/73, crash 6/6, rate). NEW ecosystem
breakage filed: v0.64.1 extern-unsafe enforcement rejects the published
`xiom.http` 0.1.1 (67 T001s); PULSE pruned the already-unused package
(`probe_pkg_http` = known-red republish gate, packages lane owns it).
Score holds (toolchain adoption, no new capability)._

_Delta 2026-10-08 (Linux sweep + kv decision): toolchain now **v0.64.1 on
Linux/WSL too** (archive sha256 `6f6787a3...` verified, installed tree
byte-identical to the verified extract). **Linux sweep fully GREEN**:
probe fleet 11/11 (incl. `probe_adopt_smoke` run twice -- **C-PULSE-09
does not reproduce on Linux**; narrowed to Windows), m212 dash+dot gate
green (after bridging the new **C-PULSE-13** Unix pkg-home mismatch,
filed), suites x2, smoke **73/73** (jsonl + kv), crash 6/6, rate, and a
**20m kv store-soak** (756 writes / 0 fail; compact + hard-kill reopen
counts intact). **kv-default decision: stays `jsonl` default / kv
opt-in** -- flip is gated on kv-aware Dockerfile + backup tooling +
crash test + a longer soak (prerequisites recorded in
`docs/PACKAGE-WISHLIST-PULSE.md`). Storage 65% -> 68% for the
cross-platform verified kv backend. 55.6% -> ~55.9%._

_Delta 2026-10-08 (wrap 3): **`xiom.http` 0.1.2 republish verified and the
package re-added** (probe green on Windows + Linux; suites x2 + smoke
73/73 with it back in the catalog) -- the last known-red package gate is
closed. The PS twin scripts' stale exe defaults
(`pulse_server.exe`/`pulse_app_v6/v8/v9.exe`) were aligned to
`out\pulse_app.exe` (one hung the smoke run -- fixed; smoke + rate
re-verified green). Website-lane brief filed
(`docs/WEBSITE-RELAY-PULSE.md`); owner decisions recorded in
`docs/OPS-REQUEST.md` section E (pulse. subdomain live, Phase 1 pages by
the website lane, release sequence on greenlight). Score holds (~55.9%)._

_Delta 2026-10-08 (wrap 4): **chunked request decoding landed** (TE:
chunked decoded with caps + trailers; TE+CL -> 400; other codings ->
501; smoke 73 -> **76**, test_http +11 parse cases, route cases in
test_app). **C-PULSE-02 fully closed:** the absolute-path `source-roots`
workaround is removed from `xiom.toml`; build + suites x2 + smoke 76/76
verified on Windows and Linux with `[dependencies]` alone resolving all
ten packages. **NEW C-PULSE-14 (Linux-only):** the 30m HTTP soak grows
RSS ~48 KB per request linearly (2.5 -> 146 MB; Windows flat, HEAD A/B
identical, pure Vec churn flat) -- filed with a runtime repro;
release-gating for the Linux demo, not for Phase-1 website work. HTTP
core 80 -> 84 (+0.5); Reliability 45 -> 40 (-0.5, Linux soak caveat).
Total ~55.9% -> ~55.8%._

_Delta 2026-10-08 (wrap 5): **config-value validation warnings** landed --
invalid `PULSE_PORT`/rate/TTL/audit-size values, non-0/1 booleans and
unknown store backends now warn at startup and in `--check-config`
instead of silently falling back (test_app +8 checks, smoke 76 -> **78**
on both platforms). Configuration 80 -> 85. Total ~55.8% -> ~56.1%._

_Delta 2026-10-08 (wrap 5b): **kv-default ops surface prepped** --
`deploy/Dockerfile` exports `PULSE_KV_DIR=/data/pulse-kv`; the backup
twins are kv-aware (`--kv-dir`/`-KvDir`, env-driven default with
`PULSE_STORE_BACKEND=kv`, whole-dir snapshot at `kv-store/` with
per-file sizes+sha256; verified on Windows + Linux); `DEPLOYMENT.md`
documents the kv store, snapshots and restore, and the Linux systemd
section now reflects the real Linux support + C-PULSE-14 mitigation.
Remaining flip gate: a longer kv soak (crash/reopen already covered by
`store_soak`). Score holds (~56.1%)._

_Delta 2026-10-09 (wrap 6): **C-PULSE-14 corrected -- cross-platform.**
The Windows soak's memory sampler measured the `cmd.exe` wrapper, not the
server: every historical "flat memory" Windows number is invalid. Fixed
(`soak_http.ps1`/`concurrent.ps1` resolve the real child); the corrected
5m soak shows **~32 KB/request** growth (Linux ~48 KB/req); the new
`rss_probe` twins reproduce it in ~2 minutes on either OS. Candidate lane
fix spotted: m235 (loop-body static allocas) -- retest on the next
archive. Reliability 40 -> 35, Testing 82 -> 80. Total ~56.1% -> ~55.5%._

_Delta 2026-10-09 (wraps 7-8): **CI + release pipeline landed** (setup
action, PR gates, tag releases that cut pulse-v0.1.0 end-to-end with
provenance, weekly heavy soaks; macOS x64/arm64 legs prepared for the
next release with the portability fixes: lsof wait_listen fallback,
timeout/gtimeout watchdog fallback, sha256sum/shasum helper,
`pulse-<ver>-macos-<arch>.zip`); the first macOS dry run hit upstream
darwin blockers (runtime C `_SC_AVPHYS_PAGES`, arm64 x86 asm, a codegen
intrinsic; filed), so the macOS legs are gated behind
`RELEASE_BUILD_MACOS` and the next release is not blocked. **C-PULSE-16
filed:** the ops-verified
`PULSE_BIND` gap (stdlib `socket_bind` wildcard-only; repro LISTEN
`0.0.0.0`); address-aware bind filed upstream, firewall mitigation
verified on the demo; fix + LISTEN-address smoke check ship with the
next release. Security 46 -> 42 (-0.5); Testing 80 -> 88 (+0.4) now that
CI exists and cut a release. Total ~55.5% -> ~55.4%._

_Delta 2026-10-09 (wrap 9, v0.64.2 adoption): **both platforms on
v0.64.2** (dl live; SHAs pinned in all workflows; the CI setup action no
longer creates the C-PULSE-13 bridge). **C-PULSE-09 CLOSED** -- probe
fleet 11/11 on Windows AND Linux, `probe_adopt_smoke` steps 1..10, exit
0. **C-PULSE-13 CLOSED** (m232: `xiom pkg` resolves the compiler home;
verified installs + doctor). Suites x2 + smoke 78/78 on both platforms.
**C-PULSE-14: Windows FIXED on v0.64.2 (flat over 206 req); Linux still
grows ~87 KB/req steady -- worse than v0.64.1's ~48** (retest on the
next archive; m235 not in v0.64.2). Incident: a concurrent toolchain
re-extract wiped the WSL packages store mid-sweep (reinstalled via
`xiom pkg install`; green after). Score holds (~55.4%)._

_Delta 2026-10-09 (wrap 11, 0.1.1 cut): **session-store swap DONE** --
`src/session.xi` is now a wrapper over the registry `xiom.session` 0.1.0
store (128-bit hex ids, explicit-clock expiry, pruning; user as the
"user" entry) behind the identical HTTP contract; module renamed
`xiom.pulse.sessions` to dodge the C-PULSE-12 alias shadowing. Verified:
build + `probe_adopt_smoke` + suites x2 + smoke 78/78 on BOTH platforms.
Version bumped to **0.1.1** (rebuilt on v0.64.2 -- Windows memory flat /
BIND validation / docs), CHANGELOG + public set updated. Score holds
(~55.4%)._

_Delta 2026-10-09 (wrap 12): the 0.1.1 tag's CI gate failed on a stale
version literal in our own test suite (nothing published); tags are
immutable, so the fixed cut is **0.1.2** -- every expected-version
literal updated (pulse.xi, server APP_VERSION, http Server header x2,
test_smoke, test_http, smoke twins), re-verified with the pinned stdlib
before tagging. Also filed: the `@llvm.memset.p0i8.i64` IR warning
reproduces on Linux CI (llvm-16), not just darwin._

_Delta 2026-10-09 (wrap 13, 0.2 first unit): **OpenAPI contract live** --
`GET /openapi.json` serves the repo document with the running version
substituted at request time; the first CLI subcommands (`openapi`,
`routes`); config `PULSE_OPENAPI_PATH`; test_app +7 checks; smoke
**84/84** on both platforms (Linux pinned-stdlib). Roadmap 0.2 items 1/2
partially done -- problem+json, pagination, idempotency, `/v1`, flag
promotions next. Score holds (~55.4%)._

_Delta 2026-10-09 (wrap 13c): **error envelopes mirror the HTTP status
additively** (`{"error":{"status":N,...}}`; shared helper also covers the
405 Allow path) and the **CLI set is complete** (`version` +
`check-config` subcommands). test_app +3 checks; smoke **89/89** on both
platforms (Linux pinned-stdlib). Roadmap 0.2: item 2 done, item 1
partially -- pagination `Link`, idempotency keys, `/v1`, the
SSRF-guarded HTTP client and multipart next. Score holds (~55.4%)._

_Delta 2026-10-10 (0.2 pagination): **`Link` pagination on
`GET /api/events`** -- cursor decision: **seq-in-record**. Every event
written by 0.2+ carries a durable `seq`; pre-0.2 records fall back to
their 1-based ordinal among valid records (stable under compaction,
which only drops invalid lines). Responses gain `next_cursor` and, while
an older page exists, an RFC 8288
`Link: </api/events?limit=N&before=K>; rel="next"` header (kind filter
preserved, percent-encoded); `?before=K` walks backwards; malformed
cursors get `400 invalid_cursor`. One `store_page` API serves both
backends (`store_last`/`store_last_kind` are thin wrappers now).
test_app +16 checks; smoke 89 -> **100/100** on both platforms (Linux
with the pinned stdlib `4dd8844`). Harness fixes found while extending
the smoke: the PS twin now file-redirects server output (a full ~4 KiB
pipe deadlocked the single-threaded server mid-suite) and reads exit
codes through a cmd wrapper (`Start-Process -PassThru` leaves `ExitCode`
empty with redirection); `check` needles are wildcard-escaped.
Roadmap 0.2 item 1: pagination done -- idempotency keys and `/v1` next.
Score holds (~55.4%)._

**Purpose:** one page the owner can read to see what a full
production-grade XIOM web backend consists of, what already works, and
what is still missing. Updated by the PULSE session at every step wrap.

**How to read the score:** each area has a weight (share of a
production-grade framework) and a completion %. The overall score is the
weighted sum. Scores are intentionally strict: "works in the soak" counts
only with evidence attached, and an area is not 100% until it survives
load, failure, and restart, not just the happy path.

---

## 1. Overall score: **~55.4% of production grade**

_Delta 2026-10-08 (kv backend): 54.6% -> ~55.6% -- **`xiom.kv` adopted as
the opt-in event-store backend** (`PULSE_STORE_BACKEND=kv`,
`PULSE_KV_DIR`/`PULSE_KV_PREFIX`; same store API, sequence-keyed records,
native compact; JSONL stays the default and documented fallback). Verified
on v0.64.1: smoke 73/73 through kv, store-soak 20s kv (89 writes, 0 fail,
compact + reopen counts intact), plus the default-backend smoke 73/73 and
test_app green as regression. Cross-module session-store swap still open
(C-PULSE-09); the kv path uses the single-module holder pattern._

_Delta 2026-10-08 (protocol round): 54.1% -> ~54.6% -- **`Expect:
100-continue`** handled (interim answered before the body read; raw-socket
proof: first line `HTTP/1.1 100 Continue`, final 200 logged; curls large
POSTs no longer stall 1s) and the missing **`Date`** response header
(spliced after the status line via `http.with_header_line`, RFC 1123
formatter reused from `xiom.static`). test_http +4 checks, smoke 73/73 on
both platforms._

_Delta 2026-10-08 (showcase round): 53.4% -> ~54.1% -- **general asset
serving** (`/assets/<path>` from `PULSE_ASSETS_DIR`, same
ETag/304/Range/traversal machinery; smoke 71/71 on both platforms) and
**per-site landing content** (`PULSE_LANDING_PATH`); **`PULSE_BIND`**
(default `127.0.0.1` -- **correction, wrap 8: not enforced in 0.1.x; see
C-PULSE-16** -- containers set `0.0.0.0`) and **`deploy/Dockerfile`** (ubuntu:24.04, verified: build +
container E2E health/version/assets). These are the prerequisites for the
`pulse.xiom-lang.org` / `orbit.` / `xvector.` showcase sites and the
offline benchmark harness (post-release)._

_Delta 2026-10-08 (pre-flight round): 53.2% -> ~53.4% -- **`--check-config`
CLI** (effective config dump, exits 1 only on an unreadable configured
file, never prints the secret; flags the dev-default JWT secret) and the
smoke twins invoke `--version`/`--check-config` before starting the server
(66 checks). Design note added: **integration seams for the new bindings
lane** (`E:\xiom-packages\bindings`; PULSE's storage/session/outbound
replacements plug behind single modules)._

_Delta 2026-10-08 (packaging round): 52.6% -> ~53.2% -- **Transfer-Encoding
smuggling guard** (any TE gets 501; CL.TE desync closed; test_app +
smoke 62/62), **status table completed** (206/304/501... were rendering
"Unknown"), **`scripts/release.{ps1,sh}`** (dist artifacts per the ops
naming, zip + sha256 verified on both platforms) and
**`scripts/backup.{ps1,sh}`** (timestamped store+audit snapshots, sha256
manifest, prune; both tested; restore runbook in DEPLOYMENT). Compiler
check: dl still v0.64.0; the lane-side m215/m216/m217 fixes (C-PULSE-08/
10/11) are the next adoption gate when v0.64.1 ships._

_Delta 2026-10-08 (schema round): 51.8% -> ~52.6% -- **JSON schema helper**
(`src/schema.xi`: typed rule list, required/optional, length + numeric
bounds, first-failure `code`/`field`/`message`) wired into the login and
token routes with field-specific 400s (probe 14/14); **flaky JWT tamper
check fixed** (append instead of replacing the last base64url char -- one
Windows run flaked on trailing-bit equivalence). Remaining M4 items
(keep-alive, recv timeouts, signals) are all gated on stdlib capabilities
already filed._

_Delta 2026-10-08 (ops items): 51.5% -> ~51.8% -- **audit rotation**
(`PULSE_AUDIT_MAX_BYTES`, single generation, probe + app E2E), **CLI
`--version`/`--help`** and **build-info fields in `/api/version`**
(commit/build from runtime env; compile-time define filed as a toolchain
ask). Signal handling checked: no stdlib handler-install API -> SIGTERM
graceful stop stays blocked; keep-alive stays gated on recv timeouts
(`socket_set_timeout` stub) because one idle keep-alive client would
stall the single-threaded loop._

_Delta 2026-10-08 (continuation): 51.2% -> ~51.5% -- **Windows
re-verify of the registry wave GREEN** (pkg installs + suites x2 + smoke
61/61 + crash 6/6 + rate); **stdlib adoption**: `TcpStream.write_all`
replaces the hand-rolled send loop, and `server_parse_request` now backs
PULSE's HTTP parser behind the same caps with invalid-Content-Length
hardening (differential probe pins parity on both platforms). Module
renamed `xiom.pulse.server` -> `xiom.pulse.app` (C-PULSE-12 alias
collision). Ops answered `docs/OPS-REQUEST.md`: staging parked by owner,
Linux toolchain source pinned on dl (v0.64.0 archive), CI mechanics ready
for greenlight._

_Delta 2026-10-07 (Linux/registry wave): 46.9% -> ~51.2% -- the **Linux
target verified end-to-end** (native ELF from the same v0.64.0 source:
suites x2 with 0 failures, smoke 61/61, crash 6/6, store-soak 20s,
proxy E2E 11/11 through Linux nginx 1.24 TLS on the extracted-package
path; crypto KAT env-free), **12 `.sh` twins** written and verified from
WSL, and the **registry wave**: `xiom.metrics` 0.2.0 (labeled counters +
latency preset), `xiom.static` 0.1.0 (ETag/Cache-Control/Range/304 +
traversal guard) and `xiom.http.middleware` 0.1.0 (CSRF/CORS) adopted
green. `xiom.session` store-integration and `xiom.kv` are filed as
C-PULSE-09/10 with repros; local store + JSONL remain the documented
fallbacks._

| # | Area | Weight | Done | Weighted | Status |
|---|---|---:|---:|---:|---|
| 1 | HTTP core (parse/build/limits) | 12% | 84% | 10.1 | query strings, header caps, HEAD, shared stdlib parser + invalid-CL reject, **chunked request decode** + TE/CL smuggling guard, Expect: 100-continue, Date header; keep-alive + chunked responses missing |
| 2 | Routing | 8% | 78% | 6.2 | registry `xiom.router` adopted (multi-`:param`, 404/405 + Allow); no wildcards/groups |
| 3 | Middleware framework | 8% | 30% | 2.4 | registry CSRF/CORS/error helpers adopted; still no composable chain |
| 4 | Configuration | 5% | 85% | 4.3 | env + JSON file (env-wins) incl. `PULSE_STATIC_DIR`; `--check-config` pre-flight with effective dump; **value validation warnings** (bad port/uint/TTL/bool/enum -> startup + check-config warnings); no schema library |
| 5 | Observability (log/metrics/audit) | 8% | 80% | 6.4 | registry metrics (labeled counters, latency-bounds histogram, exposition) + JSON log + audit with **rotation** + rid + gauges; flush no-op |
| 6 | AuthN/AuthZ | 10% | 35% | 3.5 | sessions + JWT HS256 + CSRF (constant-time via registry); no credentials, RBAC, rotation |
| 7 | Storage | 10% | 68% | 6.8 | JSONL store (default) + **xiom.kv backend** (opt-in, v0.64.2+, verified on both platforms incl. a **45m kv soak** -- 977/0, compact + hard-kill reopen intact), crash-safe append, `?limit`/`?kind`, compaction; no update/delete/index, no fsync || 8 | Security hardening | 12% | 42% | 5.0 | rate limit + CSRF + opt-in CORS + security headers + caps + static traversal guard + schema helper + TE/CL.TE smuggling guard; **C-PULSE-16: `PULSE_BIND` advisory (wildcard bind below the app; host firewall mitigates) -- fix queued with the next release**; no RBAC |
| 9 | Static / assets | 4% | 70% | 2.8 | registry `xiom.static`: mime/ETag/Cache-Control/304/Range + favicon + `/assets/*` showcase route (`PULSE_ASSETS_DIR`) + `PULSE_LANDING_PATH`; no directory index/listing |
| 10 | Protocol extras (SSE/WS/REST/GraphQL/templates) | 8% | 0% | 0.0 | none started |
| 11 | Reliability & concurrency | 10% | 35% | 3.5 | **C-PULSE-14: Windows FIXED on v0.64.2 (flat); Linux still grows ~87 KB/req steady (worse than v0.64.1's ~48)**; single-thread, no timeouts, no signals |
| 12 | Testing / CI / release | 5% | 88% | 4.4 | suites+smoke (78) on **Windows and Linux**; twins everywhere; **CI live (wrap 7): PR gates + SHA-pinned release workflow cut 0.1.0 end-to-end + weekly heavy soaks; macOS legs prepared, gated on upstream darwin fixes**; soak sampler fix + rss_probe twins; release packager + backup tooling; Dockerfile verified |
| | **Total** | **100%** | | **55.4** | |

**Framework roadmap:** `docs/FRAMEWORK-ROADMAP-PULSE.md` -- the 0.2-1.0
production-grade contract (driver seam, auth core, OpenAPI, CLI
subcommands, integrations, security gates) plus the all-OS 0.1.1
candidate plan (macOS x64/arm64 gated on the darwin blockers).

Two lenses to keep separate:

- **PULSE's own work:** ~80% of the Step 0-4 plan (Steps 0-3 core, the M4
  hardening wave, proxy E2E green on Windows and Linux, the Linux port +
  `.sh` twins, and the registry adoption wave except the two blocked
  packages).
- **Production-grade framework:** **~46%**. The gap is mostly *hardening*
  and *ecosystem maturity*, not basic function.

---

## 2. What works today (evidence-backed)

Run `out/` (Linux) or `out\pulse_app_v9.exe` (Windows); smoke 76/76 and
suites x2 on both platforms, these work end-to-end:

| Method | Path | What it does |
|---|---|---|
| GET | `/health` | liveness JSON |
| GET | `/api/version` | name + version |
| POST | `/api/echo` | echoes request JSON (400 on invalid) |
| GET | `/api/items/:id` | path-parameter demo |
| POST | `/api/session/login` | creates session, `Set-Cookie: sid` (HttpOnly, SameSite=Lax) |
| GET | `/api/me` | session lookup (401 without/expired) |
| POST | `/api/session/logout` | drops session, clears cookie |
| POST | `/api/token` | issues JWT HS256 (registry `xiom.jwt` 0.2.0) |
| POST | `/api/token/verify` | verifies signature + `exp`, returns payload |
| POST | `/api/events` | appends JSONL event (crash-safe) |
| GET | `/api/events` | last 10 events + count |
| GET | `/api/events/count` | event count |
| GET | `/metrics` | Prometheus text counters |
| GET | `/favicon.ico` | official app icon (187,396 bytes; also embedded in the Windows exe) |
| GET | `/` | landing page linking the icon |

Cross-cutting, working: router with 404/405+`Allow`, uniform error
envelope, env config, JSON access log with request ids and `dur_ms`,
structured metrics (counters + duration histogram), audit trail, cookie
sessions, JWT, crash-safe JSONL store, binary responses, request body
framing, global rate limiting (429 + `Retry-After`), graceful test
shutdown (`X-Pulse-Quit`).

**Load evidence:** 1h soak: PS driver 7,070/7,070 + WSL client 6,128,
server served **13,198/13,198** requests, 0 errors, clean shutdown; 64
simultaneous connections served, 64/64. **Memory caveat (wrap 6
correction):** the Windows "flat memory" figures from that era are
invalid -- `soak_http.ps1` sampled the `cmd.exe` wrapper, not the server
(fixed). Corrected: the request path grows RSS on **both platforms**
(~32 KB/req Windows over 587 requests; ~48 KB/req Linux over 3,097;
handles flat; pure Vec churn flat). Filed as C-PULSE-14 with repros
(`tests/probes/probe_alloc_loop.xi`, `scripts/rss_probe.{sh,ps1}`).

**Module inventory** (`src/`, all green in `tests/test_app.xi` x2):

| Module | Lines (rough) | Purpose |
|---|---:|---|
| `server.xi` | ~330 | accept loop, dispatch, send_all, log/audit wiring |
| `http.xi` | ~250 | request parse, response build (text/json/bytes) |
| `store.xi` | ~120 | JSONL append store, torn-line healing |
| `router.xi` | ~200 | app route table wrapper over registry `xiom.router`; query parsing + decoding |
| `session.xi` | ~100 | in-memory sessions, cookie bindings |
| `config.xi` | ~80 | env config with defaults |
| `metrics.xi` | ~120 | counters + request-duration histogram, Prometheus render |
| `ratelimit.xi` | ~50 | global token bucket wrapper over registry `xiom.rate` |
| `envelope.xi` | ~40 | error envelope |
| `pulse.xi` | ~15 | version |

---

## 3. What is missing, area by area (the honest list)

**HTTP core (84%)**
- No `keep-alive` (always `Connection: close`) -- the biggest perf item.
- Chunked REQUEST decoding landed (2026-10-08): caps, extensions ignored,
  trailers validated; TE+CL -> 400, other codings -> 501. Chunked
  RESPONSES still missing (they arrive with keep-alive/streaming).
- `HEAD` supported (GET semantics, body omitted); `Expect: 100-continue`
  handled; path not percent-decoded (query values are decoded).
- Head caps landed (16 KiB head, 100 headers, 1 MiB body); no per-route or
  per-connection byte-rate limits.
- Status is far from 100% even if all of the above land: response
  streaming, compression, HTTP/2 (proxy's job).

**Routing (78%)**
- Registry `xiom.router` 0.1.0 adopted: `src/router.xi` is a thin app
  wrapper (route ids + query parsing); consumer probe 8/8.
- Still missing: wildcards, optional segments, route groups, per-route
  middleware hooks, path percent-decoding.

**Middleware (30%)**
- Request-id/logging/audit are still wired inline in the loop.
- Registry `xiom.http.middleware` 0.1.0 adopted for CSRF token/validate and
  CORS header building; no composable chain, no recover-to-500.

**Configuration (85%)**
- Env-based with a JSON file (`PULSE_CONFIG`) for all eleven settings;
  environment variables win over file values.
- **Value validation warnings landed (2026-10-08):** invalid
  `PULSE_PORT`/rate/TTL/audit-size values, non-0/1 booleans and unknown
  store backends are reported once at startup (`pulse: warning: ...`) and
  in `--check-config` (`warning: ...`) instead of silently falling back.
- No general schema library beyond these per-setting checks.

**Observability (78%)**
- On registry `xiom.metrics` 0.2.0: labeled status-class counters, the
  11-bound latency-preset histogram, Prometheus exposition; JSON access
  log with `rid`/status/bytes/`dur_ms`; audit trail; request ids embedded
  in error envelopes; gauges (`pulse_app_info`, `pulse_store_records`,
  `pulse_uptime_seconds`).
- `io.flush_stdout()` is an empty body in the current stdlib -> logs can
  lag until process exit (stdlib wave queued).

**AuthN/AuthZ (35%)**
- Login trusts any username (no credential store/verification).
- Sessions are memory-only (lost on restart), no rotation on login.
- JWT: HS256 only, single static secret (dev default), no key rotation,
  no scopes/roles, no refresh tokens.
- No RBAC/authorization layer at all.

**Storage (68%)**
- Append + read last N (`?limit=1..100`) + `?kind=` field filter + count +
  compaction (temp file + atomic replace; drops torn lines); **10m soak:
  841 writes, 0 fail, compact/reopen counts intact, 0 mismatches**
  (`scripts\store_soak.ps1`); **kv soaks on Linux 20m + 45m** (756/0 and
  977/0, hard-kill reopen + native compact intact; single 90 KB segment).
  No update/delete, migrations framework,
  or indexes (fine at small scale).
- No `fsync` in the runtime: durability today = torn-tail healing, not
  power-loss safety (stdlib wishlist row added).
- `xiom.kv` 0.1.0 is the **verified opt-in backend** on both platforms
  (smoke 76/76 in wrap 4; default stays JSONL per the decision in
  `docs/PACKAGE-WISHLIST-PULSE.md`, which lists the flip prerequisites).

**Security hardening (42%)**
- TLS: front-proxy by design (Caddy/nginx); `docs/DEPLOYMENT.md` published
  with configs, supervision and a through-proxy verification checklist;
  the actual proxy E2E run is pending a proxy install.
- **C-PULSE-16 (wrap 8):** `PULSE_BIND` is advisory -- the stdlib
  `socket_bind` binds the wildcard (its address parameter is documented
  as ignored); repro: `PULSE_BIND=127.0.0.1` -> LISTEN `0.0.0.0`.
  Ops firewalled the demo (verified safe). Address-aware bind is filed
  with the compiler/stdlib lane; PULSE then enforces loopback and adds a
  smoke check on the LISTEN address.
- Global rate limiting landed (`xiom.rate` 0.2.0, `PULSE_RATE_LIMIT`,
  429 + Retry-After, `scripts/rate_smoke.ps1` green); per-client keys wait
  on `socket_peer_addr` (stdlib stub).
- CSRF double-submit on session-authenticated mutations (403 without the
  token; smoke-verified); opt-in CORS with preflight (204).
- Field length validation for `user`/`token`; no general schema library.
- Header size/count caps landed (16 KiB / 100); no recv timeouts yet
  (stdlib queued) -- a half-open request can still hold the loop.

**Static/assets (55%)**
- Favicon served through registry `xiom.static` 0.1.0: MIME map, ETag,
  Last-Modified, Cache-Control, `If-None-Match` 304, `Range` 206/416,
  traversal guard; landing page dynamic. No directory serving yet.

**Protocol extras (0%)**
- Templates, SSE, WebSocket, REST helpers, GraphQL: not started.
  Registry has `xiom.websocket`/`xiom.realtime`; GraphQL stays behind an
  interface (compiler-gated item).

**Reliability & concurrency (35%)**
- Single-threaded sequential accept (pin has no threads/select); 64
  concurrent works only because requests are short and queued by the OS.
- **C-PULSE-14 (cross-platform, corrected in wrap 6):** the request path
  retains ~32 KB/req (Windows) / ~48 KB/req (Linux) RSS linearly; the
  earlier "Windows flat" was a soak sampling bug (`cmd.exe` wrapper; now
  fixed). Handles/fds flat; pure Vec churn flat. Candidate lane fix:
  m235 "hoist loop-body static allocas" -- retest on the next archive.
  Until then: memory limit + restart cadence for any unattended instance.
- No transport timeouts; one stalled client blocks everyone.
- No signal handling / graceful in-flight drain (test-only QUIT).
- A trap anywhere kills the process (no supervisor/restart policy).

**Testing/CI/release (88%)**
- Local, both platforms: 3 suites (x2), smoke (78), crash/reopen (6),
  soak drivers (PS + shell), rate/store soaks, 20+ probes, byte-level
  lint greps. Every script ships as `.ps1` + `.sh` (LF enforced).
- **CI live (wrap 7):** `.github/actions/setup-xiom` (SHA-pinned
  toolchain + stdlib pin + store bridge + pinned deps), `ci.yml` PR
  gates (suites x2 + smoke, ubuntu/windows), `release.yml` (guard ->
  fleet -> packages -> GitHub Release on `pulse-v*`, provenance
  attested; cut 0.1.0 end-to-end), `heavy.yml` weekly 30m + kv soaks.
- **macOS legs prepared (wrap 8):** macos-x64 / macos-arm64 (suites +
  smoke + packaging); ship with the next release.
- No coverage number, no fuzzing; DCO + the suites are the PR gates.

---

## 4. Ecosystem blockers affecting PULSE (not PULSE's own code)

| Blocker | State (2026-10-08) | PULSE impact |
|---|---|---|
| C-PULSE-04 bare `&mut Int` read -> address | OPEN | keeps `*p` discipline; blocks cursor-style parsing in lane code |
| C-PULSE-05 const-receiver `.to_str()` W005 -> abort | OPEN (worse: 0x80000003) | `convert.int_to_string` workaround stays |
| C-PULSE-06 missing struct field -> garbage | OPEN | every struct literal must list all fields |
| C-PULSE-07 module-scope package ctor -> undefined call/crash | OPEN | package aggregates stay caller-owned (Vec-holder pattern pinned by `probe_pkg_state_holder`) |
| C-PULSE-08 m212 dotted-key roots | **CLOSED on v0.64.1** (m215) | gate dash+dot green on Windows and Linux (Linux after the C-PULSE-13 home bridge); `source-roots` kept only as belt-and-braces |
| C-PULSE-09 xiom.session store integration crash via wrapper modules | **CLOSED + SWAP DONE (2026-10-09)** | `src/session.xi` now wraps the registry `xiom.session` 0.1.0 store behind the same HTTP contract (module renamed `xiom.pulse.sessions` for C-PULSE-12); `probe_adopt_smoke` + suites x2 + smoke 78/78 green on BOTH platforms; ships in 0.1.1 |
| C-PULSE-10 xiom.kv kv_get Str corruption + bytes truncation | **CLOSED on v0.64.1** (m217) | `probe_pkg_kv` green; kv backend verified incl. the 20m soak |
| C-PULSE-11 package type alias invisible cross-module (defaults to i64) | **fixed in v0.64.1** (m216) | alias design compiles; swap re-tries on the C-PULSE-09 schedule |
| C-PULSE-12 module last-segment shadows an imported alias | OPEN (design around) | PULSE renamed the app module; import-alias syntax filed in the stdlib wishlist |
| C-PULSE-13 Unix pkg-home mismatch | **CLOSED on v0.64.2 (m232)** | `xiom pkg` resolves the compiler home; bridge removed from the WSL box AND the CI setup action; verified: installs land in `<home>/packages`, doctor OK |
| C-PULSE-14 request-path RSS growth | **Windows FIXED on v0.64.2 (flat, -240 B/req over 206 req); Linux OPEN and worse (~87 KB/req steady vs ~48 on v0.64.1)** | repros `rss_probe` twins + `probe_alloc_loop`; retest on the next archive (m235 was not in v0.64.2); the Linux demo keeps `MemoryMax` + restart |
| C-PULSE-16 `PULSE_BIND` not enforced (stdlib `socket_bind` wildcard-only) | **NEW, all platforms** | ops mitigated with the host firewall (demo verified); address-aware bind filed upstream; fix + LISTEN-address smoke check with the next release |
| C-PULSE-02 deps not mapped to catalog roots | **CLOSED on v0.64.1** (gate green; m212/m215) | dotted `[dependencies]` resolve to installed stores; PULSE keeps `source-roots` until a no-source-roots app build is verified |
| No toolchain exe icon (`xiom --icon`) | gap, workaround shipped | pinned rcedit in `build.ps1` + CI; new official icon art; exe icon verified locally |
| stdlib deadlines/timeouts, write_all, request parser, real flush | queued wave | slow-client guard, streaming, HTTP parse duplication, log lag |
| `xiom.router` 0.1.0 | **LIVE and adopted by PULSE** (probe 8/8, suites x2) | routing hardened; wildcards/groups remain package roadmap |
| `xiom.session`/`static`/`http.middleware` | static + middleware **adopted**; session single-module green, store integration gated | module replacement + middleware framework |
| Concurrency primitives (threads/select) | absent on the pin | caps throughput; single-threaded design |

Resolved on v0.64.0: C-PULSE-01, runtime-link (R65), crypto-link (m195).
Resolved on v0.64.1: C-PULSE-08, C-PULSE-10, C-PULSE-11, C-PULSE-02
(dependency-root gate green; no-source-roots app build pending).
`xiom.http` 0.1.2 republished and re-added (probe green on both
platforms) -- no known-red package gates remain; C-PULSE-13 is routed to
the compiler/installer lane.

---

## 5. Milestones (what "done" means next)

| Milestone | Criteria | State |
|---|---|---|
| **M1 -- Thin slice** | plaintext HTTP/1.1, routes, JSON, 404/405, curl + 64 concurrent + soak | **DONE** (2026-10-05) |
| **M2 -- App skeleton** | router, envelope, config, log, metrics, audit, sessions, JWT | **DONE** (core; hardening items above) |
| **M3 -- Storage** | durable store, schema, crash/reopen, soak | **DONE core** (JSONL; query/migrations pending) |
| **M4 -- Hardening** | timeouts, limits, keep-alive, rate limit, CORS/CSRF, validation, graceful shutdown, latency metrics | ~74% (registry metrics latency preset, static ETag/Range/304, CSRF via registry, caps, histogram, HEAD, stdlib write_all + parser, audit rotation, CLI surfaces, schema helper, TE smuggling guard; recv timeouts + signal handling blocked on stdlib) |
| **M5 -- Production ops** | TLS (proxy integrated + tested), CI pipeline, packaging, config files, runbooks, backup/restore | ~38% (TLS E2E on Windows **and** Linux; `.sh` twins; deployment runbook + ops answers; `--version`/`--check-config`/build-info; release packager + backup/restore tooling; `deploy/Dockerfile` + `PULSE_BIND`; CI pending greenlight) |
| **M6 -- Public release** | self-host compiler + mature stdlib/packages, full security review, versioned API, docs site | not started (owner gate) |

---

## 6. Production gates checklist (what 100% requires)

- [x] HTTP/1.1 plaintext service with parse+response builder
- [x] Routing with params, 404/405
- [x] Uniform JSON errors
- [x] Cookie sessions + JWT HS256
- [x] Durable append store with crash-safe reopen
- [x] Structured logs, metrics endpoint, audit trail
- [x] 1h load soak with flat memory/handles (Windows; Linux RSS growth
      open -- C-PULSE-14)
- [x] Request/header caps + query-string parsing
- [x] Rate limiting (global token bucket; per-client blocked on `socket_peer_addr`)
- [x] CSRF double-submit + opt-in CORS
- [ ] Keep-alive + chunked responses (Expect: 100-continue + request-chunked decode done)
- [ ] Schema validation library (field length caps landed)
- [ ] Real timeouts (recv deadline) and slow-client shedding
- [ ] Rate limiting + CORS + CSRF + security headers
- [ ] Schema validation for all inputs
- [ ] Credentials + RBAC; session persistence/rotation
- [ ] Graceful shutdown/signal handling + supervisor story
- [x] TLS end-to-end test through the proxy (Windows nginx + Linux nginx 1.24, 11/11 both)
- [ ] CI (suites+soak on push) + release packaging
- [ ] Static/templates/SSE/WS/REST extras (framework surface)
- [ ] Crash/chaos suite (kill -9 matrix, disk-full, corrupt store)
- [ ] Stable self-hosted toolchain (ecosystem gate)

---

## 6b. Integration seams for future bindings (design note, 2026-10-08)

PULSE keeps every external-system touch behind exactly one module so a
future **bindings-lane** package (`E:\xiom-packages\bindings`, worktree of
the packages lane) can replace the implementation without route changes:

| Seam | Module | Current impl | Binding replacement path |
|---|---|---|---|
| Event store | `src/store.xi` | JSONL append/compact (crash-safe) | same 6-fn API backed by a DB/KV binding package |
| Sessions | `xiom.pulse.session` | local vectors (`xiom.session` store swap deferred, C-PULSE-09) | store-backed sessions behind the same API |
| Static assets | route 14 via `xiom.static` | registry package | unchanged |
| CSRF/CORS | `src/cors.xi` + `xiom.http.middleware` | registry package | unchanged |
| Outbound calls | (none today) | -- | a future `src/outbound.xi` seam |

Rules: bindings arrive as registry packages (packages lane -> bindings
lane), are wrapped once per seam, and never get linked into route code.
Requests are tracked in `docs/PACKAGE-WISHLIST-PULSE.md` ("Bindings
lane").

## 7. How this score is updated

At every PULSE wrap: adjust only the areas with new **evidence** (soak,
smoke, suite, or repro), recompute the weighted total, and note the delta
in one line at the top. Evidence lives in `SESSION.md`, `docs/repro/`,
`probe-logs/`, and the smoke/suite scripts. Do not raise an area for
"code written" -- raise it when a test or soak proves the behavior.
