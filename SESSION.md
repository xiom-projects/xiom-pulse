# XIOM PULSE -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-05 (17:3xZ), by the PULSE consumer lane.

## 0. STATE (2026-10-05 17:3xZ)

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
- **Last green slice:** **M4 hardening wave 4** on v0.64.0: store
  compaction (temp file + `MoveFileEx` replace; drops torn lines), events
  `?limit=` query, request ids in every error envelope, `io.rename`
  semantics verified (`MOVEFILE_REPLACE_EXISTING`). Suites x2 (`test_app`
  90 checks), smoke **56/56** on `out\pulse_app_v8.exe`. New stdlib
  wishlist row: no `fsync`/`FlushFileBuffers` anywhere in the runtime ->
  "durable" appends are write-back only.
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

## 3. Paste prompt for the next PULSE session

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (official XIOM
full web backend). Read SESSION.md first, then the reference docs listed in
it. Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; do not push to origin without
owner approval. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits.

VERSION POLICY (owner 2026-10-05): track the LATEST compiler/stdlib/packages
to harden the ecosystem; no fixed pin. Current: compiler v0.64.0
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe), stdlib E:\xiom-lang\stdlib (lane
checkout), registry packages (xiom.http 0.1.1, xiom.cookie 0.1.1,
xiom.jwt 0.2.0). XIOM_RUNTIME_DIR is RETIRED. Dot-source
scripts\dev-env.ps1. Registry consumption needs xiom.toml source-roots
(C-PULSE-02, still open on v0.64.0).

First: read probe-logs\soak-http.summary.txt (v0.64.0 30m soak, started
17:3xZ; if absent/incomplete, re-run scripts\soak_http.ps1 with the
watchdog) and confirm the verdict; record it in SESSION.md.

Step 2 is DONE and on v0.64.0 green; Step 3 storage core is DONE (JSONL
store + events routes + crash/reopen 6/6 at 20 and 200 events). Next:
Step 3 handoff wrap, then Step 4 (TLS decision: proxy-only unless the
product needs in-XIOM TLS; keep the proxy fallback documented). Keep the
workarounds: no bare &mut Int reads (*p), no const-receiver `.to_str()`
(use convert.int_to_string), probes staged in-repo, suite x2, server
output redirected to files (never undrained pipes). Keep the three relay
documents updated at every wrap: docs\COMPILER-FINDINGS-PULSE.md,
docs\STDLIB-WISHLIST-PULSE.md, docs\PACKAGE-WISHLIST-PULSE.md. Batch
findings rows in SESSION.md at the wrap and commit.
```
