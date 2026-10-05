# XIOM PULSE -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-05 (12:55Z), by the PULSE consumer lane.

## 0. STATE (2026-10-05 12:55Z)

- **Repo:** `E:\xiom-projects\xiom-pulse`; identity `Lefteris Notas
  <lefterisnotas@gmail.com>`; repo stays **PRIVATE**; `origin` exists
  (github.com/xiom-projects/xiom-pulse) but is **not pushed without owner
  approval**.
- **PINNED TOOLCHAIN (do not upgrade without the owner):**
  - `XIOM_COMPILER    = %LOCALAPPDATA%\xiom.new\bin\xiom.exe` (v0.63.1)
  - `XIOM_STDLIB      = E:\xiom-lang\stdlib`
  - `XIOM_RUNTIME_DIR = E:\xiom-lang\stdlib\runtime` **REQUIRED** -- the
    installed AOT link never scans `<install>\lib\runtime`; without the
    override any closure using `xiom_async_now_ms` fails
    `lld-link: undefined symbol: xiom_async_now_ms` (upstream packet
    xiom-packages `5b7547b0`, `docs/repro/runtime-link/`). Also links
    `sha256_sw.c` -> the `xiom_sha256_hash` crypto-link experiment.
  - `scripts\dev-env.ps1` sets all three; dot-source it in every terminal.
    PATH shadow warning: a v0.62.3 staging dir shadows `xiom.new` in PATH.
- **Read-only lanes (record hashes, never edit):**
  - stdlib   `15cb889` 2026-10-05T14:03:35+03:00
  - compiler `586426e9` 2026-10-05T15:32:11+03:00
  - packages `3f21385c` 2026-10-05T15:47:13+03:00
- **Last green slice:** **Step 3 storage core live**: JSONL event store
  (`src/store.xi`) with schema record, torn-line tolerance and
  newline-healing appends; events routes `POST /api/events`,
  `GET /api/events`, `GET /api/events/count`; smoke 37/37; crash/reopen
  6/6 at 20 and 200 events; suite 57/57 x2. New finding **C-PULSE-05**
  filed (W005 const-receiver `.to_str()` stub wrote invalid JSON;
  workaround `convert.int_to_string`). Soaks (PS + WSL) running on the
  Step 1 binary against :18080.
- **Open blockers:** C-PULSE-01 (read method) worked around via raw
  socket_recv; C-PULSE-02 (dep->root mapping) worked around via xiom.toml
  source-roots; C-PULSE-04 (&mut Int bare read) documented; C-PULSE-05
  (const `.to_str()` W005 stub) worked around; `xiom.http` v0.1.0 parser
  broken (package defect filed).
- **Next action:** soak verdicts (wakeup scheduled 16:21Z: PS 30m soak +
  WSL 30m client cross-check). Then Step 3 wrap: a store soak (many events,
  reopen size check) and the Storage section handoff; then Step 4 (TLS via
  proxy only if needed).

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
| 1h soak (memory/fd stability) | RUNNING (started 2026-10-05 ~15:2xZ) | persistent bg process `bgp_10c9c56c40017FshZrk76eKzkH` on :18080 (session persistent); progress `probe-logs\soak-http-progress.txt` (60s samples), summary `probe-logs\soak-http.summary.txt` |
| Registry package consumption | DONE (xiom.http with workaround; cookie/jwt green) | `xiom pkg install xiom.http@0.1.0` (sha256 f8b59d9e...), `xiom.cookie@0.1.1` (sha256 6259e3b3...), `xiom.jwt@0.1.1` (sha256 408643ce...), all signature-checked; `probe_pkg_step2.xi` 8/8 x2 (cookie jar parse/get/serialize-set; jwt shape/alg/sub/exp); `probe_pkg_http.xi` exposes the xiom.http parser defect |
| WSL cross-boundary client check | DONE (green) | Ubuntu WSL: `curl http://172.26.112.1:18080/health` -> `{"status":"ok"}`; note: WSL `localhost:8080` hits the Docker Desktop container on this machine, not PULSE |

