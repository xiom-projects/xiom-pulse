<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> packages lane: wishlist + consumer findings

**Relay:** hand this file to the packages-lane session. PULSE consumes
packages from the registry only (never vendored, never edited). Evidence
paths are from `E:\xiom-projects\xiom-pulse`.

**Pin:** compiler v0.63.1, stdlib `15cb889`, registry
`https://registry.xiom-lang.org` (install flow verified: sha256 + ed25519
signature checks pass; trust fingerprint `4f:3b:47:f3:ae:17:b1:3c`).

## Consumer-visible defects

| Date | Package | Finding | Status |
|---|---|---|---|
| 2026-10-05 | `xiom.http` v0.1.0 | parser missing `use xiom.http.types;` + bare `&mut Int` cursor + no parser KATs | **FIXED in 0.1.1** (eco-v0.1.59, run 37335349031); PULSE consumer re-verified: `tests/probes/probe_pkg_http.xi` compiles importing only `xiom.http.parser` and parses (path=/api/echo, bodylen=7), exit 0. Parser KATs 40/40 per the packages lane. |
| 2026-10-05 | `xiom.http` v0.1.0 | `src/server.xi` shell (no accept loop/routing) | **DOCUMENTED STUB in 0.1.1** (README contract: consumers own transport; routing deferred to `xiom.router`). PULSE builds its own transport. |

**Positive:** `xiom.cookie` v0.1.1 (8/8), `xiom.jwt` v0.1.1 structural (8/8), and now
`xiom.jwt` **v0.2.0 HS256 adopted in PULSE** (`tests/probes/probe_pkg_step2.xi`
11/11 and `tests/test_app.xi` 6 jwt checks green): `jwt_sign_hs256`,
`jwt_signature_valid_hs256`, `jwt_verify_hs256` with the verified payload
returned. `xiom.rate` v0.2.0 (KeyedBuckets/KeyedWindows) recorded for the
next hardening slice. **`xiom.router` 0.1.0 adopted 2026-10-05 with a clean
first consumer pass** (`tests/probes/probe_pkg_router.xi` 8/8: match, param
capture, 404, 405, allowed-methods, invalid-pattern rejection); PULSE's
`src/router.xi` is now a thin wrapper and its suites x2 + smoke 44/44 stay
green. No hotfix needed.

## Ops scope confirmation (requested by the packages lane)

PULSE (consumer) confirms the four new package names and scopes it needs:

| Name | PULSE consumer scope |
|---|---|
| `xiom.router` | Replace `src/router.xi` (exact + `:param`, 404/405 + Allow). Needs: registration-order first match, allowed-methods helper. |
| `xiom.session` | Replace `src/session.xi` (id via crypto, TTL, cookie binding). Needs: explicit TTL, memory backend, rotate/drop. |
| `xiom.static` | Later slice (static file serving behind the proxy). |
| `xiom.http.middleware` | Later slice (request-id, access log, CORS, CSRF helpers) over PULSE's envelope/router. |

The registry allowlist delta itself is the owner's call; this table is the
consumer-side approval the packages lane asked for.

**Adoption blocker to track (compiler-side):** installed packages are not
mapped into the compiler's module catalog (C-PULSE-02 in
`docs/COMPILER-FINDINGS-PULSE.md`); PULSE must list each installed
package's `src/` in `xiom.toml` `source-roots`. Registry adoption will stay
manual until that lands.

