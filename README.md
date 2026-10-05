# xiom-pulse

**XIOM PULSE** is the official XIOM full web backend: a plaintext HTTP/1.1
service on XIOM, TLS terminated by a front proxy (Caddy/nginx), built as an
**external project** that consumes the XIOM stdlib and registry packages
(see the stdlib `docs/STDLIB_EXTENSION.md` S9 plan).

> **Status:** Step 0-1 active development. Not production-ready.
> **Consumer lane:** this repo never edits `E:\xiom-lang\stdlib`,
> `E:\xiom-lang\xiom`, or `E:\xiom-packages\packages`; upstream defects are
> reported through minimal repro bundles + findings rows in `SESSION.md`.

## Toolchain (latest-tracking, owner decision 2026-10-05)

PULSE tracks the **latest** compiler / stdlib / packages to harden the
ecosystem through real use; public release comes later. Exact versions and
lane hashes are recorded in `SESSION.md` at every wrap.

| Component | Current |
|---|---|
| Compiler | **v0.64.0** (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`) |
| Stdlib | `E:\xiom-lang\stdlib` (stdlib-lane checkout, latest) |
| Packages | registry (`%LOCALAPPDATA%\xiom\packages`): xiom.http 0.1.1, xiom.cookie 0.1.1, xiom.jwt 0.2.0 |

`XIOM_RUNTIME_DIR` is **retired** on v0.64.0 (release R65 links the
installed `lib\runtime` + `lib\xiom`): PULSE verified env-free with both
`XIOM_STDLIB` and `XIOM_RUNTIME_DIR` unset. Historical workaround context
is in the relay docs under `docs/`.

## App icon

The official icon lives at `resources/img/pulse-ico.ico` and is served by
the running service at `GET /favicon.ico` (with a minimal `GET /` landing
page linking it). Windows **exe** icon embedding is not yet supported by
the AOT toolchain (no `--icon`/resource flag) -- filed as a feature gap in
`docs/COMPILER-FINDINGS-PULSE.md`; the asset is committed so the app can
adopt it the moment the toolchain grows support.

## Start here

```powershell
. .\scripts\dev-env.ps1          # sets XIOM_COMPILER / XIOM_STDLIB / XIOM_RUNTIME_DIR
.\scripts\run.ps1 tests\test_smoke.xi
```

- `SESSION.md` -- live state, pin, open blockers, findings rows (upstream relay).
- `docs/PROGRESS.md` -- **weighted production-grade tracker** (what works, what is pending, % done).
- `docs/DEPLOYMENT.md` -- proxy-first TLS deployment (Caddy/nginx, env, supervision).
- `docs/repro/` -- minimal upstream repro bundles.
- `src/` -- the service; `tests/` -- suites and probes.

## Design constraints (from the pinned toolchain)

- No real OS threads (`xiom.thread.spawn` is an inline simulation); the
  service is a single-threaded sequential-accept server until the runtime
  grows select/threads.
- No socket timeouts / non-blocking mode (runtime stubs return documented
  `Err`); slow-client handling is a known limitation.
- TLS is terminated by the front proxy; in-XIOM TLS is not on the critical
  path.
- Always `Connection: close` per request on the thin slice.
