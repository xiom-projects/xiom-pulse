# XIOM PULSE -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-05; **last wrap:** 2026-10-10 wrap 14 (0.2 PULSE-side slate COMPLETE; first 0.3 interop probes green; 0.1.2 shipped; demo live), by the PULSE consumer lane.

## 0. STATE (2026-10-10 wrap 14) -- CURRENT STATE digest (supersedes the log below)

- **Repo:** `E:\xiom-projects\xiom-pulse`, **PUBLIC** since 2026-10-09
  (owner flipped it); rulesets live -- `protect-main` requires DCO +
  `ubuntu-latest` + `windows-latest`, `protect-release-tags` covers
  `pulse-v*` (org-admin pushes bypass; never move a tag -- if a tag's CI
  fails, fix and cut the next patch version). DCO `-s` commits; identity
  Lefteris Notas <lefterisnotas@gmail.com>. Head: `6171304` + the wrap
  commit on top (see `git log`); wrap-14 commits: pagination `9301052`,
  idempotency `a6a55b9`, `/v1` `602c9e6`, outbound `bf6d9b0`, uploads
  `130a54b`, interop `6171304`.
- **Toolchain:** **v0.64.2 on BOTH Windows and Linux/WSL** (dl live; pins
  in `docs/OPS-REQUEST.md` D.1 and every workflow; macOS shas pinned for
  the gated legs). **C-PULSE-13 CLOSED (m232):** package home unified, no
  bridge anywhere (CI included); after any toolchain maintenance verify
  the store (`xiom doctor`; re-add with `xiom pkg install` -- a re-extract
  removes non-archive subdirs like `packages/`). Stdlib lane `d54929d`
  (wave 97); the v0.64.2 pairing is `4dd8844` -- exact/CI checks use the
  pin (`export XIOM_STDLIB=<pinned checkout>`). `dev-env.{ps1,sh}` respect
  explicit overrides; `dev-env.sh` finds `~/.local/bin/xiom`.
- **Shipped release: 0.1.2** (tag `pulse-v0.1.2`, 2026-10-09): session
  store swapped to registry `xiom.session` 0.1.0, v0.64.2 rebuild
  (Windows request-path memory flat), `PULSE_BIND` address-only
  validation, official icon embedded (pinned rcedit, local + CI).
  `pulse-v0.1.1` exists but was never released (its CI gate failed on a
  stale version literal; tags are immutable) -- documented in
  CHANGELOG.md. dl mirror live (`dl.xiom-lang.org/pulse/...`), GitHub
  Release has assets + `SHA256SUMS` + provenance.
- **Live demo:** pulse.xiom-lang.org serves the website page **through
  PULSE** (nginx -> loopback; landing via `PULSE_LANDING_PATH`, JSON via
  `/health` + `/api/version`); currently running **0.1.0/cc3e741** -- ops
  redeploys to 0.1.2+ at leisure (site buttons/badge auto-follow
  `latest.json`). Linux memory still open: keep `MemoryMax` + restart.
  orbitdb./xvector. phase-1 pages live (driver work queued for 0.3);
  docs.xiom-lang.org = versioned compiler-docs root, PULSE docs render
  at pulse.xiom-lang.org/docs/; registry.xiom-lang.org live (490 pkgs;
  GitHub sign-in / SQLite social layer implemented in the registry lane).
- **Current focus: 0.2.0 "the release that matters"** (owner direction):
  **macOS x64 + arm64 artifacts plus the gap slate.** macOS gate (all
  upstream; patch-precise fix sketches filed): stdlib
  `runtime/xiom_runtime.c:4222` (`_SC_AVPHYS_PAGES` Linux-only), stdlib
  `runtime/fp128_helpers.c` (x86 asm on arm64), compiler
  `@llvm.memset.p0i8.i64` emission (`xiom-codegen` emitter.rs:859,
  expr.rs:3774, stmt.rs:713/1131; also warns on Linux CI/llvm-16). When a
  compiler/stdlib pairing carries them: set
  `RELEASE_BUILD_MACOS=true`, dry-run all four legs, then 0.2.0.