**Environment note (port contention):** on this machine `0.0.0.0:8080` is held by
`com.docker.backend` (Docker Desktop publishes the "XIOM Benchmark Chaos"
app; also reachable as WSL `localhost:8080`). The v0.63.1 Windows
`xiom_socket_bind` (no `SO_REUSEADDR`) still bound `127.0.0.1:8080`
alongside it, but for clean evidence PULSE gained a `PULSE_PORT` env
override (`src/server.xi` `server_port()`, default 8080) and the soak runs
on 18080.

**Soak sample (60s, healthy):** `ok=119 fail=0 ws=8,167,424 handles=110`
(baseline ws=8,208,384 handles=110).

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
- `docs/COMPILER-FINDINGS-PULSE.md` -> compiler lane (C-PULSE-01/02/04 +
  test-gap notes + exact repro commands).
- `docs/STDLIB-WISHLIST-PULSE.md` -> stdlib lane (socket options/timeouts,
  server-side request parser, str_bytes, write_all, flush_stdout, harness).
- `docs/PACKAGE-WISHLIST-PULSE.md` -> packages lane (xiom.http defect,
  proposed router/session/jwt-hs256/ratelimit/metrics/static/middleware).

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
- crypto-link `xiom_sha256_hash`: **RESOLVED via `XIOM_RUNTIME_DIR`** (Step
  0d: KAT passes under the override; without it the old undefined symbol).
  Unblocks stdlib SHA-256/HMAC for JWT; relay to the packages lane to
  re-test/flip their `docs/repro/crypto-link` row.
- FFI-class packages (kafka, zstd, lzfse) are stubs; not planned.
- Pin discipline: initialize every local (`var x: T = <default>;`); `Vec[T]`
  brackets only (byte-level grep after writes); parenthesize bitwise+additive;
  unique fn names, `pub` for cross-module; probes staged in-repo (never
  `%TEMP%\kilo`); watchdog + exit-code gate on every run; suites x2.

## 3. Paste prompt for the next PULSE session

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (official XIOM
full web backend). Read SESSION.md first, then the reference docs listed in
it. Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; do not push to origin without
owner approval. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits.

Toolchain pin: XIOM_COMPILER=%LOCALAPPDATA%\xiom.new\bin\xiom.exe (v0.63.1),
XIOM_STDLIB=E:\xiom-lang\stdlib,
XIOM_RUNTIME_DIR=E:\xiom-lang\stdlib\runtime (REQUIRED workaround, see
SESSION.md). Dot-source scripts\dev-env.ps1. Registry packages now install
to %LOCALAPPDATA%\xiom\packages; consumption needs xiom.toml source-roots
(C-PULSE-02).

First: read probe-logs\soak-http.summary.txt (1h soak started 2026-10-05 on
:18080; if absent/incomplete, re-run scripts\soak_http.ps1 with the
watchdog and watchdog-gated exit code) and confirm the soak verdict. A
non-zero failure count or handle growth is a finding: file it in SESSION.md
with the progress file as evidence.

Step 2 is DONE (suite tests\test_app.xi 41/41 x2; smoke 31/31; 64/64
concurrent). Then Step 3 (storage): pick the most-tested option first,
schema/migrations, crash/reopen test, soak. Keep the workarounds: no
one-arg `read` methods (raw socket_recv), no bare &mut Int reads (*p),
probes staged in-repo, suite x2, server output redirected to files (never
undrained pipes). Keep the three relay documents updated at every wrap:
docs\COMPILER-FINDINGS-PULSE.md, docs\STDLIB-WISHLIST-PULSE.md,
docs\PACKAGE-WISHLIST-PULSE.md. Batch findings rows in SESSION.md at the
wrap and commit.
```