## Proposed packages (PULSE needs; reusable by any XIOM service)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence from PULSE |
|---|---|---|---|---|
| `xiom.router` | Route table for HTTP servers: exact + path-parameter routes (`/api/items/:id`), method matching, aggregated 404/405, deterministic first-match order | framework/app concern; will grow (groups, wildcards) and should not sit in the zero-dep core | xiom.std | PULSE `src/server.xi handle_route` is an if/else chain with hand-rolled 404/405; Step 2 needs params/middleware hooks |
| `xiom.session` | Server-side session store: id generation (crypto), TTL/expiry, memory backend, cookie binding, rotate-on-login | app policy (storage, lifetime, security posture), not language core | xiom.std, xiom.cookie, xiom.crypto | S9 lists auth/session; PULSE Step 2 cookie+session; currently would be PULSE-local |
| `xiom.jwt` v0.2 (or `xiom.jwt.hs256`) | HS256 sign + verify on top of `xiom.jwt`'s structural decode: alg allowlist, `exp`/`nbf` enforcement, constant-time MAC compare, claim validation helpers | crypto policy + token grammar; `xiom.jwt` already owns decode; signing belongs beside it, not in stdlib | xiom.std, xiom.jwt, xiom.crypto (SHA-256/HMAC now link under `XIOM_RUNTIME_DIR`) | `xiom.jwt` v0.1.1 description: "no signature verification"; PULSE Step 2 JWT is blocked on it |
| `xiom.ratelimit` | Keyed rate limiting (per-IP/route/user): token bucket + fixed window, explicit clock injection, 429 envelope, deterministic tests | middleware/policy, not core | xiom.std | S9 lists rate; PULSE Step 2+ hardening; no-registry equivalent today |
| `xiom.metrics` | Service metrics: counters/gauges/histograms with labels + Prometheus text exposition + scrape endpoint helper | infra/ops concern | xiom.std | S9 metrics; PULSE Step 2 metrics + Step 3 soak observability |
| `xiom.static` | Static file serving: MIME mapping, ETag/Last-Modified, Range, path-traversal guard, `Cache-Control` policy | app-level policy; filesystem + HTTP semantics | xiom.std (stdlib has `xiom.net.mime` to reuse) | S9 static; PULSE later slices |
| `xiom.kv` | Embedded, pure-XIOM log-structured KV store: append-only segment write, crash-safe reopen, tombstones, compaction, optional snapshot. PULSE Step 3 storage needs a durable local store; `xiom.bolt` v0.1.2 is a read-only bbolt page parser, and `xiom.sql` is not in the registry (checked 2026-10-05) | storage engine = package domain; must not drag FFI into stdlib | xiom.std | PULSE Step 3 ("most-tested option first"): without it, PULSE ships a JSONL append store locally and the ecosystem lacks an embedded store for any service |
| `xiom.http.middleware` | Composable middleware chain over request/response envelopes with built-ins: request-id, structured access log, recover-to-500, CORS, CSRF token helpers | app framework concern; needs router/envelope types first | xiom.std (+ router types if shared) | S9 lists middleware/cors/csrf/xss; PULSE Step 2 audit/log envelope |

## Suggested order for the packages lane

1. ~~`xiom.http` 0.1.1~~ **DONE** -- consumer re-verified by PULSE.
2. ~~`xiom.jwt` HS256~~ **DONE (0.2.0, adopted by PULSE)**.
3. ~~`xiom.router` 0.1.0~~ **DONE -- live and adopted by PULSE**
   (probe 8/8, suites x2, smoke 44/44; no hotfix needed).
4. `xiom.http.middleware` (next), then `xiom.session`, `xiom.rate` adoption,
   `xiom.metrics` 0.2.0, `xiom.static`, and `xiom.kv` (embedded store).

**Registry notes (checked 2026-10-05):** `xiom.sql` is not published
(`xiom pkg info xiom.sql` -> empty); `xiom.bolt` v0.1.2 is pure-XIOM but
read-only (bbolt page parser); no embedded writable KV/storage package is
available. PULSE Step 3 therefore starts with a zero-dependency JSONL
append store and files `xiom.kv` above.

## Contract notes for the packages lane

- PULSE consumes from the registry only. If a package is incubating that
  is fine; publish it and PULSE will test it as a consumer and file rows
  here.
- Please include a 3-line consumer snippet in README (the exact `use`
  lines) -- (a)/(b) above were only visible from a consumer project, not
  from the package's own suite.
- New packages should stay stdlib-only or declare deps explicitly; PULSE's
  `xiom.toml` currently wires each installed package `src/` manually
  (C-PULSE-02).

## Delta 2026-10-07 (registry wave, Linux/WSL session)

**Adopted and green by PULSE (consumer-verified):**

| Package | Probe (all x1, green) | Use in PULSE |
|---|---|---|
| `xiom.metrics` 0.2.0 | `probe_pkg_metrics.xi` -- counter/gauge/histogram/labels/registry/find/exposition/latency-bounds | `src/metrics.xi` wrapper: labeled status counters, 11-bound latency histogram, Prometheus exposition; uptime gauge at render |
| `xiom.http.middleware` 0.1.0 | `probe_pkg_middleware.xi` | CSRF token + constant-time validate (`src/session.xi`); CORS header block (`src/cors.xi`) |
| `xiom.static` 0.1.0 | `probe_pkg_static.xi` | `/favicon.ico` through `static_serve`: mime, ETag/Last-Modified/Cache-Control, If-None-Match 304, Range 206/416, traversal guard |
| `xiom.session` 0.1.0 | `probe_pkg_session.xi` (green) | **store integration deferred** -- C-PULSE-09 crash when driven from wrapper modules (inline green); local store retained |
| `xiom.kv` 0.1.0 | `probe_pkg_kv.xi` (**green on v0.64.1 and v0.64.2**) | **adopted as the opt-in store backend** (`PULSE_STORE_BACKEND=kv`, `PULSE_KV_DIR`, `PULSE_KV_PREFIX`; sequence-keyed records, native compact; JSONL stays the default fallback). v0.64.0 defects (C-PULSE-10) were fixed by m217 |

