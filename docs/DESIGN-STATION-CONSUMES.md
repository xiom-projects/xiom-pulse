<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Station consumes `xiom.pulse` (Beacon) -- adoption design + evidence matrix

Reference-study unit for the closing half of the Beacon acceptance
(`REL-20261016-1810-packages-3`): PULSE Station consumes the published
`xiom.pulse` 0.1.0 (eco-v0.1.192, sha256 `53fcc56e...`) and the full
fleet runs against it -- the final verify evidence ("one core, never a
fork").

References: the PROVENANCE byte-set (carved = verbatim module list);
fastify plugin encapsulation + gin context/middleware (core-vs-product
composition, `docs/PRODUCTION-REFERENCES.md`); the compiler catalog
behavior observed below.

## Finding A -- module precedence (2026-10-17, pinned v0.64.5)

With `"xiom.pulse" = "0.1.0"` declared and product modules present, the
catalog resolves DUPLICATE module names **in favour of the dependency**
and only warns (`W001`):

```
warning[W001]: module 'xiom.pulse.app' declared by 2 files
  [<store>/xiom-pulse/src/server.xi, 'src\server.xi']; using '<store>/...'
warning[W001]: module 'xiom.pulse.config' declared by 2 files [...]
warning[W001]: module 'xiom.pulse.router' declared by 2 files [...]
```

The shadowed product modules then fail downstream (`router.route_match
expects 2 argument(s), found 3`; `app.handle_route expects 4 argument(s),
found 3`; `load_icon` missing) -- i.e. the transition is impossible
without renaming the product's colliding modules. Relayed: resolver
policy to compiler; the module-precedence answer goes into the packages
0.2 wishlist.

## Target module map

| File | Today | Target |
|---|---|---|
| `src/http.xi`, `src/envelope.xi`, `src/reqctx.xi`, `src/pulse.xi` | `xiom.pulse.*` | **deleted** -- byte-identical, provided by the package (PROVENANCE sha set verified at the extraction) |
| `src/server.xi` | `xiom.pulse.app` | `xiom.pulse.station.app` (product loop: metrics/audit/CORS/session wiring live here) |
| `src/config.xi` | `xiom.pulse.config` | `xiom.pulse.station.config` (rich product knobs; the package's config is the six loop knobs) |
| `src/router.xi` | `xiom.pulse.router` | `xiom.pulse.station.router` (mechanism + the product `route_defs()` table) |
| `src/version.xi` (new) | -- | `xiom.pulse.station.version` -- the product version source; it must NOT come from the consumed package (the package has its own release line) |
| all other modules | unchanged | no name collisions with the package |

Import rewrites (10 files / 18 lines as of 2026-10-17):
`src/{server,openapi,game,store,cors}.xi`, `tests/test_http.xi`,
`tests/test_app.xi`, and `tests/probes/{probe_app_flow,probe_app_flow2,probe_adopt_smoke}.xi`.

Manifests: `xiom.toml` + `package.xi` deps gain `"xiom.pulse" = "0.1.0"`;
the CI installer list (`setup-xiom` action) gains `xiom.pulse@0.1.0`.

## Adoption sequence

1. Rename the three product modules + rewrite the 18 imports (mechanical,
   no logic changes).
2. Delete the four byte-identical files; declare the dep in both
   manifests + the CI installer.
3. Build `pulse_app`; suites x2 + smoke x2 on both platforms must stay
   green (134/134); crash harness x2 (store untouched -- smoke covers the
   path); CI dry run on the push.
4. File the stage-2a result to packages. Stage 2b (full loop adoption)
   stays GATED on the hook seam (packages wishlist) + the middleware
   chain (queue item 3).

## Stage 2a result -- GREEN (2026-10-17, session 20)

- Renamed `app`/`config`/`router` to `xiom.pulse.station.*` and rewrote the
  18 imports across the 10 files listed above; no logic changes.
- Deleted `src/http.xi`, `src/envelope.xi`, `src/reqctx.xi`,
  `src/pulse.xi` after re-confirming the four SHA256s against the installed
  package (all hash-equal at `...\xiom\packages\xiom-pulse-0.1.0`).
- Added `src/version.xi` as Station's own version source; release tooling
  (`scripts/release.{ps1,sh}`, the `release.yml` tag guard) and
  `tests/test_smoke.xi` now read it. The package's carved root module is no
  longer the product version source.
- Declared `"xiom.pulse" = "0.1.0"` in `xiom.toml` + `package.xi` and added
  `xiom.pulse@0.1.0` to the CI installer; adopted the latest registry deps
  (`xiom.http` 0.1.8, `xiom.cookie` 0.1.2, `xiom.jwt` 0.2.1) per the owner
  directive (always consume the latest fixes).
- Toolchain: XIOM v0.64.6 + stdlib release `8d95815` (tag
  `stdlib-v0.64.6`; `STDLIB_VERSION` + all three workflow pin blocks
  updated with the v0.64.6 SHA256 set).
- Gates (both platforms): build green; suites x2 (`test_http` 77,
  `test_app` 237, `test_smoke` 4, all rc=0); HTTP smoke 134/134 x2
  (jsonl + kv); crash harness x2 GREEN. Evidence:
  `probe-logs/station-consumes-2a/` (local, gitignored).
- Adjacent fix (ops `REL-20261017-1141-ops`): site-mode file responses
  emitted `Content-Length` twice (static engine + response builder);
  the static copy is dropped and the suite locks a single CL. Live check:
  200 and 304 site responses each carry exactly one CL.
- Finding C (to packages): the carved package hardcodes product-version
  literals -- `pulse_version()` returns `0.2.1` and `http.xi` emits
  `Server: xiom-pulse/0.2.1` twice. Station no longer consumes the root
  version, but the `Server` header is package-owned and cannot be bumped by
  a Station cut. Ask: parameterize the header (or make it neutral) in the
  0.2.0 hook-seam publish.
- Stage 2b stays GATED on the hook seam (packages acked
  `REL-20261017-1123-pulse-2`, implementation dispatched) + the middleware
  chain.

## Finding B -- shared-home clobber (2026-10-17)

The Windows shared package home was reset overnight: PULSE's installs
(`xiom.pulse`, `xiom.template`, `xiom.ssl`, `xiom.brotli`) vanished while
other lanes' packages remained; the WSL store was unaffected. Reinstalled
(checksum re-verified); flagged to ops as a recurrence risk of the 1852
clobber class.

## Rollback

Pure rename + dependency declaration: `git revert` restores the
monolith; no data or wire-format changes.
