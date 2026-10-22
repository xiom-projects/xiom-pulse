<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE release checklist (mechanical cut)

History lesson: `pulse-v0.1.1` was tagged but never released because its
CI gate tripped on a **stale version literal**; release tags are
immutable, so every literal below must be updated and verified BEFORE
tagging. Follow this list in order. Scope: any release; the 0.2.0
preconditions are called out where they differ.

## 0.3.0 readiness (2026-10-21)

**Included and green now:**

- Keep-alive A/B, durability A/B, middleware Phase A (read / gate /
  dispatch / after_response; gate order 11/11), SQL class MVP
  (migrations 21/21) plus the opt-in repository/query layer (53/53),
  SSE + WebSocket (Origin policy, fragmentation, startup registry,
  per-route rate; 57/57 + 20/20 live), static conditional/Range, bttger
  baseline, linux-arm64 CI and release packaging dry-run.
- Gating matrix: **linux-x64, linux-arm64, windows-x64**; suites x2 /
  smoke x2 / crash x2; SQL/migrations/stream on both Linux legs.
  Release dry-run `39588855890` green with three packages + provenance.

**Not in the 0.3.0 cut (blocked or deferred):**

- Compiler **m371** -> middleware Phase B (the legacy loop stays).
- Jobs core.
- macOS release assets: **macOS x64 is gating and green** with
  compiler v0.64.8 + stdlib-v0.64.9 (`macos-15-intel`; full gates).
  macOS arm64 is non-gating pending 0717/`REL-20261022-1529-pulse`;
  22.04 arm64 has the same finding, so the gating Linux arm64 leg uses
  ubuntu-24.04. The **v0.64.9 compiler is WITHDRAWN**
  (`REL-20261022-1826-compiler`); production stays v0.64.8 and **v0.65.0**
  is the next gate. The user StreamHandler registry and arm64 fixes wait
  for that pin; enable macOS packaging after it.
- **Per-request retention on the serving path** (compiler m375 / no
  drop glue; `REL-20261010-1549-pulse-4`, new stdlib
  `REL-20261022-2049-pulse`): measured 2026-10-22 on v0.64.8 + stdlib
  `aa8b656`, the stock `pulse_app` retains **55-60 KB per
  `GET /health`** (keep-alive and connection-per-request alike); bttger
  retains 39 KB (tiny GET), 89-96 KB (`POST /insert`) and 1.14 MB
  (`GET /serialize/big`) per request. At 100 rps that is ~5.5 MB/s. This
  is no longer a JSON-only or benchmark-only issue: a 0.3.0 server
  cannot run sustained load on this pin without a restart/RSS-cap
  policy. **Owner decision:** wait for the compiler drop-glue fix plus
  the stdlib `socket_recv_into` mitigation, or ship 0.3.0 with the
  limitation documented. The stdlib JSON builders
  (`REL-20261020-1704-pulse`) remain the O(tree) amplifier.
- Dynamic user stream handlers and WS authentication.

**Decision proposed (2026-10-22):** cut 0.3.0 with the above scope. The
serving SQL surface is decided as an **opt-in application library**;
the stock `pulse_app` stays SQL-free (`docs/DESIGN-SQL-SERVING.md`).
Jobs / Phase B / macOS remain later work. Owner approval is the only
remaining gate; the mechanical bump+tag steps below are unchanged.

## 0. Preconditions

- **linux-arm64 leg (0.3.0+):** the release matrix now packages
  `linux-arm64` on `ubuntu-24.04-arm` natively (`scripts/release.sh`
  auto-detects aarch64 and names `pulse-<ver>-linux-arm64.zip`). The
  dry-run fleet must be green before the bump. Release assets therefore
  include linux-x64, linux-arm64 and windows-x64 by default.
- **macOS legs (0.2.0 only):** the compiler/stdlib pairing must carry
  the three darwin items (SESSION digest: stdlib `xiom_runtime.c`
  `_SC_AVPHYS_PAGES`, stdlib `fp128_helpers.c` x86 asm, compiler
  `@llvm.memset.p0i8.i64` emission). Then:
  `gh variable set RELEASE_BUILD_MACOS --body true` and dry-run **all
  four legs** green before the bump.