- **0.2 PULSE-side progress:** DONE -- OpenAPI 3.1 served
  (`/openapi.json`, version token substituted at serve time) + `pulse
  openapi`; full CLI set (`routes`, `version`, `check-config`); additive
  error `status` in every envelope (incl. the 405 Allow path); official
  icon adopted + embedded; **pagination `Link` on `GET /api/events`**
  (seq-in-record cursor: durable `seq`, legacy fallback ordinal,
  `next_cursor` + RFC 8288 `Link rel="next"`, `?before=` walk-back,
  `400 invalid_cursor`); **idempotency keys on event writes**
  (`Idempotency-Key` header, durable `idem` marker in the record, replay
  with `deduplicated:true`, `400 invalid_idempotency_key`); **`/v1`
  versioned alias** (every route resolves under both forms; new surfaces
  go `/v1` first; `Link` preserves the client's prefix); **outbound
  client base** (`xiom.http` **0.1.4**, SSRF guard
  `xiom.pulse.outbound` + `probe_outbound_guard` in the fleet;
  libcurl transport seam isolated pending the `--c-source` build hook);
  **multipart uploads** (`POST /api/uploads` + `/v1` alias; PULSE-side
  parser, per-part/part-count caps, generated on-disk names, stable
  415/400/413 errors); fleet **12/12**, smoke **119/119** on both
  platforms (Linux run with the pinned stdlib). **The 0.2 PULSE-side
  slate is COMPLETE** -- next: docs/public-set refresh, then the 0.2.0
  cut when macOS is green (upstream gates below).
- **0.3 interop (first tranche, wrap 14):** ORBITDB + XVector consumer
  conformance probes built and GREEN both platforms --
  `tests/interop/orbitdb/probe_pkg_orbitdb.xi` (**39/39**; roundtrip +
  reopen x2 at 1k keys, query edges, open/order/stale-handle errors, txn
  commit/abort, delete persistence) and
  `tests/interop/xvector/probe_pkg_xvector.xi` (**30/30**; exact Flat
  roundtrip, top-k edges, dimension limits, delete/re-add, duplicate-id
  overwrite, WAL persist/recover, torn-tail prefix). Source-level
  composition (nested `xiom.toml` + relative `source-roots`; lanes'
  pattern), local-only until the packages publish. Trap note filed in
  both relays: `search(k=0)` / `create_collection(dim=0)` are contract
  traps, not Err. NEXT tranche: orbitdb hard-kill harness (§5.2/3),
  xvector filters (§5.2) + hybrid join (§5.9), then the 0.3 drivers.
- **Bug gates:** C-PULSE-08/10/11 CLOSED; **C-PULSE-02 CLOSED**
  (no-source-roots build verified); **C-PULSE-09 CLOSED + swap shipped**
  (fleet 11/11 both platforms); **C-PULSE-13 CLOSED (m232)**; **C-PULSE-14
  split on v0.64.2**: Windows flat, **Linux still grows (~87 KB/req
  steady; worse than v0.64.1)** -- retest on the next archive;
  **C-PULSE-16 OPEN** (`PULSE_BIND` advisory; address-aware bind filed;
  demo firewalled); C-PULSE-12 open (rename workaround used twice;
  import-alias syntax ask); **C-PULSE-17 NEW** (`io.list_dir` returns
  dangling names on v0.64.2 -- repro
  `docs/repro/io-list-dir-dangling/`; PULSE avoids list_dir entirely).
- **Score:** ~55.4% production grade (`docs/PROGRESS.md`).
- **Stores:** jsonl = default; kv = verified opt-in both platforms
  (20m + 45m Linux soaks); flip still gated on the recorded
  prerequisites. **`xiom.http` 0.1.4 in-repo** (bumped in the 0.2
  outbound unit; client calls still need the `--c-source` bridge, see
  the wishlist); all ten package gates green.
- **Wrap 4 (chunked + manifest + soak):** `Transfer-Encoding: chunked`
  REQUEST decoding landed (caps, extensions ignored, trailers validated;
  TE+CL -> 400; other codings -> 501) with smoke **76/76** on both
  platforms (test_http +11 parse cases, route cases in test_app);
  `xiom.toml` `source-roots` RETIRED -- the manifest has no machine
  paths (C-PULSE-02 closed). The fresh 30m Linux HTTP soak surfaced
  **C-PULSE-14** (see bug gates; the "Windows flat" comparison there was
  later invalidated by the wrap-6 soak-sampling bug). Evidence:
  `probe-logs/soak-http.summary.txt` + the progress curve; runtime repro
  `tests/probes/probe_alloc_loop.xi`.
- **Wrap 5 (config validation):** invalid values now warn at startup and
  in `--check-config` (port/uint/TTL/bool/enum; test_app +8 checks, smoke
  **78/78** on both platforms). Configuration 80 -> 85.
- **Wrap 5b (kv ops surface):** Dockerfile exports
  `PULSE_KV_DIR=/data/pulse-kv`; `backup.{sh,ps1}` are kv-aware
  (`--kv-dir`/`-KvDir`, env default, `kv-store/` snapshot with per-file
  hashes; verified both platforms); `DEPLOYMENT.md` covers the kv store +
  snapshot/restore and the current Linux systemd guidance. Flip still
  gated on a longer kv soak (crash/reopen covered by `store_soak`).
- **Wrap 6 (C-PULSE-14 correction + tools):** the Windows soak sampler
  measured the `cmd.exe` wrapper, not the server -- all historical
  "flat memory" numbers are invalid and the leak is **cross-platform**
  (~32 KB/req Windows, ~48 KB/req Linux). Fixed `soak_http.ps1` +
  `concurrent.ps1`; added `scripts/rss_probe.{sh,ps1}` (steady-state
  growth per request in ~2 min, either OS). m235 in the compiler lane is
  the candidate fix (loop-body static allocas) -- retest on the next
  archive. Reliability 40 -> 35, Testing 82 -> 80. Also: **45m kv soak
  green** (977/0, compact + hard-kill reopen intact, single 90 KB
  segment) -- the flip gate is now only the >= 24h aggregated bar.
- **Wrap 7 (release pipeline, owner-greenlit demo sequence):** CI infra
  committed -- `.github/actions/setup-xiom` (pinned v0.64.1 toolchain,
  SHA256-verified per platform, stdlib checkout at `STDLIB_VERSION`
  `4dd884423ab7ea39a3962630d1ea2552bfd16a2d`, the C-PULSE-13 bridge, ten
  pinned deps), `ci.yml` (PR tier: suites x2 + smoke on both OS),
  `release.yml` (guard -> fleet -> `pulse-<ver>-<os>-<arch>.zip` +
  `.sha256` + `SHA256SUMS` -> GitHub Release on `pulse-v*`), `heavy.yml`
  (weekly 30m HTTP + kv soaks + RSS probe). Sequence executed: main
  pushed; rulesets verified live (owner-applied protect-main +
  protect-release-tags; CI contexts `DCO`/`ubuntu-latest`/`windows-latest`
  added to protect-main); dry run green on the Linux leg and it **caught
  a mis-transcribed Windows toolchain SHA** (fixed, re-run fully green);
  tag `pulse-v0.1.0` cut at `cc3e741`; **GitHub Release published** with
  `pulse-0.1.0-{linux,windows}-x64.zip` + per-asset `.sha256` + combined
  `SHA256SUMS`, build provenance attested. Ops mirrors to
  `dl.xiom-lang.org/pulse/...` (slug `pulse`, hourly at :17); the
  website then wires downloads + the live badge; demo deploy per runbook.
- **Wrap 7b (docs + conventions):** public docs phase A delivered in-repo
  (`docs/public/`: summary + Introduction/Install/Quick start/
  Configuration/HTTP API/Operations/Security/Releases; ASCII, front
  matter, relative links) and `CHANGELOG.md` added; the GitHub release
  body carries the 0.1.0 highlights. Conventions confirmed with the
  website lane (no macOS artifact; mirror layout; `/api/version` ==
  tag). Relay-back in `docs/WEBSITE-RELAY-PULSE.md` section 11.
- **Wrap 7c (ops env correction):** `PULSE_BIND=<addr>:<port>` is a silent
  trap (the port part is ignored; ops hit it on the VPS and fixed the
  unit to `PULSE_BIND=127.0.0.1` + `PULSE_PORT=3500`). Now covered by
  config validation: an `addr:port` / `[v6]:port` value warns at startup
  and in `--check-config` (bare IPv6 like `::1` is not flagged);
  test_app +4 checks; runbooks (public + internal) all state
  address-only. Verified both platforms (suites x2, smoke 78/78).
  Side-finding filed: the compiler silently accepted a stray `}` that
  left code outside the function body (COMPILER-FINDINGS wrap 7c).
- **Wrap 8 (macOS prep + bind finding):** macOS release support prepared
  (setup-xiom macOS branch, SHA-pinned x64/arm64 toolchains; release
  matrix macos-x64/macos-arm64 with suites x2 + smoke; portability: lsof
  `wait_listen` fallback, `timeout`/`gtimeout` watchdog fallback,
  `pulse_sha256` sha256sum/shasum helper, `release.sh` OS detection ->
  `pulse-<ver>-macos-<arch>.zip`; the first dry run surfaced upstream
  darwin blockers (runtime C `_SC_AVPHYS_PAGES`, arm64 x86 asm, a
  codegen intrinsic -- all filed), so the legs are gated behind
  `RELEASE_BUILD_MACOS` and the next release is not blocked).
  **C-PULSE-16 filed:** ops verified `PULSE_BIND` is not enforced (stdlib
  wildcard bind; local repro LISTEN `0.0.0.0`); demo firewalled;
  address-aware bind filed upstream; fix + LISTEN-address smoke check
  with the next release (owner: next cut = compiler fixes + macOS).
  Score: Security 46 -> 42, Testing 80 -> 88 -> ~55.4%.
- **Wrap 9 (v0.64.2 adoption):** both platforms on v0.64.2; the CI setup
  action's C-PULSE-13 bridge removed. **C-PULSE-09 CLOSED** -- probe
  fleet 11/11 on Windows AND Linux (`probe_adopt_smoke` steps 1..10, exit
  0 on both). **C-PULSE-13 CLOSED** (m232; verified installs + doctor).
  Suites x2 + smoke 78/78 on both platforms; m212 gate green; crash 6/6.
  **C-PULSE-14: Windows FIXED (flat over 206 req); Linux still grows
  ~87 KB/req steady (worse than v0.64.1's ~48)** -- retest on the next
  archive. Incident: a concurrent toolchain re-extract wiped the WSL
  packages store mid-sweep (reinstalled via `xiom pkg install`; green
  after) -- verify the store after any install. **NEXT: the session-store
  swap retry (bridge `220f814`) -- now unblocked on both platforms.**
- **Wrap 10 (framework roadmap):** `docs/FRAMEWORK-ROADMAP-PULSE.md`
  filed -- the production-grade contract (capability map with per-area
  upstream asks; milestones: 0.1.1 -> 0.2 foundations [driver seam, auth
  core, OpenAPI/problem+json/pagination, CLI subcommands, multipart,
  HTTP client] -> 0.3 data drivers [OrbitDB embedded, XVector vector,
  SQL via bindings, migrations] -> 0.4 integrations [payments, email,
  OIDC, webhooks, jobs] -> 1.0 production grade) and the **next
  candidate release plan for ALL OSs** (0.1.1 = v0.64.2 rebuild +
  session swap + fixes; `pulse-0.1.1-{linux,windows}-x64` ready, macOS
  x64/arm64 gated on the darwin blockers -- ship all four when green,
  else carry macOS to 0.1.2). Driver seam = versioned
  `xiom.pulse.driver` contract; every integration ships with a
  conformance probe.
- **Wrap 10b (orbitdb/xvector handshake):** two relay messages filed --
  `docs/ORBITDB-RELAY-PULSE.md` and `docs/XVECTOR-RELAY-PULSE.md` --
  asking each lane to write `docs/PULSE-INTEGRATION.md` in their repo
  (embedding API + snippets, build/link contract + platform matrix, pin,
  consumer-affecting findings incl. recovery/memory, conformance test
  proposal, cross-asks). PULSE reads it locally (read-only), then builds
  `probe_pkg_orbitdb` / `probe_pkg_xvector` and wires the 0.3 drivers;
  the vector use cases are events search + RAG endpoints, and the hybrid
  (OrbitDB rows + XVector embeddings) is the intended showcase.
- **Wrap 11 (0.1.1 cut):** session-store swap DONE -- `src/session.xi`
  wraps registry `xiom.session` 0.1.0 (ids/expiry/pruning from the
  package; user as the "user" entry; module renamed
  `xiom.pulse.sessions` for C-PULSE-12). Verified both platforms: build
  + `probe_adopt_smoke` + suites x2 + smoke 78/78. Version 0.1.1
  (rebuilt on v0.64.2: Windows memory flat + BIND validation warning +
  docs); CHANGELOG + public docs updated. Tag `pulse-v0.1.1` cuts
  linux+windows artifacts; **macOS stays gated** (darwin blockers).
- **Wrap 11b (package-lane relay):** durable-DB ask SERVED and verified
  signed on the registry -- `xiom.sqlite 0.2.0` (vendored amalgamation;
  waits on the `--c-source` build-hook story for registry consumers),
  `xiom.libpq 0.2.0` + `xiom.odbc 0.2.0` (dynamic-loader, SKIP when
  absent), and `xiom.http 0.1.4` (real-libcurl GET/POST -- no outbound
  binding needed; PULSE bumps in 0.2 and adds the SSRF guard). Filed in
  the package wishlist + roadmap; no 0.1.1 scope change.
- **Wrap 12 (0.1.2 ships):** the `pulse-v0.1.1` tag's CI gate failed on
  a stale version literal in `test_smoke.xi` (PULSE-side; nothing
  published); tags are immutable (protect-release-tags, no bypass), so
  the fixed cut is **0.1.2**: all expected-version literals updated
  (pulse.xi, server APP_VERSION, http Server header x2, test_smoke,
  test_http, smoke twins), verified with the pinned stdlib (CI parity),
  re-tagged. **`pulse-v0.1.2` published green:** guard + linux/windows
  packages + GitHub Release (assets + per-asset `.sha256` + `SHA256SUMS`,
  provenance attested; release body carries the 0.1.2 highlights).
  Relay-back + ops mirror note: `WEBSITE-RELAY-PULSE.md` section 13.
  Bindings-lane addendum filed: sqlite README carries the
  3-line consumer snippet + the required `--c-source` flag (ergonomic
  fix filed by that lane); xiom.http 0.1.4 covers outbound; they
  keep-fresh and target accelerators after the `xiom.vectors` extraction.
  Compiler finding updated: the `@llvm.memset.p0i8.i64` IR warning also
  reproduces on Linux CI (llvm-16), not only darwin.
- **Wrap 12b (0.2.0 direction):** owner decision -- the next release must
  matter: **macOS x64 + arm64 artifacts and real gap coverage** (not a
  maintenance cut). macOS critical path confirmed upstream and unfixed on
  the current lane sources: `xiom_runtime.c:4222` (`_SC_AVPHYS_PAGES`),
  `fp128_helpers.c` (x86 asm on arm64), compiler `@llvm.memset.p0i8.i64`
  emission (xiom-codegen `emitter.rs:859`, `expr.rs:3774`,
  `stmt.rs:713/1131`) -- fix sketches filed in the two wishlists. 0.2.0
  PULSE-side slate fixed in the roadmap: OpenAPI + additive problem+json
  + pagination + idempotency, CLI subcommands, `xiom.http` 0.1.4 + the
  SSRF-guarded client wrapper, multipart uploads, docs refresh. 0.1.2
  remains the shipped release.
- **Wrap 13 (0.2 starts: OpenAPI contract):** `GET /openapi.json` serves
  the OpenAPI 3.1 document (`resources/openapi.json`; the version token
  is substituted at serve time from the running build, so the contract
  and `/api/version` cannot drift); CLI gains its first subcommands --
  `pulse_app openapi` and `pulse_app routes` (17 routes, argv[0] note:
  args scan includes the exe path); config gains
  `PULSE_OPENAPI_PATH`; test_app +7 checks; smoke 78 -> **84/84** on
  BOTH platforms (Linux run with the pinned stdlib). Roadmap 0.2 items
  1/2 partially ticked; problem+json, pagination, idempotency, `/v1`,
  flag promotions next.
- **Wrap 13b (icon):** owner-provided `pulse.ico` (187,396 B, sha256
  `d424af89...`) adopted as the canonical icon at
  `resources/img/pulse-ico.ico` (all references, release staging and the
  `/favicon.ico` route stay stable); the **Windows exe now carries it**
  via **pinned rcedit v2.0.0** (`build.ps1` resolves PATH -> npm global
  -> `%LOCALAPPDATA%\xiom-tools`; the CI setup action fetches and
  sha256-verifies it for release builds). Verified: exe +187,904 B,
  `ExtractAssociatedIcon` loads 32x32; suites x2 + smoke 84/84 on both
  platforms. `xiom --icon` is still absent in v0.64.2 -- ask stands.
- **Wrap 13c (error status + CLI set):** every error path now mirrors the
  HTTP status additively in the envelope (`{"error":{"status":N,...}}`;
  the 405 Allow-header path uses the same shared helper); the CLI set is
  complete -- `version` and `check-config` subcommands join
  `openapi`/`routes`. test_app +3 checks; smoke 84 -> **89/89** on both
  platforms (Linux pinned-stdlib). Roadmap 0.2 item 2 done, item 1
  partially; pagination/idempotency/`/v1` next.
- **Wrap 14 (0.2 slate COMPLETE + first 0.3 interop):** pre-work full
  regression (fleet, suites x2, smoke 89/89 both platforms) against the
  wrap-13c binaries; then, in order: **pagination `Link`** on
  `GET /api/events` (seq-in-record cursor, legacy ordinal fallback,
  `next_cursor`, RFC 8288 `rel="next"`, `400 invalid_cursor`) `9301052`;
  **idempotency keys** (`Idempotency-Key`, durable `idem` marker, replay
  `deduplicated:true`) `a6a55b9`; **`/v1` alias** (`v1_path`; Link
  preserves the client's prefix) `602c9e6`; **outbound base** (`xiom.http`
  **0.1.4**, SSRF guard `xiom.pulse.outbound` + `probe_outbound_guard`
  42 checks in the fleet; libcurl transport seam isolated pending the
  `--c-source` hook) `bf6d9b0`; **multipart uploads**
  (`POST /api/uploads` + `/v1`, parser + caps + generated names; found +
  filed **C-PULSE-17** `io.list_dir` dangling names with a staged repro,
  and an `io.create_dir` requires-exists trap) `130a54b`; **interop
  probes** for ORBITDB (39/39) + XVector (30/30) with relay responses
  `6171304`. Every unit: suites x2 + smoke (final **119/119**, jsonl+kv,
  Linux pinned stdlib) + signed commit. Smoke PS twin now file-redirects
  server output and reads exit codes through cmd (pipe-deadlock +
  empty-ExitCode traps fixed); `check()` needles are wildcard-escaped.
- **Compiler relay received (2026-10-09, `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md`):**
  **v0.64.2 is release-ready, tag held for the owner.** Fixes in batch:
  C-PULSE-09 (m223..m227; re-run `probe_adopt_smoke` on the archive),
  C-PULSE-13 (m232 installer home unified -- test dropping the bridge!),
  C-PULSE-11, plus m228/m231/m234/m239. **Not** in this batch: the BIND
  primitive (C-PULSE-16) and the darwin blockers -- macOS stays gated.
  On publish: install both platforms, re-run the probe fleet + suites +
  smoke, retest C-PULSE-14 soaks (m235 still the candidate), and drop
  obsolete workarounds (C-PULSE-13 bridge if m232 holds), then cut the
  next release (0.1.1) per the standing routine.
- **Website lane relayed Phase-2 readiness (2026-10-09); PULSE reply
  filed** (`docs/WEBSITE-RELAY-PULSE.md` section 9): endpoint/binding
  facts, release naming (`pulse-v0.1.0`, `pulse-<ver>-<os>-<arch>.zip`),
  claim deltas (smoke 78/78; no memory/long-uptime claims on any OS),
  badge fetch approved (same-origin); **greenlight is owner-only**.
  `PULSE_CORS_ORIGIN` is now a comma-separated allowlist (verified both
  platforms) for the pulse-origin + hub-embed case.
- **Showcase/site (owner decisions 2026-10-08):** `pulse.xiom-lang.org`
  DNS is live (no staging subdomain needed); `orbitdb.`/`xvector.` pages
  later (DNS records exist). Phase 1: the **website lane** owns the
  marketing pages (`docs/WEBSITE-RELAY-PULSE.md` = brief + paste prompt);
  PULSE owns the product UI (`PULSE_LANDING_PATH`/`PULSE_ASSETS_DIR`) and
  claim review; ops owns infra. On greenlight: GH Actions release -> repo
  public + `main` rulesets -> dl publish -> ops deploys the demo. Cover
  image lands at `resources/img/` (owner drops it; PULSE wires the
  landing).
- **v0.64.1 known-issue cautions (from the notes):** `from_utf8` by-ref
  (pass by value), optional-into-vector-element assignment, nested-field
  mutation copies -- designs avoid all three.
- **Capabilities landed 2026-10-07/08:** 12 `.ps1`+`.sh` twins (all
  verified; PS exe defaults aligned to `out\pulse_app.exe` in wrap 3 --
  one stale default had hung a smoke run), registry wave
  (metrics/static/middleware adopted), stdlib
  `write_all` + `server_parse_request` adopted, TE smuggling guard,
  Expect/Date protocol fix, schema helper, audit rotation,
  `--version`/`--check-config`, showcase `/assets` + `PULSE_LANDING_PATH`,
  `PULSE_BIND`, Dockerfile, release + backup tooling; **v0.64.1 adoption
  complete on both platforms** (Linux sweep green, incl. the 20m kv soak);
  ops answered (staging parked; Linux toolchain pin v0.64.1 recorded; CI
  on greenlight).
- **Score:** ~55.4% production grade (`docs/PROGRESS.md`).
- **NEXT (in order):** 1) the **session-store swap retry** (bridge
  `220f814`) -- now unblocked on both platforms (C-PULSE-09 closed on
  v0.64.2: fleet 11/11, adopt_smoke green both); after it, cut 0.1.1
  (v0.64.2 pins already in the workflows; macOS stays gated). 2) watch
  the lanes: compiler (C-PULSE-16 address-aware bind; darwin
  runtime/codegen blockers; C-PULSE-12 alias ask), bindings (DB/KV
  binding, store seam). 3) non-blocked hardening: chunked RESPONSES
  (with keep-alive), a fresh 30-60m soak, or the longer kv soak for the
  flip gate; **C-PULSE-14 Linux memory retest on the next archive**
  (Windows flat on v0.64.2). 4) kv default flip only after the recorded
  prerequisites; otherwise keep kv opt-in. 5) release ops: pulse-v0.1.0
  live (demo + dl + docs verified); wire the owner's cover image
  (`resources/img/`) into the product landing when it lands.
