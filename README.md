# xiom-pulse

**XIOM PULSE** is the official XIOM full web backend: a plaintext HTTP/1.1
service on XIOM, TLS terminated by a front proxy (Caddy/nginx), built as an
**external project** that consumes the XIOM stdlib and registry packages
(see the stdlib `docs/STDLIB_EXTENSION.md` S9 plan).

> **Status:** Step 0-1 active development. Not production-ready.
> **Consumer lane:** this repo never edits `E:\xiom-lang\stdlib`,
> `E:\xiom-lang\xiom`, or `E:\xiom-packages\packages`; upstream defects are
> reported through minimal repro bundles + findings rows in `SESSION.md`.

## Toolchain pin (fixed 2026-10-05)

| Component | Pin |
|---|---|
| Compiler | v0.63.1 (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`) |
| Stdlib | `E:\xiom-lang\stdlib` |
| Runtime | `E:\xiom-lang\stdlib\runtime` **via `XIOM_RUNTIME_DIR`** |

`XIOM_RUNTIME_DIR` is **required** on this pin: the installed compiler's AOT
link only links `xiom_runtime.c`, so any program whose closure uses the
monotonic clock (`xiom_async_now_ms`, including the stdlib test harness)
fails with `lld-link: undefined symbol: xiom_async_now_ms`. The override
makes the link include `async_runtime.c` + `sha256_sw.c` and the rest of the
runtime dir. Repro: `xiom-packages` commit `5b7547b0`
(`docs/repro/runtime-link/`).

## Start here

```powershell
. .\scripts\dev-env.ps1          # sets XIOM_COMPILER / XIOM_STDLIB / XIOM_RUNTIME_DIR
.\scripts\run.ps1 tests\test_smoke.xi
```

- `SESSION.md` -- live state, pin, open blockers, findings rows (upstream relay).
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
