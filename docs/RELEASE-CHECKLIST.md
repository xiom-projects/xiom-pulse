<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE release checklist (mechanical cut)

History lesson: `pulse-v0.1.1` was tagged but never released because its
CI gate tripped on a **stale version literal**; release tags are
immutable, so every literal below must be updated and verified BEFORE
tagging. Follow this list in order. Scope: any release; the 0.2.0
preconditions are called out where they differ.

## 0. Preconditions

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
| `src/pulse.xi` | `pulse_version()` return string |
| `src/server.xi` | `const APP_VERSION: Str` |
| `src/http.xi` | `Server: xiom-pulse/<ver>` -- **two** occurrences (`response_head` paths) |
| `package.xi` | `version:` field |
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
