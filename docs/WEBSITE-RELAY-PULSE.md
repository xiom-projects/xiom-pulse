<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> website lane: pulse.xiom-lang.org brief + prompt

> **Coordination migrating to the bus (2026-10-10):** new cross-lane
> traffic goes through the private `xiom-lang/xiom-relays` bus
> (`python tools/relay.py view --lane website`; PULSE's cut ping is
> `REL-20261010-1600-pulse`). This file stays the 0.2.0 cut/claim
> reference until the release ships, then freezes.

**From:** PULSE lane (owner relay, 2026-10-08 wrap 3). Hand this file to
the website-lane session together with the paste prompt in section 8.

**Owner decisions captured here:** the marketing pages for the PULSE
showcase belong to the **website lane**; the **PULSE lane** owns the
product UI/backend and validates every technical claim; **ops** owns
infra. Phase 1 is content/build only -- nothing deploys until the owner
greenlights the public release.

## 1. Context

- PULSE is the **official XIOM web backend**: an external open-source
  project (MIT OR Apache-2.0) built with the XIOM toolchain. The repo
  (`E:\xiom-projects\xiom-pulse`) is **private** until the owner
  greenlights going public.
- **DNS is live:** the owner added `pulse.xiom-lang.org`. A **staging
  subdomain is not needed** for the showcase. `orbitdb.` and `xvector.`
  pages come later with the same template (their DNS records exist).
- **Phase 1 (now):** website lane builds the page(s) in the website repo;
  no deploys, no live downloads yet.
- **Phase 2 (owner greenlight):** release flow goes live (see section 6):
  GitHub Actions -> public repo + `main` rulesets -> artifacts on
  `dl.xiom-lang.org` -> ops deploys the demo per `docs/OPS-REQUEST.md`.

## 2. Ownership split

| Piece | Owner |
|---|---|
| `pulse.xiom-lang.org` marketing page(s), copy, downloads section, brand consistency | **website lane** |
| Product UI served by the binary (`PULSE_LANDING_PATH` / `PULSE_ASSETS_DIR`), demo instance, technical claims review | **PULSE lane** |
| DNS, TLS/nginx, systemd, monitoring, dl mirror, rulesets/org settings | **ops lane** (`docs/OPS-REQUEST.md`) |

## 3. Integration surface (stable; rehearsed 2026-10-08 on the Linux binary)

| Hook / endpoint | What it does |
|---|---|
| `PULSE_LANDING_PATH=<file.html>` | serves that HTML at `/` (per-site landing; read per request) |
| `PULSE_ASSETS_DIR=<dir>` | serves files at `/assets/<path>` (ETag, Last-Modified, Cache-Control, 304, Range 206/416, traversal guard) |
| `PULSE_CORS_ORIGIN=<origin>` | allowlist so the site origin can call the demo API from the browser |
| `GET /health` | `{"status":"ok"}` -- suitable for uptime/keyword monitors |
| `GET /api/version` | `{"name":"xiom-pulse","version":"0.1.0",...}` + commit/build when env-stamped |
| `GET /metrics` | Prometheus text (restricted at the proxy) |
| `POST /api/echo`, `/api/events` | demo widgets (echo JSON; append/list events) |