- **Gotchas:** PS 5.1 strips embedded quotes in native args (use files,
  `--etag-save/--etag-compare`); when driving WSL from PS avoid inner
  quotes (write scripts to `/tmp` instead); `io.flush_stdout` is a no-op
  (durable step logs); no inline if-expressions; module last-segment
  collisions shadow imports (C-PULSE-12); no module-scope package
  constructors (Vec-holder pattern); **C-PULSE-13 is CLOSED (m232): no
  bridge -- `xiom pkg` resolves the compiler home; after any toolchain
  maintenance verify the store (`xiom doctor`; re-add with `xiom pkg
  install` -- a concurrent re-extract can wipe `packages/`)**;
  `wsl --shutdown` clears CLR/paging errors (system commit pressure, not
  the build); **version bumps: update EVERY expected-version literal --
  `src/pulse.xi`, `src/server.xi` APP_VERSION, `src/http.xi` Server
  header (x2), `tests/test_smoke.xi`, `tests/test_http.xi`,
  `scripts/http_smoke.{sh,ps1}` -- and run the suites with the pinned
  stdlib before tagging (CI parity; a stale literal cost the 0.1.1
  tag).** The openapi version assertion in `tests/test_app.xi` is part
  of that set.

### Session log 2026-10-07/08 (chronological history; superseded by the digest above)

