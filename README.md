# xiom-pulse

**XIOM PULSE** is the official XIOM full web backend: a plaintext HTTP/1.1
service on XIOM, TLS terminated by a front proxy (Caddy/nginx), built as an
**external project** that consumes the XIOM stdlib and registry packages
(see the stdlib `docs/STDLIB_EXTENSION.md` S9 plan).

This repository ships **PULSE Station** -- the standalone (hosted) edition.
The embeddable core is packaged separately as **PULSE Beacon** (registry id
`xiom.pulse`), and Station consumes that same package -- **one core, never a
fork**. Tier map below.

> **Status:** 0.2.1 released (linux-x64 + windows-x64, tag `pulse-v0.2.1`);
> a live demo runs at pulse.xiom-lang.org. Not top-tier complete yet --
> weighted tracker in `docs/PROGRESS.md`.
> **Consumer lane:** this repo never edits `E:\xiom-lang\stdlib`,
> `E:\xiom-lang\xiom`, or `E:\xiom-packages\packages`; upstream defects are
> reported through minimal repro bundles + findings rows in `SESSION.md`.

## Two tiers, one core: PULSE Beacon (tier 1) / PULSE Station (tier 2)

PULSE is one protocol core shipped as **two tiers** (the ecosystem
satellite/station pattern -- orbitdb and xvector follow the same tier map):
**tier 1** = the registry tier, the embeddable core package; **tier 2** =
the standalone tier, the hosted product. Codenames identify the tier
(convention `REL-20261016-1446-packages`); registry ids stay functional
(`xiom.pulse`). Working names `pulse-sails` / `pulse-satellite` /
`pulse-sonde` are retired; the canonical name stays **XIOM PULSE** for both
tiers (full plan: `docs/ROADMAP-TOP-TIER.md` section 9).

| | **PULSE Beacon** (tier 1 -- registry package) | **PULSE Station** (tier 2 -- standalone product) |
|---|---|---|
| **What** | the framework core as a registry package -- id `xiom.pulse` | the full product this repo ships today (`pulse-v*` releases) |
| **Use when** | you embed HTTP into an existing XIOM program: engine control endpoints, playground workers, xvector services, docs tooling, user apps -- register routes, run in three lines | you host a backend: docker/kubernetes deployment with the whole feature set |
| **Contents** | request parser + response builders + connection loop (deadlines + keep-alive A/B) + router + envelope + a `minimal.xi` example | the core **plus** the product extras: sessions, metrics, store (jsonl/kv), static/site mode, multipart, JWT/CSRF/CORS, rate limiting, OpenAPI, audit/access logs, game control plane, release machinery |
| **Dependencies** | `xiom.std` only; extras compose as the separate registry packages (`xiom.session`, `xiom.static`, `xiom.kv`, `xiom.rate`, `xiom.metrics`, `xiom.http.middleware`, `xiom.sqlite`) | the pinned package family + the same Beacon core |
| **Hardening** | full -- the light path is never the unsafe path: TE/CL smuggling rules, chunked decoding, 100-continue, header/body caps, deadlines, keep-alive | same core, same guarantees |

Station consumes the same `xiom.pulse` package Beacon publishes, so
protocol fixes land once and reach every user.

**Status:** the core's connection semantics are frozen at the keep-alive
A+B pair (`56eb9f8`; smoke 134/134 x2 both platforms); the `xiom.pulse`
extraction (Beacon, v0.1.0) is **in flight** in the packages lane (porter
carving the frozen pair into `packages/xiom-pulse`; bus
`REL-20261016-1429-packages`). Until it publishes, Station carries the core
in-tree.

## Toolchain (latest-tracking, owner decision 2026-10-05)

PULSE tracks the **latest** compiler / stdlib / packages to harden the
ecosystem through real use; public release comes later. Exact versions and
lane hashes are recorded in `SESSION.md` at every wrap.

| Component | Current |
|---|---|
| Compiler | **v0.64.8** (versioned install; `dev-env` prefers it over the v0.64.7/unversioned fallbacks) |
| Stdlib | pin **`112c5b6`** (tag `stdlib-v0.64.8`; extracted release tag) |
| Packages | registry (`%LOCALAPPDATA%\xiom\packages`): the 11 deps -- xiom.pulse 0.2.1, xiom.http 0.1.8, xiom.cookie 0.1.2, xiom.jwt 0.2.1, xiom.router 0.1.0, xiom.rate 0.2.0, xiom.metrics 0.2.0, xiom.http.middleware 0.1.0, xiom.session 0.1.0, xiom.static 0.1.0, xiom.kv 0.1.0 |

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
. .\scripts\dev-env.ps1          # sets XIOM_COMPILER / XIOM_STDLIB (XIOM_RUNTIME_DIR retired)
.\scripts\run.ps1 tests\test_smoke.xi
```

- `SESSION.md` -- live state, pin, open blockers, findings rows (upstream relay).
- `docs/PROGRESS.md` -- **weighted production-grade tracker** (what works, what is pending, % done).
- `docs/ROADMAP-TOP-TIER.md` -- the top-tier goal map: acceptance criteria T1-T9, the two editions (Beacon/Station), workstreams.
- `docs/DEPLOYMENT.md` -- proxy-first TLS deployment (Caddy/nginx, env, supervision).
- `docs/repro/` -- minimal upstream repro bundles.
- `src/` -- the service; `tests/` -- suites and probes.

## Design constraints (from the pinned toolchain)

- No real OS threads (`xiom.thread.spawn` is an inline simulation); the
  service accepts connections sequentially until the runtime grows real
  threads (worker supervisor is roadmap W1).
- Connection deadlines + keep-alive landed (2026-10-16): per-request read
  deadlines (`408` from idle), non-blocking poll-gated sends (stalled
  readers dropped), HTTP/1.1 reuse with in-order pipelining, silent idle
  expiry; `PULSE_KEEPALIVE=0` restores close-per-request
  (`docs/DESIGN-KEEPALIVE-DEADLINES.md`).
- TLS is terminated by the front proxy; in-XIOM TLS is not on the critical
  path.
- Slow clients are shed by the deadlines; incomplete framing always closes
  without an answer (h11-adopted reuse rules: comma-token
  `Connection: close`, HTTP/1.0 never reuses).