- **Full fleet, both platforms, pinned stdlib:** probe fleet (12/12,
  incl. `probe_outbound_guard`) + m212 gate + suites x2 + smoke
  (119/119, jsonl + kv) + rate + crash. Interop probes where the sibling
  trees exist (not CI).
- Tree clean; every relay/doc update for the release already committed.

## 1. Version literals (bump together)

| File | Literal |
|---|---|
| `src/version.xi` | `pulse_version()` return string (Station product version) |
| `src/server.xi` | `const APP_VERSION: Str` |
| `package.xi` | `version:` field |
| `xiom.pulse` 0.1.0 (consumed) | `Server: xiom-pulse/<ver>` -- **two** literals in the package's `http.xi`; not editable here. A product-version bump needs a package seam (version parameter/neutral header) or the header stays at the package's carved literal (flagged to packages 2026-10-17). |
| `tests/test_smoke.xi` | expected `pulse_version()` literal |
| `tests/test_http.xi` | `/api/version` body literal |
| `tests/test_app.xi` | openapi `"version": "<ver>"` literal |
| `scripts/http_smoke.ps1` | `version value` check literal |
| `scripts/http_smoke.sh` | `version value` check literal |

After the bump, grep the repo for the OLD literal: hits must only remain
in CHANGELOG/history/relay prose -- never in `src/`, `tests/`,
`scripts/`, or `package.xi`.

## 2. Content

- `CHANGELOG.md`: retitle `[Unreleased]` to `[<ver>] - <date>`; move any
  trailing notes; keep the highlights the GitHub release body needs.
- `docs/public/releases.md`: add the release entry; `install.md` links
  follow `latest.json` automatically.
- Refresh behavior pages changed since the last cut (this cycle:
  `http-api.md`, `configuration.md`, `operations.md`, `security.md`,
  `index.md` were refreshed for 0.2.0).

### 0.2.0 included content (wrap 13/13c/14, all committed on main)

1. OpenAPI 3.1 served at `/openapi.json` + `pulse openapi` export;
   additive error `status` in every envelope; full CLI set
   (`openapi`, `routes`, `version`, `check-config`).
2. Pagination `Link` on `GET /api/events` (seq-in-record cursor,
   `next_cursor`, `?before=`, `400 invalid_cursor`).
3. Idempotency keys on event writes (replay `deduplicated:true`).
4. `/v1` versioned alias for every route.
5. Outbound client base: `xiom.http` 0.1.4 + `xiom.pulse.outbound`
   SSRF guard (+ `probe_outbound_guard` in the fleet).
6. Multipart uploads (`POST /api/uploads`, caps, generated names).
7. Interop probes green as repo evidence (ORBITDB 39/39, XVector 30/30;
   local-only, not shipped as artifacts).

## 3. Verify (before the tag)

- `pulse_app --version`, `GET /api/version`, `/openapi.json` version
  token, and the `Server:` header all report the new version.
- `pulse_app openapi --check` reports OK (the contract covers every
  router route; exit 1 lists drift).
- Full fleet AGAIN post-bump with the pinned stdlib on both platforms
  (suites x2 + smoke at minimum; the tag gate in CI re-runs it).
- `--check-config` output sane; JSON config overlay keys all load.

## 4. Cut

- Commit `release: v<ver>` (signed, DCO `-s`).
- Tag `pulse-v<ver>` on main; push `main` then the tag.
- CI release workflow: guard (tag == version, tag on main) -> package
  legs -> checksums -> GitHub Release (four zips + `.sha256` +
  `SHA256SUMS` + provenance when macOS is enabled).
- Ops: dl mirror pulls at :17; website buttons/badge auto-follow
  `latest.json`; the macOS button lights when its artifacts exist.

## 5. Post

- SESSION.md digest + `docs/PROGRESS.md` updated; demo redeploy noted
  (ops at leisure; the demo lags by design).
- Verify the mirror: `https://dl.xiom-lang.org/pulse/latest.json` names
  the new version + checksums.