- **Repo:** unchanged (`E:\xiom-projects\xiom-pulse`, private, no push
  without owner approval). Commits this session: `b58f7a8` (bash twins +
  Linux build path + m212 repro), `220f814` (registry wave adoptions +
  findings), plus this docs wrap.
- **Toolchain (owner policy: track latest):**
  - Windows: compiler v0.64.0 (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`),
    stdlib `E:\xiom-lang\stdlib`, `XIOM_RUNTIME_DIR` retired.
  - **Linux (NEW, verified):** WSL Ubuntu compiler v0.64.0 at the
    canonical Unix install (`~/.local/share/xiom`, `xiom` on PATH);
    stdlib from `XIOM_STDLIB=/mnt/e/xiom-lang/stdlib` when present, else
    the compiler's bundled tree; registry packages live in
    `~/xiom/packages` (legacy home) and install from the live registry
    (reachable from WSL, signatures verified).
- **Linux binary:** `out/pulse_app` (native x86-64 ELF, 609 KiB) built by
  `scripts/build.sh`; full runtime green.
- **WINDOWS SESSION MUST-DO:** the app now imports `xiom.metrics`,
  `xiom.static`, `xiom.http.middleware`; install them on Windows first:
  `xiom pkg install xiom.metrics@0.2.0 xiom.http.middleware@0.1.0
  xiom.static@0.1.0` (then suites x2 + smoke to re-verify Windows).
  Windows source-roots for the wave are already staged in `xiom.toml`.
- **Green evidence this session (Linux/WSL):** 12 `.sh` twins verified
  (run hello + crypto KAT, 3 binaries built, smoke 61/61, concurrent
  64/64, soak_tcp 25/25, crash 6/6, rate smoke, store_soak 20s, soak_http
  20s, proxy_e2e 11/11 via nginx 1.24 TLS); on the adopted binary: suites
  x2 all 0 failures, smoke 61/61, crash/rate/store-soak/proxy-E2E green;
  probes green: metrics, middleware, session (package surface), static,
  state-holder, adopt-smoke, session-inline.
- **Registry wave status:** `xiom.metrics` 0.2.0 -> `src/metrics.xi`
  (labeled counters + latency preset + exposition); `xiom.static` 0.1.0 ->
  favicon route (mime/ETag/Cache-Control/304/Range/traversal-guard);
  `xiom.http.middleware` 0.1.0 -> CSRF + CORS. `xiom.session` 0.1.0 store
  integration DEFERRED (C-PULSE-09 crash via wrapper modules; inline
  green; local store retained). `xiom.kv` 0.1.0 BLOCKED (C-PULSE-10
  kv_get corruption; JSONL fallback stays; `probe_pkg_kv` is the
  known-red gate).
- **New findings (details in relay docs):** C-PULSE-08 (m212 dotted-key
  latent, repro `docs/repro/dep-roots-name-form`), C-PULSE-09 (session
  store integration crash), C-PULSE-10 (kv_get corruption; classification
  open), C-PULSE-11 (`pub type X = PackageType` invisible cross-module ->
  "defaulting to i64" warning), C-PULSE-12 (module last-segment shadows an
  imported stdlib alias; renamed the app module).
- **Ops relay updated:** `docs/OPS-REQUEST.md` now carries the Linux
  evidence (VPS OS question resolved: Linux is fine) and the WSL-vs-Docker
  guidance for staging rehearsal.
- **2026-10-08 continuation:** **Windows re-verify GREEN** -- wave
  packages installed on Windows (`xiom pkg install xiom.metrics@0.2.0
  xiom.http.middleware@0.1.0 xiom.static@0.1.0`), then build + suites x2
  + smoke 61/61 + crash 6/6 + rate smoke all green on
  `out\pulse_app.exe`. **Stdlib wishlist delivered and adopted**:
  `TcpStream.write_all` replaces PULSE's send loop; the shared
  `xiom.net.server.server_parse_request` backs `http.parse_request`
  (PULSE caps preserved: 16 KiB guard, 100-header cap, trimmed values;
  invalid Content-Length now rejected); parity pinned by
  `tests/probes/probe_stdlib_server_parse.xi` (12 checks, both
  platforms). **Module renamed** `xiom.pulse.server` -> `xiom.pulse.app`
  (C-PULSE-12: a last-segment name shadows an imported stdlib alias --
  `server.` calls broke until the rename). Ops answered the relay
  (docs/OPS-REQUEST.md section D): staging is parked by owner decision;
  Linux toolchain source pinned at dl (`xiom-v0.64.0-linux-x64.tar.gz`,
  SHA256SUMS, immutable pins); CI mechanics specified for greenlight.
- **Env note (2026-10-08):** the Windows box hit pagefile/commit
  exhaustion mid-session (PowerShell/WSL errors: "paging file is too
  small", "Starting the CLR failed", UTF-16 mangled interop output); a
  `wsl --shutdown` cleared it before the RAM bump + restart. If WSL
  commands return CLR/paging errors, suspect system commit pressure, not
  the build. PULSE's own footprint is small (single clang compiles, tiny
  test servers); Docker Desktop + WSL VMs dominate.
- **2026-10-08 (later):** audit rotation landed (`src/audit.xi`,
  `PULSE_AUDIT_MAX_BYTES` default 5 MB, probe 6/6 + app-level E2E on
  Linux); CLI `--version`/`--help` and `/api/version` commit/build fields
  (runtime `PULSE_BUILD_COMMIT`/`PULSE_BUILD_DATE` until a compiler
  define flag exists -- filed). Both platforms re-verified green.
  Blocked-work survey: `xiom.os.signal` has no handler-install API ->
  SIGTERM graceful stop stays blocked (stdlib wishlist filed); keep-alive
  stays gated on recv timeouts (`socket_set_timeout` stub) because one
  idle keep-alive client would stall the single-threaded loop. Next
  unblocked M4 item: schema helper.
- **2026-10-08 (schema close-out):** `src/schema.xi` landed (typed
  rule-list validator: required/optional, length + numeric bounds,
  first-failure code/field/message) and routes 4/7/8 use it with
  field-specific 400s (probe_schema 14/14); the flaky JWT tamper check is
  fixed (append a char -- replacing the last base64url char can decode to
  identical bytes; one Windows run flaked). Unblocked M4/M5 work is now
  exhausted: keep-alive / recv timeouts / signals wait on stdlib
  capabilities (filed), CI / packaging / true build stamping wait on the
  public greenlight (ops mechanics ready).
- **2026-10-08 (packaging round):** TE/chunked smuggling guard (any
  `Transfer-Encoding` -> 501; CL.TE desync closed; test_app 105 checks +
  smoke 62/62), status table completed (206/304/501... had rendered
  "Unknown"), `scripts/release.{ps1,sh}` (dist artifacts per the ops
  naming, zip + sha256 verified on both platforms) and
  `scripts/backup.{ps1,sh}` (timestamped store+audit snapshots with
  sha256 manifest + prune; tested; restore runbook in DEPLOYMENT §9).
  Compiler check: dl still v0.64.0; **m215/m216/m217 (C-PULSE-08/10/11
  fixes) are in the lane source, not in an archive** -- v0.64.1 is the
  next adoption gate; C-PULSE-09 was triaged not-reproducible from
  committed sources (PULSE will retry the session-store swap on the next
  archive using the arrangement in git history 220f814).
- **2026-10-08 (pre-flight round):** `--check-config` CLI (effective
  config dump; exits 1 only on an unreadable configured file; never
  prints the secret -- flags dev-default vs env) + smoke pre-flight
  checks (`--version`/`--check-config` before start; 66 checks). Suites
  x2 + smoke green on both platforms. **Lane map:** a dedicated
  **bindings lane** (`E:\xiom-packages\bindings`, worktree of the
  packages lane) now builds binding packages; PULSE files binding
  requests via the packages lane and keeps the seam map in PROGRESS
  ("Integration seams for future bindings").
- **2026-10-08 (showcase round):** general `/assets/<path>` serving
  (`PULSE_ASSETS_DIR`, same ETag/304/Range/traversal machinery) +
  `PULSE_LANDING_PATH` per-site landing content + `PULSE_BIND` (loopback
  default; containers set 0.0.0.0) + `deploy/Dockerfile` (build verified,
  container E2E: health/version/assets). Smoke 71/71 on both platforms.
  These are the PULSE-side prerequisites for the planned
  `pulse.xiom-lang.org` / `orbit.` / `xvector.` showcase sites (one
  binary + per-site env; honest beta framing) and for the offline
  benchmark harness after release. Owner plan discussed this wrap; ops
  side unchanged (staging parked; one nginx site per subdomain when
  greenlit).
- **2026-10-08 (protocol round):** `Expect: 100-continue` (interim before
  the body; raw-socket proof) and the `Date` response header landed;
  test_http +4, smoke 73/73 both platforms. Owner plan agreed: adopt the
  next compiler/stdlib/package release, sweep bugs/blockers against it
  (C-PULSE-08/09/10/11 gates ready), then coordinate ops for the three
  showcase sites; non-blocked hardening continues until then.
- **2026-10-08 (v0.64.1 sweep):** the installed Windows toolchain was
  updated in place to **v0.64.1**; the package store was wiped by that
  maintenance and all ten deps were reinstalled. **C-PULSE-08 CLOSED**
  (m212 gate: dash + dot both exit 0, no source-roots), **C-PULSE-10
  CLOSED** (kv probe GREEN; kv_get returns the stored text), C-PULSE-11
  alias fix confirmed by the release notes. Full regression on v0.64.1:
  suites x2 + smoke 73/73 + crash 6/6 + rate, all green. **NEW finding:**
  v0.64.1's extern-unsafe enforcement breaks the published `xiom.http`
  0.1.1 (67 T001s) -- PULSE pruned the already-unused package
  (`probe_pkg_http` is the known-red republish gate; the packages lane
  owns the fix). **Session-store swap retried on v0.64.1:** now compiles,
  but still crashes (0xC0000005) at the first cross-module access to the
  module-level `Vec[SessionStore]` (C-PULSE-09 stays OPEN; durable step
  evidence in `probe_adopt_smoke` via `pulse-adopt-steps.txt`; local
  store stands). **kv backend adopted (opt-in):** `PULSE_STORE_BACKEND=kv`
  (+ `PULSE_KV_DIR`/`PULSE_KV_PREFIX`) routes the event store through
  `xiom.kv` behind the same API; verified on v0.64.1 (smoke 73/73 through
  kv, store-soak 20s kv green, default jsonl smoke 73/73 regression).
  Next: Linux-side sweep when dl publishes v0.64.1, then ops on
  greenlight.
- **Next action:** session-store swap retry with the alias design (m216
  fix; keep the local store until suites pass), kv backend adoption
  behind the same store API, Linux-side probe sweep + suites when dl
  publishes v0.64.1, adopt socket timeouts / signals / define flag when
  the stdlib exposes them, watch the bindings lane for the durable DB/KV
  binding (store seam, PROGRESS 6b); when the owner greenlights: CI file
  + dl release flow + the three showcase sites (ops mechanics in
  docs/OPS-REQUEST.md).

## 0b. STATE HISTORY (2026-10-05) -- superseded

- **Repo:** `E:\xiom-projects\xiom-pulse`; identity `Lefteris Notas
  <lefterisnotas@gmail.com>`; repo stays **PRIVATE**; `origin` exists
  (github.com/xiom-projects/xiom-pulse) but is **not pushed without owner
  approval**.
- **VERSION POLICY (owner decision 2026-10-05): track the LATEST compiler /
  stdlib / packages.** PULSE is the ecosystem's real-world hardening
  harness; no fixed pin. Record exact versions + lane hashes every wrap; on
  a latest-version regression, file the finding, note the last known-good
  as a ROLLBACK OPTION, and keep moving.
  - `XIOM_COMPILER = %LOCALAPPDATA%\xiom.new\bin\xiom.exe` (**v0.64.0**)
  - `XIOM_STDLIB   = E:\xiom-lang\stdlib` (stdlib-lane checkout = latest)
  - **`XIOM_RUNTIME_DIR` RETIRED** -- v0.64.0 R65 links the installed
    `lib\runtime` + `lib\xiom` without overrides. PULSE verified env-free
    (both vars unset): hello + `probe_crypto` NIST KAT green (2026-10-05).
  - `scripts\dev-env.ps1` sets the two and removes any stale
    `XIOM_RUNTIME_DIR`; PATH shadow warning: a v0.62.3 staging dir shadows
    `xiom.new` in PATH.
- **Lane hashes / latest cycle (recorded 2026-10-05):**
  - compiler v0.64.0 (release archive; `xiom.new-cand-v0.64.0` also present)
  - stdlib lane checkout `357474c` (per stdlib lane message)
  - packages: `xiom.http` 0.1.1, `xiom.cookie` 0.1.1, `xiom.jwt` 0.2.0,
    `xiom.rate` 0.2.0, `xiom.router` 0.1.0 (incubating, publish pending
    ops scope confirmation)
- **Last green slice:** **through-proxy TLS E2E GREEN 11/11** on
  `out\pulse_app_v9.exe`: nginx 1.28.3 terminates TLS (self-signed cert
  via Git-OpenSSL) on 127.0.0.1:8443 -> PULSE :18091; verified health,
  HSTS, `Server: nginx` with no upstream token leak, POST bodies, metrics,
  404+rid. Script `scripts\proxy_e2e.ps1`; production example
  `deploy\nginx\pulse.conf.example`. Before it: wave 6 (config file,
  events `?kind=`, 10m store soak 841/841/841 GREEN) and wave 5
  (compaction, `?limit`, rid, gauges).
- **Registry wave ready to wire (owner relay 2026-10-07):** all published
  and signature-verified: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.metrics` 0.2.0, `xiom.router` 0.1.0,
  `xiom.http.middleware` 0.1.0, `xiom.session` 0.1.0, `xiom.static`
  0.1.0, `xiom.kv` 0.1.0.
- **Pipeline-hang lesson (cost the owner hours):** launching a detached
  child (nginx) with inherited stdout/stderr pipes makes the caller wait
  on the pipe forever, past any process timeout. Always `Start-Process`
  with file redirection, poll readiness with a bounded socket connect,
  and kill by PID tree.
- **Next action (owner-ordered):** FIRST port every script to a `.sh`
  twin (dev-env, run, build, smoke, soak, concurrent, crash, rate,
  store, proxy-e2e) so Linux developers can use them; THEN adopt the
  registry wave (`xiom.metrics` 0.2.0 labels/latency preset,
  `xiom.http.middleware`, `xiom.session`, `xiom.static` for the favicon/
  landing, `xiom.kv` as the durable store replacement); continue M4/M5
  hardening per `docs/PROGRESS.md`.
- **Findings status on v0.64.0:** C-PULSE-01 **RESOLVED** (read matrix
  exit 0; `probe_read_no_io` + `probe_net_roundtrip` now green);
  C-PULSE-04 **still open** (exit 5); C-PULSE-05 **worse** (W005 const
  `.to_str()` now aborts 0x80000003 instead of rendering empty; PULSE
  workaround `convert.int_to_string` still required); C-PULSE-02 **still
  open** (13 T001 without source-roots); runtime-link/crypto-link
  **RESOLVED env-free**; `xiom.http` parser defect fixed in 0.1.1.
- **Next action:** Step 4 wrap: run the through-proxy E2E checklist
  (`docs/DEPLOYMENT.md`) once a proxy is installed (Caddy/nginx); meanwhile
  continue M4 (CORS/CSRF helpers, HEAD handling, schema validation,
  keep-alive) and adopt `xiom.http.middleware`/`xiom.session` when the
  packages lane publishes them.

### Step 3 progress (storage)

`xiom.sql` is not in the registry; `xiom.bolt` v0.1.2 is pure-XIOM but a
read-only bbolt page parser; no writable embedded store is published.
Step 3 therefore ships a **zero-dependency append-only JSONL event store**
(proven `io.append_line`/`read_file_lines` path) and proposes **`xiom.kv`**
to the packages lane (`docs/PACKAGE-WISHLIST-PULSE.md`).

| Item | Result | Evidence |
|---|---|---|
| Schema record + loader (invalid/torn lines skipped) | DONE | `src/store.xi`; suite store tests |
| Torn-line healing append (`\n` repair before write) | DONE | suite `store torn tolerated`; crash test |
| Events routes (`POST/GET /api/events`, `GET /api/events/count`) | DONE | suite dispatch tests; smoke extension pending |
| Crash/reopen end-to-end | DONE 6/6 | `scripts\crash_test.ps1` (20 events -> kill -> torn -> reopen 20 -> heal 21) |
| Storage soak (200 events, crash, reopen) | DONE 6/6 | `scripts\crash_test.ps1 -Events 200` (store 12,731 bytes -> kill -> torn -> reopen count=200 -> heal 201) |
| W005 const-`.to_str()` workaround | DONE | `convert.int_to_string` in `schema_line`; C-PULSE-05 filed |

### Step 2 progress

| Item | Result | Evidence |
|---|---|---|
| Router (exact + `/api/items/:id`, 405 + Allow) | DONE | `src/router.xi`; `tests/test_app.xi` |
| Error envelope `{"error":{"code","message"}}` | DONE | `src/envelope.xi`; smoke 400/401/404/405 |
| Config (env-overridable) | DONE | `src/config.xi`; suite port override/fallback |
| Structured access log (JSON, rid) | DONE | `src/server.xi access_log`; smoke server log |
| Metrics + `/metrics` Prometheus text | DONE | `src/metrics.xi`; suite + smoke |
| Audit trail (mutating requests) | DONE | `src/server.xi audit_event`; `pulse-audit.log` (gitignored) |
| Cookie sessions (login/me/logout) | DONE | `src/session.xi` (registry `xiom.cookie` for parsing); smoke cookie-jar flow |
| JWT HS256 (sign/verify/exp/tamper) | DONE | `src/jwt_hs.xi`; suite + smoke |
| 64 concurrent on Step 2 binary | DONE (green) | `scripts\concurrent.ps1 -Port 18083 -ServerExe out\pulse_app.exe` |
| Storage | pending (Step 3) | -- |

**Test-infra learning:** chatty servers must never be started with undrained
PowerShell pipes (4 KiB buffer) — `concurrent.ps1` and `soak_http.ps1` both
redirect the server to a file via `cmd /c` now. The first Step 2 concurrent
run deadlocked on exactly this (64 JSON log lines > 4 KiB), which is why
the driver was fixed before the green run.

### Step 1 progress

| Item | Result | Evidence |
|---|---|---|
| HTTP parser + response builder | DONE (31/31 x2) | `src/http.xi`; `tests/test_http.xi` |
| Router: GET /health, GET /api/version, POST /api/echo, 404/405 | DONE | `src/server.xi` `handle_route`; suite + smoke |
| JSON responses via stdlib `xiom.serialize.json` | DONE | smoke: `{"status":"ok"}`, `{"echo":{"a":1}}` |
| curl verification | DONE 13/13 | `scripts/http_smoke.ps1` (note: bodies via `--data-binary @file`; PS 5.1 strips embedded quotes in native args) |
| 64 concurrent on :8080 | DONE (green) | `scripts\concurrent.ps1 -Clients 64 -Port 8080 -Path /health -ServerExe out\pulse_server.exe` -> connected=64/64, ok=64, served=64, server_exit=0, handles 77->78 |
| 1h soak (memory/fd stability) | DONE with caveat; 1h re-run in progress | 30m dual soak (2026-10-05 15:49-16:19Z): PS driver **3538/3538 ok, server_exit=0**; WSL client **3105 ok / 1 fail** (client transient, no server-side evidence); server log **7248/7248 HTTP 200**, 0 error lines, clean `shutdown served=7248`, ws 8,491,008 -> 8,544,256 (+53 KB), handles 113 -> 113. The +605 extra served requests were the orphaned old driver before `taskkill /T`. True **1h re-run on `out\pulse_app.exe`** started 16:2xZ (PS + WSL, wakeup scheduled) |
| Registry package consumption | DONE (xiom.http with workaround; cookie/jwt green) | `xiom pkg install xiom.http@0.1.0` (sha256 f8b59d9e...), `xiom.cookie@0.1.1` (sha256 6259e3b3...), `xiom.jwt@0.1.1` (sha256 408643ce...), all signature-checked; `probe_pkg_step2.xi` 8/8 x2 (cookie jar parse/get/serialize-set; jwt shape/alg/sub/exp); `probe_pkg_http.xi` exposes the xiom.http parser defect |
| WSL cross-boundary client check | DONE (green) | Ubuntu WSL: `curl http://172.26.112.1:18080/health` -> `{"status":"ok"}`; note: WSL `localhost:8080` hits the Docker Desktop container on this machine, not PULSE |

**Environment note (port contention):** on this machine `0.0.0.0:8080` is held by
`com.docker.backend` (Docker Desktop publishes the "XIOM Benchmark Chaos"
app; also reachable as WSL `localhost:8080`). The v0.63.1 Windows
`xiom_socket_bind` (no `SO_REUSEADDR`) still bound `127.0.0.1:8080`
alongside it, but for clean evidence PULSE gained a `PULSE_PORT` env
override (`src/server.xi` `server_port()`, default 8080) and the soak runs
on 18080.

**Soak verdict (30m dual, 2026-10-05 15:49-16:19Z):** PS 3538/3538 ok
(fail=0, clean exit); WSL 3105 ok / 1 transient fail (no server-side
evidence -- the server served 7248/7248 with zero error lines and shut
down cleanly); ws +53 KB, handles flat 113/113. The earlier 36-min driver
stall was a PowerShell-harness issue (orphaned child survived a
wrapper-only kill; drivers now use `taskkill /T` semantics, socket
timeouts, heartbeats and file redirects). WSL failure lines now log the
curl exit code/HTTP code for future transients.

### Step 0 progress

| Step | Result | Evidence |
|---|---|---|
| 0a scaffold + pin + lane hashes | DONE | this file; `.gitignore`; `scripts\dev-env.ps1` |
| 0b version/doctor/hello x2 | DONE (green x2) | `tests\probes\probe_hello.xi`; `tests\test_smoke.xi` 4/4 |
| 0c raw TCP bind/listen/accept/read/write x2 + 60s soak | DONE (green; workaround) | `tests\probes\probe_tcp_server2.xi` + `probe_tcp_client2.xi`; `scripts\soak_tcp.ps1 -Seconds 60` -> served=147, fail=0, handles 82->82, ws +69 KB; 10s re-run GREEN served=27 |
| 0d crypto `sha256_hex` with/without `XIOM_RUNTIME_DIR` | DONE -- **WITH = KAT PASS exit 0**; WITHOUT = `lld-link: undefined symbol: xiom_sha256_hash` | `tests\probes\probe_crypto.xi` both ways |
| 0e N concurrent connections | DONE (green) | `scripts\concurrent.ps1 -Clients 64` -> connected=64/64, ok=64 fail=0, served=64, server_exit=0, handles 84->85, ws +78 KB |

**STEP 0d RESULT (relay to packages/stdlib lanes):** `xiom.crypto.sha256_hex`
is fully usable on v0.63.1 **when `XIOM_RUNTIME_DIR` is set** -- it links
`runtime\sha256_sw.c` and produces the NIST KAT. Without the override the
long-open `crypto-link` finding reproduces exactly (`undefined symbol:
xiom_sha256_hash`, referenced by `__unsafe_block_3`). crypto-link therefore
looks like the SAME class as runtime-link (install-layout runtime discovery,
packages `5b7547b0`); the packages lane can re-test `docs/repro/crypto-link`
under the override and likely fold/flip that row. This unblocks stdlib
SHA-256/HMAC for PULSE JWT (Step 2).

## 1. Upstream findings (relay rows -- batched at every step wrap)

**Relay documents (owner hands these to the lanes; keep updated every wrap):**
- `docs/PROGRESS.md` -> owner tracker (weighted production-grade %; update
  with evidence at every wrap).
- `docs/COMPILER-FINDINGS-PULSE.md` -> compiler lane (C-PULSE-01/02/04/05/06 +
  test-gap notes + v0.64.0 results + bump procedure).
- `docs/STDLIB-WISHLIST-PULSE.md` -> stdlib lane (str_bytes RESOLVED;
  socket options/timeouts, server-side request parser, write_all,
  flush_stdout confirmed empty, harness -- all queued).
- `docs/PACKAGE-WISHLIST-PULSE.md` -> packages lane (xiom.http 0.1.1
  verified; jwt 0.2.0 adopted; rate 0.2.0 recorded; router publish gated on
  the ops scope confirmation in the doc).

### Relay cycle 2026-10-05 (incoming + actions taken)

- **stdlib** (`357474c`): `str_bytes` exists at `xiom.string.slice.str_bytes`
  (`slice.xi:135`) -- PULSE adopted it (`src/http.xi` delegates; no more
  hand-rolled loops). `flush_stdout` confirmed an empty body at
  `io.xi:903` (explains lagging redirected logs). Socket options,
  deadline recv, `write_all`, `server_parse_request`, `hmac_sha256_hex`,
  loopback fixture are queued; items 1/4 are runtime-backed and need
  `XIOM_RUNTIME_DIR` until archives bundle the newer runtime. C-PULSE-01
  forwarded to the compiler lane.
- **packages**: `xiom.http` **0.1.1** published (types import + deref cursor
  + parser KATs 40/40; server.xi documented stub). PULSE re-verified from
  the consumer side: `probe_pkg_http.xi` now compiles importing only
  `xiom.http.parser` and parses, exit 0. `xiom.jwt` **0.2.0 HS256 is
  live and adopted by PULSE**: `jwt_sign_hs256` /
  `jwt_signature_valid_hs256` / `jwt_verify_hs256` (verified payload
  returned), local `src/jwt_hs.xi` deleted; `tests/test_app.xi` 6 jwt
  checks + `probe_pkg_step2.xi` 11/11 green. `xiom.rate` 0.2.0 live
  (recorded). `xiom.router` 0.1.0 recorded/incubating -- publish awaits
  the ops scope confirmation (PULSE confirmed the four names in the
  package wishlist doc).
- **compiler**: **v0.64.0 released and ADOPTED** (owner decision: track
  latest). PULSE migration green: runtime-link + crypto-link resolved
  env-free, C-PULSE-01 resolved, C-PULSE-04/05 and C-PULSE-02 still open
  (details + bump procedure in `docs/COMPILER-FINDINGS-PULSE.md`).
  Fleet on v0.64.0: suites x2, smoke 38/38, 64/64 concurrent, registry +
  read probes green.
- **packages (router)**: `xiom.router` 0.1.0 published and **adopted by
  PULSE** within the hour: `probe_pkg_router.xi` 8/8 (match/param/404/405/
  Allow/validation); `src/router.xi` is now a thin app wrapper over the
  package (route ids + query parsing/decoding); suites x2 + smoke 44/44 on
  `out\pulse_app_v5.exe`. Clean first consumer pass, no hotfix.
- **packages (rate)**: `xiom.rate` 0.2.0 adopted for the global limiter
  (token bucket wrapper, caller-owned; tests + `rate_smoke` green). Package
  itself clean; the crash we hit was a compiler gap, not the package.
- **compiler (icon)**: reply recorded -- immediate workaround is post-build
  `rcedit`, planned `xiom --icon` for v0.64.1+ (llvm-rc, cached by icon
  hash). PULSE wired the rcedit hook into `scripts\build.ps1` (activates
  when rcedit is on PATH) and will delete it when `--icon` lands.
- **compiler (new finding)**: C-PULSE-07 -- module-scope initialization from
  a package constructor is accepted but emits an undefined call
  (`@rate_keyed_new`) or crashes at module init; repro bundle
  `docs/repro/module-scope-package-init/`; PULSE policy: package aggregates
  stay caller-owned.
- **website message**: routed for the website lane, not PULSE scope.

Reference docs read before reporting (do NOT re-run known bisections; add
delta evidence only): packages `docs/COMPILER-FINDINGS.md`,
`docs/STDLIB-WISHLIST.md`, `docs/repro/README.md`, packages `SESSION.md`.

### Compiler defects (-> minimal repro bundle + row)

| Date | Finding | Evidence | Workaround | Impact |
|---|---|---|---|---|
| 2026-10-05 | **C-PULSE-01: a method named `read` called with ONE argument is hijacked by the raw-pointer codegen builtin (`xiom-codegen/src/call.rs:3177`, guard checks only `fn_name=="read" && args.len()>=1`, not the receiver type). The real method is never emitted; `Result.is_ok` folds to false / Int result to 0; NO diagnostic. Renaming fixes it; `use xiom.io;` is irrelevant (A/B).** | `docs/repro/read-method-builtin-shadow/probe.xi`: matrix exit 5 (`SockA.read`+Result and `SockC.read`+Int broken; `take2`/`take3`/`read5` green); `--emit-ir` shows `@SockA.read`/`@SockC.read` defined but never called. App context: `xiom.net.TcpStream.read` (`xiom/net/net.xi:105`) dead -> PULSE server/client cannot read requests; `os.Pipe.read` same shape. IR of the networking repro folds `.is_ok` to `icmp ne i64 0, 0`. | read via `xiom.net.socket.socket_recv(fd, max)` (raw fd, verified green); never name one-arg methods `read`; `write` unaffected (builtin requires >=2 args) | blocks the whole stdlib networking read path + any `read(oneArg)` method; silent no-op with no diagnostic |
| 2026-10-05 | **C-PULSE-04: a `&mut Int` parameter used BARE in value position (arithmetic RHS or `return`) yields the pointer ADDRESS, not the pointee. Explicit `*p` deref is correct. No diagnostic.** (The v0.62.2/v0.62.3 write-drop half is fixed; this is the read side.) | `docs/repro/mut-int-bare-read/probe.xi` (exit 5 = bits 0\|2): `bare_add` prints `a=1056790543816 r=1056790543808` (stack addresses); `deref_add` `b=11 r=11`; `bare_read` returns `1056790543744` vs 10; `deref_read` 10. App context: `xiom.http` v0.1.0 parser keeps its cursor in `&mut Int` and returns `Unexpected end of request line pos=372324169712` on valid input. | always `*p = *p + k; return *p;` for `&mut Int` (existing `xiom.gbnf` pattern); PULSE's own parser uses value locals | silent wrong values; breaks any cursor-style parser still on the bare form; was the root cause behind the registry-package parser failure |
| 2026-10-05 | **C-PULSE-02 (toolchain gap): installed registry packages are invisible to the compiler module catalog. `[dependencies]`/`dependencies:` are parsed by `xiom-graph` but never mapped to source roots; the driver only adds the project's own roots + stdlib (`xiom-graph/src/manifest.rs:resolve_source_roots`, `xiom/src/lib.rs` catalog setup).** | `xiom pkg install xiom.http` succeeds (sha256 + signature); `tests/probes/probe_pkg_http.xi` with declared deps -> 13x `T001 undefined variable 'http_*'`; adding `xiom.toml` `source-roots` pointing at `$XIOM_HOME\packages\xiom-http-0.1.0\xiom-http\src` makes the catalog load it. | `xiom.toml` `[project].source-roots` with each installed package's `src/` (and package root when a barrel module lives there) | registry consumption requires manual path wiring; `xiom pkg install` alone is not enough to `use` a package |

### Stdlib gaps (-> STDLIB-WISHLIST row)

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| Socket option exposure: `socket_set_timeout` (SO_RCVTIMEO) and `socket_reuse_addr` (SO_REUSEADDR) are documented-Err stubs in `xiom/net/socket.xi:287,360`; the Windows `xiom_socket_bind` (`xiom_runtime.c:4737`) does not set SO_REUSEADDR (the POSIX branch at :4816 does). | PULSE Step 0c/1: server restart after an unclean stop can hit `WSAEADDRINUSE` (TIME_WAIT); no slow-client guard is possible -- a half-open request blocks the single-threaded accept loop forever. | restart with retry/backoff + alternate ports in tests; document the slow-client risk; keep clients well-behaved. | production hardening (timeouts, graceful restarts) |
| `xiom.string.bytes`: `str_bytes(s) -> Vec[UInt8]` (Str -> bytes without an FFI/data-field reach-around). PULSE hand-rolled `str_to_bytes` in 4 probes in one session. | `tests/probes/probe_tcp_server.xi`, `probe_tcp_client.xi`, `probe_socket_low.xi`, `probe_net_roundtrip.xi` (same 8-line loop each). | local `str_to_bytes` helper per file | every wire-response writer re-implements it; add PULSE as requester to the existing wishlist row |
| Durable `flush_stdout` on abnormal exit (existing row) -- add PULSE as requester. | redirected server probes produced no output before exit; `background_process` logs were empty until the process ended. | run servers in the foreground for evidence, or flush explicitly | observability of long-running services |
| A deadline-capable `xiom.net` read path: `TcpStream.read` is dead (C-PULSE-01) and `socket_recv` is untimed/blocking; a web backend needs a recv deadline to shed slow clients. | PULSE Step 0c/1 server loops; `xiom/net/net.xi:105`; `xiom/net/socket.xi:287`. | raw `socket_recv` + careful request framing; document the limitation. | slow-client resilience; DoS resistance |

### Package wishlist (-> package row)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence from PULSE |
|---|---|---|---|---|
| `xiom.http` v0.1.1 (bump, not new name) | fix consumer-visible parser + tests | n/a (existing package) | xiom.std | see Package defects below |

### Package defects (-> packages lane rows)

| Date | Package | Finding | Evidence | Impact |
|---|---|---|---|---|
| 2026-10-05 | `xiom.http` v0.1.0 | **Shipped parser is consumer-broken on v0.63.1:** (a) `src/parser.xi` uses `HttpRequest`/`HttpMethod`/`HttpHeaders`/`method_from_str` from `xiom.http.types` WITHOUT `use xiom.http.types;` -> 19 T001s for a consumer importing only `xiom.http.parser`; (b) the request cursor is a `&mut Int` used bare (`pos_ref = pos_ref + len + 1`), which on v0.63.1 reads the address (C-PULSE-04) -> valid input returns `Unexpected end of request line pos=372324169712`; (c) `tests/test_conformance.xi` never calls `http_parse_request`/`http_parse_response`, so (a)/(b) ship green. | PULSE consumer probe `tests/probes/probe_pkg_http.xi` (installed via `xiom pkg install xiom.http`; sha256 verified): with `use xiom.http.types;` added, compile succeeds and `http_parse_request("POST /api/echo ... Content-Length: 7 ...")` returns that Err with a stack-address position. | any registry consumer of `xiom.http`'s parser is blocked until re-shipped; add parser KATs to the suite |

## 2. Known compiler-gated items (design around; do NOT rediscover)

- graphql 9/10 enum-payload `Str` in-situ: open, distinct root cause; GraphQL
  stays behind an interface, not on the critical path. C001 `4bf8cf1e` IS in
  v0.63.1.
- grpc `Vec[(Str,Str)]` read-after-mutation crash/hang: m192-class candidate;
  re-test only on the next compiler archive. No gRPC in the design.
- crypto-link `xiom_sha256_hash`: **RESOLVED on v0.64.0 env-free** (PULSE
  KAT green with `XIOM_STDLIB` and `XIOM_RUNTIME_DIR` both unset). The old
  `XIOM_RUNTIME_DIR` override is retired; stdlib SHA-256/HMAC and registry
  `xiom.jwt` 0.2.0 are fully usable.
- FFI-class packages (kafka, zstd, lzfse) are stubs; not planned.
- Pin discipline: initialize every local (`var x: T = <default>;`); `Vec[T]`
  brackets only (byte-level grep after writes); parenthesize bitwise+additive;
  unique fn names, `pub` for cross-module; probes staged in-repo (never
  `%TEMP%\kilo`); watchdog + exit-code gate on every run; suites x2.

## 3. Paste prompt for the next PULSE session (2026-10-10 wrap 14)

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (the official
XIOM web backend). Read SESSION.md first -- the CURRENT STATE digest at
the top is authoritative; then docs\PROGRESS.md and the relay docs it
lists. The repo is PUBLIC now; org rulesets gate PRs on DCO +
ubuntu-latest + windows-latest (admin pushes bypass; never move a
published tag -- on a failed tag run, fix and cut the next patch
version). Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages (or its bindings worktree
E:\xiom-packages\bindings). Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s; when a message
contains quotes or slash-paths use git commit -F <file> (PS mangles
native-arg quoting). Toolchain: v0.64.2 on BOTH Windows and Linux/WSL
(pins in docs\OPS-REQUEST.md D.1 and every workflow); Linux
verification uses the PINNED stdlib (4dd8844) -- export
XIOM_STDLIB=$HOME/.cache/xiom-pin/stdlib-4dd8844 (the WSL tmp cleaner
wipes /tmp on distro restarts, so the pin cache lives in ~/.cache).

TASK ORDER:
1. FIRST: quick regression on the existing binaries -- probe fleet
   (12/12, incl. probe_outbound_guard) + suites x2 + smoke 119/119
   (jsonl and kv) on Linux and Windows; Linux with the pinned stdlib;
   compare against probe-logs\regress-20261010\ before touching anything.
2. RELEASE 0.2.0 ("the release that matters") when macOS is green (or on
   the owner's call): the 0.2 PULSE-side slate is COMPLETE (pagination
   Link + seq cursor, idempotency keys, /v1 alias, outbound base +
   SSRF guard, multipart uploads). Version bump checklist from SESSION
   gotchas: EVERY expected-version literal (tests/test_app.xi openapi,
   the smoke twins, package.xi/SESSION, docs), CHANGELOG entry, tag
   pulse-v0.2.0, CI publishes, ops mirrors at :17, website lights the
   macOS button.
3. INTEROP / 0.3: next tranche of tests/interop/ -- orbitdb hard-kill
   harness (integration doc §5.2/3: writer/verify modes + kill), xvector
   filter combos (§5.2) + hybrid join (§5.9); then the 0.3 drivers
   (open/exec/query/tx seam over ORBITDB; upsert/search/delete over
   XVector). Probes: tests/interop/<lane>/, nested xiom.toml with
   source-roots relative to the sibling checkouts; local-only until the
   packages publish.
4. WATCH the lanes: compiler (darwin trio -> flip RELEASE_BUILD_MACOS +
   dry-run all four legs; C-PULSE-16 address-aware bind -> enforce
   loopback + LISTEN-address smoke check; C-PULSE-14 Linux memory retest
   on the next archive; C-PULSE-12 alias ask; C-PULSE-17 list_dir fix ->
   re-enable list_dir use if it lands), packages/bindings (SQL class
   when the sqlite --c-source story lands; the http --c-source hook for
   the real outbound client), demo redeploys.
5. OPS/SITE: demo runs 0.1.0; ops redeploys 0.1.2+ at leisure (Linux
   memory: MemoryMax + restart stays). Wire the owner's cover image
   (resources\img\) into the product landing when it lands.
6. Wrap at every stopping point: SESSION.md digest + the relay docs +
   PROGRESS.md, commit signed, push.

DISCIPLINE: probes in-repo; suites x2; outputs to files, never inherited
pipes (chatty servers: file-redirect stdout; the PS smoke reads exit
codes through a cmd wrapper); durable step logs for crash-prone runs;
every struct literal lists every field; no module-scope package
constructors (Vec-holder pattern); no const-receiver .to_str(); explicit
*p for &mut Int reads; quoted dotted TOML dep keys; avoid inner quotes
driving WSL from PS (write scripts to files); `wsl --shutdown` on
CLR/paging errors (system commit pressure, not the build); after any
toolchain maintenance verify the package store (xiom doctor; re-add with
xiom pkg install); avoid io.list_dir until C-PULSE-17 is fixed (dangling
names); guard io.create_dir with io.is_dir (its contract requires the
path NOT to exist); kill stray test servers/scripts after any stopped
monitor.
```

## 3c. Paste prompt (2026-10-07, superseded)

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (official XIOM
full web backend). Read SESSION.md first, then docs\PROGRESS.md and the
reference relay docs it lists. Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; do not push to origin without owner approval. Identity
"Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Track the LATEST toolchain: Windows compiler v0.64.0
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe); Linux/WSL compiler v0.64.0
(~/.local/share/xiom) — the Linux lane is verified and every script has a
verified .sh twin (scripts/*.sh + scripts/lib.sh). XIOM_RUNTIME_DIR
retired. Registry consumption still needs xiom.toml source-roots
(C-PULSE-02).

TASK ORDER (owner-ordered, 2026-10-07 wrap):
1. WINDOWS RE-VERIFY of the registry wave: first run
   `xiom pkg install xiom.metrics@0.2.0 xiom.http.middleware@0.1.0
   xiom.static@0.1.0` (the app imports them now; Windows source-roots are
   already in xiom.toml), then suites x2 + smoke + crash + rate on
   Windows; record deltas vs the Linux run.
2. Continue M4/M5 per docs\PROGRESS.md: keep-alive, schema helper, recv
   timeouts (stdlib), CI file when the repo goes public, packaging per
   docs/OPS-REQUEST.md.
3. Watch the compiler lane for C-PULSE-08 (m212 dotted-key gate:
   docs/repro/dep-roots-name-form both variants must exit 0), C-PULSE-09
   (xiom.session store integration crash), C-PULSE-10 (xiom.kv kv_get
   corruption; probe_pkg_kv is the known-red gate), C-PULSE-11 (package
   type aliases). Re-run the probes when the next archive lands; swap the
   session store and the kv backend when green.
4. Update SESSION.md STATE + the three relay docs + PROGRESS.md at every
   wrap; commit signed (DCO -s).

Discipline: every struct literal lists every field; never init module
vars with package constructors (use the Vec-holder pattern,
probe_pkg_state_holder); no const-receiver .to_str(); explicit *p for
&mut Int reads; quote dotted TOML dep keys; probes in-repo; suites x2;
outputs to files, never inherited pipes; durable step logs for anything
that can crash (io.flush_stdout is a no-op).
```

## 3b. Paste prompt (2026-10-05, superseded)

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (official XIOM
full web backend). Read SESSION.md first, then docs\PROGRESS.md and the
reference relay docs it lists. Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; do not push to origin without owner approval. Identity
"Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Track the LATEST toolchain: compiler v0.64.0
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe), stdlib E:\xiom-lang\stdlib,
XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1. Registry
consumption needs xiom.toml source-roots (C-PULSE-02, still open).

