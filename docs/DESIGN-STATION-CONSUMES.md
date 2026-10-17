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

## Finding B -- shared-home clobber (2026-10-17)

The Windows shared package home was reset overnight: PULSE's installs
(`xiom.pulse`, `xiom.template`, `xiom.ssl`, `xiom.brotli`) vanished while
other lanes' packages remained; the WSL store was unaffected. Reinstalled
(checksum re-verified); flagged to ops as a recurrence risk of the 1852
clobber class.

## Rollback

Pure rename + dependency declaration: `git revert` restores the
monolith; no data or wire-format changes.