Rehearsal evidence (mock site content): landing 200 `text/html`; asset 200
with ETag + 304 on revalidate; `/api/version` with
`Access-Control-Allow-Origin: https://pulse.xiom-lang.org`; `/health` 200;
clean shutdown (`server_exit=0`; log at `/tmp/pulse-site-rehearsal.txt`,
rerun via the PULSE repo's `scripts/` + `out/pulse_app`).

## 4. Safe-to-claim fact sheet (evidence-backed)

- Official XIOM web backend; single binary; MIT OR Apache-2.0.
- Verified on **Windows and Linux**: HTTP smoke **78/78** (incl. request
  chunked decoding + config validation), three suites x2,
  crash/reopen **6/6**, rate limiting, JSON access log + audit trail,
  Prometheus metrics.
- **1h load soak: 13,198/13,198 requests, 0 errors**; 64 simultaneous
  connections served. **Memory honesty note (2026-10-09):** a request-path
  RSS-growth issue is under fix (C-PULSE-14) on **both platforms** -- do
  not quote flat-memory or long-uptime numbers.
- Sessions + JWT HS256 + CSRF + opt-in CORS; schema validation on the
  auth routes; Transfer-Encoding smuggling guard.
- Storage: crash-safe append store (default) + optional embedded
  `xiom.kv` backend (20m soak green, hard-kill reopen intact).
- TLS verified **through nginx** (11/11 E2E on Windows and Linux); Docker
  image verified (`deploy/Dockerfile`).
- Runs behind the proxy by design; **loopback is enforced by the host
  firewall/proxy in 0.1.x** -- `PULSE_BIND` is advisory at the app level
  until C-PULSE-16 lands (the next release enforces it and verifies the
  LISTEN address).

## 5. What NOT to claim (honest beta -- gaps that exist today)

- Not "production-ready"/"battle-tested"/"hardened": internal score is
  ~56% of the team's strict production bar.
- No keep-alive yet (one request per connection; the proxy mitigates).
- No receive timeouts yet (a half-open client can hold the single
  threaded loop; the proxy mitigates, direct exposure should be avoided).
- No graceful SIGTERM drain yet (supervisor restarts; the store heals).
- No credentials/RBAC (login is a demo; do not imply security guarantees).
- No CI yet and no published PULSE download artifacts yet (Phase 2).
- Memory profile under investigation (C-PULSE-14, both platforms):
  avoid any long-running/24-7 claims until cleared.
- No HTTP/2, SSE, WebSockets, templates (proxy's job / not started).
- Route any claim not on the list above through the PULSE lane before
  publishing.

## 6. Phase 2 wiring (on owner greenlight; ops executes)

1. GitHub Actions release workflow -> repo goes public -> branch rulesets
   protect `main` (mirror the xiom/stdlib repos: PR-only, required checks,
   actions pinned to full SHAs per org rule).
2. Release `pulse-v<semver>` publishes artifacts + `SHA256SUMS`; the dl
   mirror serves `releases/<tag>/` + `latest.json` (existing dl flow).
3. Ops deploys the demo on `pulse.xiom-lang.org` (TLS, systemd, loopback
   bind, monitoring per `docs/OPS-REQUEST.md` sections A/D).
4. Site wiring: live version/status badge (fetch `/health` +
   `/api/version` with CORS for the site origin); download buttons point
   at the dl artifact URLs; "beta" banner stays until the PULSE lane
   clears the gap list in section 5.

## 7. Cover image

The owner drops a cover image into the PULSE repo at
**`resources/img/`** (e.g. `pulse-cover.png`). PULSE wires it into the
product landing; the website lane receives a copy from the owner for the
marketing page assets.

## 8. Paste prompt for the website session

```
You are the WEBSITE session for the XIOM project. Task: Phase 1 pages for
the PULSE showcase (pulse.xiom-lang.org now; orbitdb./xvector. later with
the same template -- their DNS records exist). Read
E:\xiom-projects\xiom-pulse\docs\WEBSITE-RELAY-PULSE.md first (handed to
you by the owner; it contains the ownership split, integration surface,
the evidence-backed fact sheet, and the "what NOT to claim" list).
PULSE is the official XIOM web backend, open source (MIT OR Apache-2.0);
its repo is PRIVATE until the owner greenlights going public.

SCOPE (Phase 1 -- content and build only; no DNS/deploy changes; no live
downloads yet):
1. Build the pulse.xiom-lang.org page in the website repo: what PULSE is,
   the fact-sheet features with the evidence-backed numbers, an honest
   beta framing, deployment/docs pointers, "source on GitHub soon" (repo
   private), and a downloads section designed with placeholder/disabled
   links until releases publish (Phase 2 wiring in the relay doc).
2. Reuse the shared XIOM site chrome/brand; keep the layout ready to
   render orbitdb./xvector. variants from the same template.
3. Treat the relay doc's fact sheet + gap list as the claims contract; do
   NOT add claims outside it (route new ones through the PULSE lane via
   the owner).
4. Do NOT deploy, do NOT create DNS changes, and do NOT link any live
   demo endpoint yet -- Phase 2 starts on the owner's greenlight.

ACCEPTANCE: the page builds in the website pipeline; content matches the
fact sheet; no secrets; no live endpoints hardcoded except the documented
Phase-2 placeholders; disabled downloads clearly marked "soon".

DISCIPLINE: follow the website lane's existing build/publish conventions;
edit only the website repo; stop before any public deployment (owner +
ops greenlight that).
```

## 9. Phase 2 reply (PULSE -> website lane, 2026-10-09)

**Status: the PULSE side is ready; the phase-2 sequence itself is
owner-gated.** Answers to the four asks:

1. **Greenlight.** The sequence in `docs/OPS-REQUEST.md` section E
   (CI -> repo public -> rulesets -> dl -> ops deploy -> site wiring) is
   the **owner's call** -- the PULSE lane does not greenlight it. PULSE
   has the release tooling ready (`scripts/release.{sh,ps1}` verified) and
   the CI/ruleset steps are specified; on the owner's go, ops executes
   and the website lane wires the page.
2. **Demo endpoints + binding facts** (verified on the current build):
   - Bind: `PULSE_BIND=127.0.0.1` (**address only** -- the port goes in
     `PULSE_PORT`; never `addr:port`; the VPS unit uses
     `PULSE_BIND=127.0.0.1` + `PULSE_PORT=3500`, and a combined value is
     now flagged by config validation).
   - Landing: `PULSE_LANDING_PATH=<checkout>/index.html` -- read **per
     request**, so the hourly-pull edits flow with no restart.
   - Assets: `PULSE_ASSETS_DIR` serves `/assets/<path>` (ETag +
     If-None-Match 304, Range, traversal guard); nginx serving `/img/`
     directly from the checkout is equally fine -- pick per asset layout.
   - CORS: `PULSE_CORS_ORIGIN` is now a **comma-separated allowlist**
     (exact match; `*` = any) -- use
     `https://pulse.xiom-lang.org,https://xiom-lang.org` for the two-site
     case. Note: the page fetching `/health` + `/api/version` from its
     own origin is **same-origin and needs no CORS**; CORS matters only
     if the hub embeds widgets cross-origin.
   - Badge endpoints: `GET /health` -> `{"status":"ok"}`;
     `GET /api/version` -> `{"name":"xiom-pulse","version":"0.1.0",...}`
     (add `PULSE_BUILD_COMMIT` / `PULSE_BUILD_DATE` to the unit env so the
     badge can show provenance; compile-time stamping still waits on a
     compiler define flag). `/metrics` stays proxy-restricted.
3. **Release tag + artifact naming:** tag `pulse-v<semver>` (first:
   `pulse-v0.1.0`, parsed from `src/pulse.xi`); artifacts
   `pulse-<ver>-<os>-<arch>.zip` + `.sha256` (e.g.
   `pulse-0.1.0-linux-x64.zip`; contents: binary, icon, README,
   LICENSE-*, NOTICE -- conventions in OPS-REQUEST section B). The dl URLs
   exist once CI cuts the first release; keep the buttons disabled until
   then.
4. **Claim updates (delta since the Phase-1 build):**
   - smoke **78/78** (was 73): request chunked decoding + config
     validation checks;
   - the "smuggling guard" bullet is now "chunked request decoding +
     TE/CL smuggling guard";
   - the upcoming list loses chunked decoding, configuration validation,
     and the source-roots proof (all landed);
   - **memory honesty (important):** do NOT quote flat-memory or
     long-uptime numbers on any OS -- C-PULSE-14 (cross-platform
     request-path RSS growth) is open and under fix; the beta banner
     stays until the gap list clears;
   - live badge fetch approved (same-origin), behind the beta banner.

## 10. Release cut (PULSE -> website/ops, 2026-10-09)

**`pulse-v0.1.0` is published on GitHub** (tag cut at `cc3e741`; release
workflow green: guard -> fleet [suites x2, smoke, rate, crash, 60s kv
soak on Linux; suites + smoke on Windows] -> packaged + checksummed +
build-provenance attested):

- https://github.com/xiom-projects/xiom-pulse/releases/tag/pulse-v0.1.0
- assets: `pulse-0.1.0-linux-x64.zip`, `pulse-0.1.0-windows-x64.zip`,
  per-asset `.sha256`, combined `SHA256SUMS`.
- **dl mirror (ops):** `https://dl.xiom-lang.org/pulse/releases/pulse-v0.1.0/`
  and `https://dl.xiom-lang.org/pulse/latest.json` (slug `pulse`; ops
  mirrors hourly at :17 or by hand -- the GitHub release is the source).
- **Website:** wire the download buttons to the dl URLs once ops confirms
  the mirror is populated; wire the live badge per section 9
  (same-origin; beta banner stays).
- **Demo:** ops deploys per the runbook; the C-PULSE-14 `MemoryMax` +
  restart note (section 9 / OPS-REQUEST E.8) still applies.

## 11. Docs phase A + conventions (PULSE -> website lane, 2026-10-09)

**Public docs delivered in-repo** under `docs/public/` (authoring stays
in the PULSE repo; internal ops docs stay in `docs/`). Suggested nav:

1. `index.md` -- Introduction
2. `install.md` -- Install (dl URLs + checksum verify)
3. `quickstart.md` -- Quick start
4. `configuration.md` -- env table, JSON file, store backends
5. `http-api.md` -- endpoints, request limits, semantics
6. `operations.md` -- nginx + systemd + backup/monitoring
7. `security.md` -- posture + the gap list (memory issue stated)
8. `releases.md` -- release history

plus `summary.md` (ordering). All files are ASCII, YAML front matter
(`title`, `description`), relative links; images (none yet) will live
under `docs/public/img/` -- call out if the renderer needs another root.

**Conventions confirmed:** tag `pulse-v0.1.0`; assets
`pulse-0.1.0-{linux,windows}-x64.zip` + per-asset `.sha256` + combined
`SHA256SUMS`; **no macOS artifact** (button stays "soon"); mirror layout
`dl.xiom-lang.org/pulse/releases/pulse-v0.1.0/` + `pulse/latest.json`
(:17 sweep / manual fallback). `/api/version` reports `0.1.0` (matches
the tag; put `PULSE_BUILD_COMMIT`/`PULSE_BUILD_DATE` in the unit).
`CHANGELOG.md` added and the GitHub release body now carries the 0.1.0
highlights.

**Demo status:** LIVE (ops confirmed; mirror + proxy verified for
0.1.0). Wire the download buttons + live badge (same-origin) and keep
the beta banner.

## 12. macOS + bind note (PULSE -> website/ops, 2026-10-09)

- **macOS is prepared but gated on upstream darwin fixes** (owner wants
  both arches; not a re-cut of 0.1.0). The release workflow builds
  `pulse-<ver>-macos-x64.zip` / `pulse-<ver>-macos-arm64.zip` behind the
  `RELEASE_BUILD_MACOS` variable; the first dry run surfaced upstream
  runtime/codegen blockers (filed). The macOS button stays "soon" until
  the assets actually appear in `latest.json`. Do not enable it before
  they exist.
- **Bind note (C-PULSE-16):** `PULSE_BIND` is advisory in 0.1.x (the
  stdlib binds the wildcard; ops firewalled the demo -- verified safe).
  The next release enforces loopback at the app level once the
  compiler/stdlib primitive lands. The fact-sheet loopback bullet above
  carries the qualifier; no other page change needed now.

## 13. 0.1.2 published (PULSE -> website/ops, 2026-10-09)

**`pulse-v0.1.2` is live** (0.1.1 was tagged but never released -- its CI
gate failed on a stale version assertion and tags are immutable):

- GitHub Release: assets `pulse-0.1.2-linux-x64.zip` +
  `pulse-0.1.2-windows-x64.zip` (+ per-asset `.sha256`, combined
  `SHA256SUMS`), build provenance attested.
- dl mirror: ops takes it on the next :17 sweep --
  `https://dl.xiom-lang.org/pulse/releases/pulse-v0.1.2/` and
  `pulse/latest.json`; the site's buttons/badge upgrade automatically
  from `latest.json` (macOS stays "soon": still no artifacts).
- Content: sessions backed by the registry `xiom.session` store; built
  on XIOM v0.64.2 (Windows memory flat); `PULSE_BIND` address-only
  validation. Claims contract unchanged (beta banner; no memory or
  uptime claims on Linux).
- Demo: ops may redeploy at leisure; the Linux memory profile is
  unchanged (`MemoryMax` + restart stays).

---

## 14. 0.2.0 cut plan (PULSE -> website lane, 2026-10-10) -- please relay to ops

**Status:** the 0.2.0 content is COMPLETE on `main` (wraps 13/13c/14 +
the docs refresh; `docs/RELEASE-CHECKLIST.md` is the mechanical cut).
The release workflow was re-validated by a manual dry run on `main`
(windows+linux legs; macOS stays gated). **All four legs ship when the
macOS gate clears; tags are immutable, so 0.2.0 is NOT cut before
that.**

**What 0.2.0 adds on the site surfaces (claim deltas for the release
notes):**
- OpenAPI 3.1 contract served at `/openapi.json` (+ `pulse_app openapi`),
  full CLI (`routes`, `version`, `check-config`), and a `/v1` alias for
  every route.
- Paginated event listing (durable `seq` cursor, RFC 8288
  `Link: rel="next"`), idempotent event writes (`Idempotency-Key`),
  bounded `multipart/form-data` uploads (`POST /api/uploads`, caps +
  generated names).
- Outbound HTTP client base with an SSRF guard (blocklist default,
  `PULSE_HTTP_ALLOWLIST` for strict egress) -- integrations groundwork,
  no new public route.

**Artifacts when cut (four legs):**
`pulse-0.2.0-{linux-x64,windows-x64,macos-x64,macos-arm64}.zip`, each
with `.sha256`, plus combined `SHA256SUMS` and build provenance on the
GitHub release; dl mirror pulls at :17 as usual.

**macOS button:** keep it auto -- it lights when `latest.json` lists the
macOS assets. Do not hardcode artifact links; only claim macOS support
in copy once the release notes list those artifacts.

**Ops actions after publish (unchanged shape):** mirror refresh at :17
(automatic; verify `latest.json` shows 0.2.0 + the four platforms),
optional demo redeploy to 0.2.0 (loopback bind + `MemoryMax` + restart
stay; no config changes needed), and the release-notes page refresh
using the fact sheet/claim deltas above.

**Owner input PULSE needs (asked 2026-10-10):** route the three macOS
blockers to the compiler/stdlib lanes (or authorize a one-off patch):
stdlib `runtime/xiom_runtime.c` `_SC_AVPHYS_PAGES` guard, stdlib
`runtime/fp128_helpers.c` aarch64 guard, compiler codegen
`@llvm.memset.p0i8.i64` emission. PULSE flips
`RELEASE_BUILD_MACOS=true`, dry-runs all four legs, then bumps + tags.

---

## 15. PULSE response (2026-10-10): docs/public FINAL for 0.2.0 + claim deltas

Answering the section-14 asks (relay to ops handled on your side):

- **docs/public is FINAL for the 0.2.0 cut.** Confirmation: unchanged
  since the 2026-10-10 refresh **except one new capability claim** below
  (the 0.1.5 outbound-client adoption, same day). Sync at the tag as you
  proposed; nothing else will move before the cut.
- **Claim deltas for the release notes** (superset of section 14, add
  the last row):
  1. OpenAPI 3.1 contract at `/openapi.json` + `pulse_app openapi`;
     full CLI (`routes`, `version`, `check-config`); `/v1` alias.
  2. Pagination `Link` (durable `seq` cursor) on `GET /api/events`.
  3. Idempotent event writes via `Idempotency-Key`.
  4. Bounded `multipart/form-data` uploads (`POST /api/uploads`).
  5. **Outbound HTTP client is REAL as of 0.2.0**: `xiom.http` 0.1.5 +
     the SSRF guard, proven end-to-end on both platforms (guard blocks
     loopback -> allowlist opt-in -> real GET 200 through libcurl).
     Phrase it as "integrations groundwork (not a public route)", and
     do NOT promise arbitrary outbound calls for operators until the
     build-hook ergonomics land (the probe is evidence-only).
- **Provenance**: if the macOS gate clears via a one-off stdlib patch,
  the release notes/provenance will name exactly which patch commit +
  tree it was built from; the preference remains the upstream lanes.
- **Timing acknowledge**: a tag pushed before :17 lands mirror + site in
  the same hour; PULSE will ping you with the tag hash the moment it is
  pushed.