TASK ORDER (owner-ordered, 2026-10-07):
1. PORT EVERY SCRIPT TO A .sh TWIN so Linux developers can use them:
   scripts\dev-env, run, build, http_smoke, soak_http, soil_tcp?, concurrent,
   crash_test, rate_smoke, store_soak, proxy_e2e -> each gets a bash
   equivalent that runs on WSL/Linux (same flags, same exit-code gating,
   watchdog via `timeout`). Verify each .sh from WSL before moving on.
2. ADOPT THE PUBLISHED REGISTRY WAVE (all signature-verified):
   xiom.metrics 0.2.0 (labels + latency preset) to replace/extend our
   counters; xiom.http.middleware 0.1.0 for the middleware chain;
   xiom.session 0.1.0 to replace src\session.xi; xiom.static 0.1.0 for
   favicon/landing serving; xiom.kv 0.1.0 as the durable store backend
   (keep the JSONL fallback documented). Run each consumer probe first
   (tests\probes\probe_pkg_*.xi pattern), then swap, suites x2 + smoke.
3. Continue M4/M5 per docs\PROGRESS.md (proxy E2E is GREEN 11/11 via
   scripts\proxy_e2e.ps1 + deploy\nginx\pulse.conf.example; keep-alive,
   schema helper, audit rotation, CI file when public).
4. Update SESSION.md STATE + the three relay docs + PROGRESS.md at every
   wrap; commit signed.

Discipline: every struct literal lists every field; never init module vars
with package constructors; no const-receiver `.to_str()` (use
convert.int_to_string); explicit `*p` for &mut Int reads; probes in-repo;
suites x2; outputs to files, never inherited pipes (Start-Process +
redirection, bounded socket polls, kill by PID tree).
```