**API notes for the packages lane:**

- `static_resolve_path` rejects a leading `/` as "absolute"; consumers must
  strip it from the request target (documented in the probe). Worth a
  README line.
- `xiom.kv` defect bundle: `docs/repro/kv-get-str-corruption/` -- a
  kv_get-after-kv_put case with values >= 8 bytes and a multi-key
  overwrite case would have caught both symptoms in the package's own
  suite.
- `xiom.session` conformance: add a two-module consumer case (state owner
  module + thin wrapper module) matching PULSE's integration shape if the
  crash turns out to be reproducible outside the compiler.

**Roadmap status:** items 1-3 done; of item 4, metrics/middleware/static
are adopted, session + kv are gated on the C-PULSE-09/10 fixes.

## Bindings lane (added 2026-10-08)

A dedicated **bindings lane** now exists as a worktree of the packages
lane: `E:\xiom-packages\bindings`. Its purpose is **binding packages** --
native integration layers that hook XIOM into external systems (databases,
queues, drivers).

**Routing rule for PULSE:** binding requests are filed in this wishlist (or
the package lane's tracker) like any other request; the packages lane
forwards them to the bindings lane. PULSE never links native code
directly -- bindings must arrive as registry packages consumed exactly
like the current deps (`xiom.toml` `[dependencies]` + the `source-roots`
workaround until C-PULSE-08's m215 ships in an archive).

**Likely first PULSE binding requests (heads-up; final-stage work):**
- A durable database/KV client binding (SQLite/Postgres or similar) to
  back the event store and sessions beyond JSONL. Until then PULSE keeps
  the JSONL store (the documented fallback) and the `xiom.kv` defect gate
  (`probe_pkg_kv`).
- Optional outbound HTTP client binding for webhooks/proxying -- PULSE is
  inbound-only today, so this is not yet needed.
- TLS is intentionally NOT a binding for PULSE: the front proxy terminates
  TLS (docs/DEPLOYMENT.md); the app stays plaintext on loopback.

**Consumption contract (PULSE side):** each binding is wrapped in exactly
one PULSE module behind a stable PULSE API; route code never calls a
binding directly. The seam map is in `docs/PROGRESS.md` ("Integration
seams for future bindings").

## Delta 2026-10-08 (Linux v0.64.1 sweep) -- NEW finding C-PULSE-13 + kv soak/decision

### C-PULSE-13: Unix shipped-installer layout -- `xiom pkg` and the compiler resolve different XIOM homes

| Field | Detail |
|---|---|
| **Class** | consumer-visible install-layout defect (Linux/Unix shipped installer; Windows unaffected) |
| **Symptom** | after `xiom pkg install xiom.rate@0.2.0` succeeds, `[dependencies]` still resolve zero catalog roots: the m212 gate (`docs/repro/dep-roots-name-form/`) fails both variants with 6x `T001 undefined variable 'rate'`, and `xiom doctor` reports `XIOM_HOME /home/lefteris/.local/share/xiom` + `[--] No packages` |
| **Root cause (lane source, read-only)** | `xiom-pkg` (`crates/xiom-pkg/src/registry.rs::resolve_package_cache_dir`, :1103-1121) defaults to **`$HOME/xiom/packages`**, while the compiler (`crates/xiom-graph/src/paths.rs::xiom_home`, CRB-3c :184-194) picks the **first existing candidate** -- the canonical `~/.local/share/xiom` install root wins over the legacy `~/xiom` candidate -- and dependency roots resolve under `<xiom_home>/packages` (`manifest.rs::dependency_roots_under`). Windows agrees (`%LOCALAPPDATA%\xiom` for both), so this is Unix-only |
| **Evidence** | install output: `Installed xiom.rate v0.2.0 to /home/lefteris/xiom/packages/...`; `xiom doctor` -> "No packages"; gate red in `probe-logs/linux-sweep-20261008T132937Z/` (pre-repair, kept for the record); with `XIOM_HOME=/home/lefteris/xiom` both variants `--check` PASS; after bridging (below) the full gate passes in `probe-logs/linux-sweep-20261008T134143Z/` |
| **PULSE workaround (applied on WSL)** | `ln -s /home/lefteris/xiom/packages /home/lefteris/.local/share/xiom/packages` -- doctor then reports `[OK] packages directory`, and the m212 gate + default resolver work; setting `XIOM_HOME=~/xiom` also works but skews install-root discovery |
| **Ask** | unify on one resolver: either `xiom-pkg` installs to `xiom_graph::paths::xiom_home().join("packages")` (preferred -- keeps the canonical layout authoritative), or the CRB-3c candidate order gains a "candidate that already contains `packages/`" tiebreak, or the Unix installer creates/points `$XIOM_HOME/packages`. Please also re-run `xiom doctor` on a fresh Unix install as the regression check. **(Routed to the compiler/installer lane 2026-10-08 per the packages lane.)** |

**Note:** prior Linux sessions never surfaced this because PULSE's
`xiom.toml` lists every installed package's `src/` explicitly (the
C-PULSE-02 workaround bypasses the resolver); only the m212 gate
exercises dependency-root resolution for real, and it was expected-red
on v0.64.0 anyway.

### `xiom.kv` 0.1.0 -- 20m Linux soak green; default decision

- Linux v0.64.1: kv-mode smoke **73/73**, store-soak **20m green** (756
  writes / 0 fail; `count_after_compact=count_after_reopen=756`,
  0 mismatches, native compact, hard-kill reopen intact, `server_exit=0`,
  segment `evt-seg-0000000019.kv` 70 KB). Windows v0.64.1: kv smoke 73/73
  + 20s soak green (previous wrap).
- **Decision (with evidence): the default stays `jsonl`; kv remains the
  verified opt-in backend.** The flip was gated on the operations surface
  first. **Prerequisite progress (wrap 5b):** `deploy/Dockerfile` now
  sets `PULSE_KV_DIR=/data/pulse-kv`; `scripts/backup.{sh,ps1}` are
  kv-aware (`--kv-dir`/`-KvDir`, env-driven default when
  `PULSE_STORE_BACKEND=kv`, whole-dir snapshot at `kv-store/` with
  per-file sizes+sha256 -- verified on both platforms); `DEPLOYMENT.md`
  documents the kv store, snapshot and restore procedure. Soak evidence:
  Linux 20m (756/0) + **45m (977/0, compact + hard-kill reopen intact,
  single 90 KB segment; `probe-logs/kv-soak-45m.summary.txt`)** + Windows
  20s; aggregate Linux ~66 min. Remaining gate: the >= 24h aggregated bar
  (and the `crash_test` jsonl-pin note -- `store_soak` is the kv
  crash/reopen contract). Re-evaluate at the next compiler release.
- Cosmetic consumer note: `store_soak.sh` prints a `store-soak.jsonl: No
  such file` stderr line in kv mode when computing `store_bytes` (fixed
  this wrap in the `.sh` twin to match the `.ps1` empty value).

### Consumer-visible status on v0.64.1 (Linux, post-repair)

All ten adopted packages' probes green on the Linux archive
(state-holder, session-inline, adopt-smoke, stdlib-server-parse, schema,
audit-rotate, kv, middleware, metrics, static, session). The `xiom.http`
0.1.1 red gate (extern-unsafe enforcement on v0.64.1) was **closed by the
0.1.2 republish** -- see the wrap-3 subsection below (package re-added).

### Consumer-visible status on v0.64.2 (2026-10-09) -- all green, both platforms

Re-run after the v0.64.2 adoption: the **full probe fleet is 11/11 on
Windows AND Linux** (state-holder, session-inline, **adopt-smoke**
(steps 1..10, exit 0 -- C-PULSE-09 closed), stdlib-server-parse, schema,
audit-rotate, kv, middleware, metrics, static, session), plus the m212
gate, suites x2, smoke 78/78, crash 6/6 on both platforms. No package
reds remain; `xiom.http` 0.1.2, `xiom.kv` 0.1.0, `xiom.session` 0.1.0
and the rest all consume cleanly on the v0.64.2 archive.

### C-PULSE-13 CLOSED (v0.64.2, m232) -- verified 2026-10-09

`xiom pkg install` now resolves the SAME home as the compiler
(`xiom_graph::paths::xiom_home()`), so the Unix split is gone: verified
on WSL (`xiom pkg install xiom.http@0.1.2` -> `~/.local/share/xiom/packages`,
`xiom doctor` OK) and Windows (`%LOCALAPPDATA%\xiom\packages`). The local
bridge was removed from the WSL box AND from the CI setup action
(`.github/actions/setup-xiom`); installs + full builds work without it.
Operational note kept: a toolchain re-extract/repair removes non-archive
subdirs (like `packages/`) -- verify with `xiom doctor` and re-add with
`xiom pkg install` after any toolchain maintenance.

### Delta 2026-10-09 (wrap 11b) -- durable-DB binding ask SERVED; HTTP client available

Packages lane relay (via owner) + registry verification (`xiom pkg info`,
signed):

- **`xiom.sqlite` 0.2.0** -- SQLite bindings, vendored amalgamation
  3.53.4, signed (`0.3.0` pending their batch 22).
- **`xiom.libpq` 0.2.0** -- Postgres via dynamic loader (SKIP when the
  runtime lib is absent), signed.
- **`xiom.odbc` 0.2.0** -- ODBC via dynamic loader (Windows-first),
  signed.
- **`xiom.http` 0.1.5 -- RESOLVED + ADOPTED (2026-10-10).** 0.1.5
  (eco-v0.1.125) ships the curl-free `bridge/xiom_http_shims.c` plus the
  verified consumer recipe (`--c-source <installed>\bridge\xiom_http_shims.c
  --link curl --link-path <scratch-with-curl.lib>`; curl-for-win
  `libcurl.dll.a` copy, kit DLL beside the exe, `CURL_CA_BUNDLE` for
  TLS). PULSE bumped the pin (manifest + CI + package.xi) and proved the
  real client end-to-end on **both platforms** with the new evidence-only
  runner `scripts/outbound_transport_probe.{ps1,sh}`: guard blocks
  loopback -> `PULSE_HTTP_ALLOWLIST` opt-in -> real GET 200 from a local
  PULSE server through libcurl 8.22.0. Remaining ask domain: the general
  C-consumption-hook family (auto-applying `port.args.json` so consumers
  need not pass `--c-source`/`--link` by hand) stays with the
  compiler/pkg side.

**Consumer caveat filed by the packages lane:** the vendored-C sqlite
package needs a `--c-source` build-hook story for registry consumers
(beyond the lane runner's `port.args.json`) -- i.e., sqlite adoption in
PULSE waits on that hook or a documented consumption recipe; the
dynamic-loader packages (libpq/odbc) have no such issue. Roadmap mapping:
0.3 data drivers now have concrete SQL candidates; the 0.2 HTTP client
base is `xiom.http` 0.1.4. Wrap-behind-one-module contract acknowledged
both ways; no PULSE-side changes needed before the 0.2 cycle starts.

**Bindings-lane addendum (same day):** the `xiom.sqlite` README carries
the exact 3-line consumer snippet plus the one required `--c-source`
build flag; the ergonomic fix for that flag is filed on their side --
adoption is therefore documented, not blocked on a mystery. xiom.http
0.1.4 covers outbound (no TLS/HTTP binding needed). The bindings lane
continues on the next sector (accelerators unlock after the
`xiom.vectors` extraction lands) and keeps fresh from main.

### xiom.http 0.1.2 (eco-v0.1.103) -- republish verified, re-added (wrap 3)

- 0.1.2 carries the extern-unsafe compat fix (64 wraps + unsafe-internal
  helpers). PULSE verified on v0.64.1 **both platforms**:
  `probe_pkg_http` GREEN (Windows + Linux), suites x2 + smoke 73/73 green
  with the package **re-added** to `xiom.toml`/`package.xi` (sha256
  `994271f0b6507ea2f724b745f5c881eeb021f7b1ee49bdc2c9df0565c3a8e1a6`,
  signature verified). The `xiom.http` breakage row in the compiler
  findings doc is closed -- clean consumer pass, no hotfix needed on the
  PULSE side.
- **C-PULSE-13 routing:** the packages lane routed the Unix pkg-home
  mismatch to the **compiler/installer lane** (not a package defect);
  recorded in `docs/COMPILER-FINDINGS-PULSE.md`.

> **Migrated (2026-10-10):** cross-lane coordination moved to the private xiom-relays bus (`python tools/relay.py view --lane packages`). The remaining open rows migrate there on the doorbell; this file is frozen history.
