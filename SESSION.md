# XIOM PULSE -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

## HANDOFF PROMPT (CURRENT -- 2026-10-22, session 24 close)

You are the PULSE lane for E:\xiom-projects\xiom-pulse (the official
XIOM web backend / multipurpose framework). This session closed near the
context limit. Read this prompt first, then SESSION.md's WRAP 24
correction/digest, docs\PROGRESS.md, docs\PRODUCTION-REFERENCES.md,
docs\PRODUCTION-GAPS.md, docs\ROADMAP-TOP-TIER.md and the unit design
docs. Relays: E:\xiom-lang\xiom-relays. Reference shelf: E:\repos.

RE-ARM YOUR DOORBELL FIRST (crons are session-scoped): every 2h with the
standard sweep (git fetch + merge --ff-only, NEVER `git pull`; view --lane
pulse; process items; wrap on change). Then continue the queue.

STATE AT WRAP 24 (2026-10-22, session 24):
- `main = cdcdca8` (clean + pushed; this handoff commit follows).
- **Compiler: v0.64.8 production.** v0.64.9 is **WITHDRAWN**
  (`REL-20261022-1826-compiler`: nested enum patterns + 1451/1550
  release-mode defects; production stays v0.64.8). **v0.65.0 production
  gate is open** (P0 correctness -> hardening -> MCU; no candidate/tag
  before the gate is green + owner GO). **Do not adopt v0.64.9.**
- **Stdlib: v0.64.9 `aa8b656` kept** (pins compiler v0.64.8; carries the
  macOS `list_dir` fix + JSON/YAML/TOML/CSV byte builders). v0.65.0 will
  pin stdlib-v0.65.0. Local Windows `%LOCALAPPDATA%\xiom.new-v0.64.8` +
  `xiom-pins\stdlib-tag-v0.64.9`; WSL `~/.local/share/xiom-v0648` +
  `~/.cache/xiom-pin/stdlib-tag-v0.64.9`; `dev-env` prefers v0.64.8.
- **User StreamHandler registry: reverted** (`5a927d3`); patch kept at
  `29dbd25` (`register_handler`/`dispatch` + `Vec[StreamHandler]`).
  Restore it only on the v0.65.0 production pin, then re-run
  `probe_fnptr` + `probe_stream_handler` and stream smoke. The built-in
  SSE/WS registry is live.
- **macOS x64 gating and green** (stdlib `list_dir` fix); **macOS arm64
  and 22.04 arm64 non-gating** on `REL-20261021-0717-pulse` /
  `REL-20261022-1529-pulse`; the gating linux-arm64 leg uses
  ubuntu-24.04.
- **CI `39815111372` green** on linux-x64, linux-arm64 (24.04),
  windows-x64, macOS x64. **Release dry-run `39816871164` green** on
  linux-x64, linux-arm64, windows-x64. (`39809053080` was on the
  withdrawn v0.64.9 archive; ignore for adoption.)
- Gates on v0.64.8 + stdlib v0.64.9: suites x2 (95/239/4), smoke
  135/135 x2 (jsonl+kv), crash x2, migrations 21/21, SQL 53/53, stream
  57/57 + live 20/20, rate smoke; green locally and in CI.
- **JSON/bench:** stdlib v0.64.9 builders + parse/stringify are clean at
  2k/512MB; legacy `json_set` still retains; bttger `/insert` over HTTP
  hit 2GB after ~1,042 POSTs while the standalone insert-shaped loop
  (`probe_json_get_leak`) is flat -> the remaining growth is the HTTP
  POST/request path (m375/PULSE). **Linux/1M bench stays blocked; never
  run uncapped.**
- **Release 0.3.0:** SQL serving surface decision proposed in
  `docs/DESIGN-SQL-SERVING.md` (opt-in app library; stock `pulse_app`
  SQL-free). Owner approval is the only gate; then bump
  `src/version.xi` + `APP_VERSION` + `package.xi`, CHANGELOG, tag
  `pulse-v*`, watch the fleet, ping ops.
- **Memory cap:** every manual/long app run uses
  `scripts\capped_app.ps1` / `scripts\capped_app.sh` (default 2048 MB,
  `PULSE_MAX_RSS_MB`; exit 137). CI runners are isolated; short smokes
  are bounded. Never run the 1M bench uncapped.
- **Engine incident (2026-10-22):** many `C:\Users\lefte` config dirs
  were deleted; PULSE workspace/toolchain/stdlib pins are intact.
  Re-authenticate any deleted tool configs; no PULSE recovery action.

NEXT (dependency order):
1. **v0.65.0 -- ADOPTED 2026-10-24 (see the update below):** compiler
   v0.65.0 + stdlib `3eb9c05`, StreamHandler registry restored, CI legs
   flipped to ubuntu-22.04-arm + gating macOS; remaining: the CI run and
   release dry-run verdict.
2. **HTTP request-path retention -- INVESTIGATED (session 25, below):**
   compiler-owned per-request leak on v0.64.8 + stdlib v0.64.9 (product
   `GET /health` 55-60 KB/req; bttger `/serialize/big` 1.14 MB/req).
   Bus: `REL-20261010-1549-pulse-4` (compiler, v0.65.0 P0),
   `REL-20261020-1704-pulse` (stdlib reference APIs), new
   `REL-20261022-2049-pulse` (`socket_recv_into`). Do not re-isolate;
   wait for a pin/fix, then re-run `scripts/post_retention_probe.ps1`
   and only then the capped bttger 5k/1M.
3. **Release 0.3.0** after owner approval (SQL serving decision proposed).
4. Remaining realtime: **stream auth LANDED** (session 26:
   `PULSE_WS_AUTH=off|jwt|session`, see below); permessage-deflate and
   subprotocol negotiation remain; Phase B stays blocked on m371.

OPEN RELAYS: `REL-20261021-0717-pulse` and `REL-20261022-1529-pulse` are
v0.65.0 acceptance input; `REL-20261020-1704-pulse` acked (builders in,
m375 residual); `REL-20261021-0918-pulse` verified; `REL-20261021-1703`
verified on the withdrawn archive; no open PULSE ops items.

DISCIPLINE: latest is **not** v0.64.9 (withdrawn); production v0.64.8
until the v0.65.0 gate is green + owner GO. Signed conventional commits;
commit/push per unit; update SESSION + docs/PROGRESS at every wrap;
report blockers on the relay first.

**2026-10-24 UPDATE -- v0.65.0 ADOPTED (supersedes the state block above):**
production is now compiler **v0.65.0** (windows archive `ff4abb4a...`,
checksum-verified; `%LOCALAPPDATA%\xiom.new-v0.65.0`) + stdlib **v0.65.0**
(`3eb9c05`; `xiom-pins\stdlib-tag-v0.65.0`). v0.64.9 stays withdrawn;
v0.64.8 is superseded. CI/heavy/release pin v0.65.0 with the five archive
SHA256s; linux-arm64 runs on **ubuntu-22.04-arm** and `macos-14` are
**witness-only** until `REL-20261024-1101-pulse` (two arm64 codegen
defects) clears; macOS **x64** packaging is enabled. `dev-env`
now resolves from the **lane-local** `%LOCALAPPDATA%\xiom-pulse-home` (the
shared package store was clobbered again by a fleet repin) and
`build.ps1`/`run.ps1` always source it. The user **StreamHandler registry
is restored** on this pin. Windows fleet green; retention re-measured and
still red (~60 KB/req floor).

**2026-10-22 (session 25 -- HTTP request-path retention isolated):**
The remaining growth is **per request** and **compiler-owned**; it is not
a bttger/JSON artifact and it is not fixed by the stdlib-v0.64.9 pins.
On v0.64.8 + stdlib tag `aa8b656` (Windows x64): the product `pulse_app`
`GET /health` retains **55-60 KB/request** (connection-per-request and
one keep-alive connection alike); bttger retains 39 KB (tiny GET), 36.6
KB (`/serialize`), 55 KB (404), 71-96 KB (`/insert` 2 B-163 B), 303 KB
(4 KB body) and **1.14 MB** (`/serialize/big`). One keep-alive 400-POST
run has the same 89 KB/req slope, so the earlier "standalone loop flat /
HTTP residual" reading was a measurement artifact. Standalone bisect
(`tests/probes/probe_alloc_aggregate.xi`, peak RSS): `Vec[Int]` 139 B,
`Map[Str,Int]` 289 B, `Str` concat 47 B per iteration, but a one-field
JSON build+stringify **2,152 B**, a trivial `json_type` on the same
value **1,885 B**, `json_get` 1,959 B and `json_parse("{\"a\":1}")`
2,267 B -> by-value `JsonValue` Map/Vec copies amplify the compiler's
missing-drop-glue class (m375); the HTTP floor is the per-read 64 KiB
`socket_recv` Vec. Harness `scripts/post_retention_probe.ps1`; evidence
`probe-logs/post-retention-20261022.log`. Bus: compiler
`REL-20261010-1549-pulse-4` updated with the v0.65.0 P0 ask + acceptance;
stdlib `REL-20261020-1704-pulse` corrected (the "2k clean" note is a
242 MB peak, not flat) with a `&JsonValue` reference-API ask; new
`REL-20261022-2049-pulse` asks for `socket_recv_into` /
`socket_recv_timeout_into` so the server can reuse one read buffer.
**0.3.0 consequence:** on this pin the stock server leaks ~5.5 MB/s at
100 rps; `docs/RELEASE-CHECKLIST.md` now records a sustained-load gate
and the owner decision (wait for the compile fix + recv-into, or ship
with a documented restart/RSS-cap policy). Environment: the local
Windows package store (`%LOCALAPPDATA%\xiom\packages`) was empty after
the engine incident; all 12 manifest deps were reinstalled at the pinned
versions and `pulse_app` rebuilds green.

**2026-10-23 (session 26 -- stream authentication landed):**
`PULSE_WS_AUTH=off|jwt|session` is now enforced for `/api/sse`, `/api/ws`
and every registered stream route, after the protocol checks + Origin
guard and before the 101 / first SSE chunk. JWT (HS256) accepts the token
via `Authorization: Bearer`, the browser `Sec-WebSocket-Protocol:
pulse.jwt.<jwt>` carrier, or `?token=`/`?access_token=` (EventSource);
`session` mode requires a live `sid` cookie. Rejection is 401 with
`WWW-Authenticate: Bearer` (jwt mode); unknown `PULSE_WS_AUTH` values and a
missing `PULSE_JWT_SECRET` fail closed (the dev default is refused).
Query-string credentials are redacted in the access log and audit file.
New `src/wsauth.xi` (`xiom.pulse.station.wsauth`), wired in `src/server.xi`;
config validation + `--check-config` print `ws_auth`. Gates:
`tests/test_stream.xi` **78/78** (21 new), live
`scripts/ws_auth_smoke.ps1` **11/11** (401/101/SSE + log redaction),
`stream_smoke` 20/20, suites x1 green (95/239/4). Two v0.64.8
catalog-body inference holes surfaced and were worked around with typed
`let` bindings (tuple-returned `Vec[Str]` element; cross-module `Str` used
as a session key) -- relay filed. Remaining realtime: permessage-deflate +
subprotocol negotiation. **CI `40007323461` GREEN** on linux-x64,
linux-arm64 (24.04), windows-x64 and macOS x64; `macos-14` (arm64) is red
on the known non-gating compiler defect (`REL-20261021-0717-pulse` /
`REL-20261022-1529-pulse`).

**2026-10-24 (session 27 -- v0.65.0 adopted; registry restored):**
Toolchain v0.65.0 (`ff4abb4a...` windows; 11 assets + SHA256SUMS verified)
+ stdlib `3eb9c05` installed; `STDLIB_VERSION` updated; CI/heavy/release
re-pinned; linux-arm64 -> `ubuntu-22.04-arm`; macOS **x64** packaging
enabled. **arm64 is not yet buildable on this pair** (`REL-20261024-1101-pulse`):
(1) stdlib `io.print` emits a fixed-arity `printf` call rejected by
opt/clang on arm64 -- worked around PULSE-side (`print_block`, commit
`24c4354`); (2) the contract evaluator emits `load i64, i64* %p` where
`%p` is `i8**` for `Result[Str, IOError]` (stdlib `io.xi:244`). Both arm64
legs are therefore non-gating witnesses and `macos-arm64` packaging is
held; `0717`/`1529` cannot be verified until the product builds there.
Acceptance on Windows v0.65.0: `probe_arm64_ginit`
compiles, `probe_fnptr` and `probe_stream_handler` both
`var=4,7 vec=4,7`, `p_io_listdir_roundtrip` green, migrations 21/21.
Registry restored: `register_handler`/`dispatch` + `Vec[StreamHandler]`;
built-ins register through the same table (`stream.xi`, `stream_dispatch`
in `server.xi`); `test_stream` **83/83** (5 new), stream smoke 20/20,
ws-auth 11/11. Fleet: suites x2 (95/239/4), smoke **135/135 x2**
(jsonl+kv), crash 6/6 x2, SQL 53/53, rate smoke. **Retention on v0.65.0:**
product `GET /health` 60.6 KB/req; bttger `/serialize` 37 KB, `/insert`
79.6 KB, `/serialize/big` **225 KB/req** (5x better than v0.64.8's
1.14 MB); standalone obj 2,140 B / type 1,937 B / map 289 B / vec 145 B /
str 49 B -- the drop-glue class is still open, so the 0.3.0 sustained-load
gate remains. The shared package store was clobbered again by a fleet
repin; this lane now resolves from `%LOCALAPPDATA%\xiom-pulse-home`.

**WRAP 24 CORRECTION (2026-10-22T19:05Z):** the v0.64.9 **compiler is
WITHDRAWN** (`REL-20261022-1826-compiler`: nested enum patterns and the
1451/1550 family fail in release mode; production stays v0.64.8;
**v0.65.0 gate opened, no rush**). It was first held per
`REL-20261022-1501-orbitdb`. PULSE reverted compiler pins to
**v0.64.8** and dev-env preference; **stdlib-v0.64.9 (`aa8b656`) is kept**
(unaffected, pins compiler v0.64.8). The user StreamHandler registry
(`29dbd25`) was **reverted** (`5a927d3`); it returns from git history with
a fixed archive. macOS x64 remains gating with the stdlib `list_dir` fix;
macOS arm64 and 22.04 stay blocked on 0717/1529. Local gates on v0.64.8 +
stdlib-v0.64.9: suites x2, smoke 135/135 x2, crash x2, migrations 21/21,
SQL 53/53, stream 57/57 + live 20/20, rate. **CI `39815111372` GREEN on
linux-x64, linux-arm64 (24.04), windows-x64 and macOS x64**; release
dry-run **`39816871164` GREEN on linux-x64/linux-arm64/windows-x64**.
`main = 2b350a7` at wrap start (this wrap commit follows). The WRAP 24
paragraph below is superseded on the compiler/registry claims.

**WRAP 24 (2026-10-22, session 24):** **XIOM v0.64.9 + stdlib-v0.64.9 ADOPTED** (compiler `v0.64.9` / `ffde5aa`; stdlib tag `aa8b656`, pin in `STDLIB_VERSION`; SHA256 pins in ci/heavy/release; local Windows `%LOCALAPPDATA%\xiom.new-v0.64.9` and WSL `~/.local/share/xiom-v0649` + stdlib tag dirs). **USER STREAM HANDLERS LANDED:** `StreamHandler = fn(Int, &Vec[UInt8], &PulseRequest) -> (Int, Int)` in `Vec`, `register_handler`/`dispatch`; built-in SSE/WS use the same table; `probe_fnptr`/`probe_stream_handler` green. **CI `39805179815` GREEN on linux-x64, linux-arm64 (ubuntu-24.04), windows-x64 and macOS x64** (macOS x64 now gating; full SQL/migrations/stream/suites/smoke). Full local gates on v0.64.9 Windows + WSL: suites x2 (95/239/4), smoke 135/135 x2, crash x2, migrations 21/21, SQL 53/53, stream 57/57 + live 20/20, rate smoke. **New blocker:** `REL-20261022-1529-pulse` -- stored-fn thunks emit `ptrtoint ptr @__unsafe_block_N`; clang 14 / Apple arm64 reject, so `ubuntu-22.04-arm` and macOS arm64 stay non-gating (24.04 arm64 gating). **JSON test-back:** v0.64.9 builders + parse/stringify are clean at 2k/512MB; legacy `json_set` still retains; bttger `/insert` over HTTP hit 2GB after ~1,042 POSTs while the standalone insert-shaped loop is flat -> the remaining growth is the HTTP POST/request path (m375/PULSE), so the Linux/1M bench stays blocked. **Release dry-run `39809053080` GREEN on linux-x64, linux-arm64 and windows-x64** (full fleet + packaging + provenance). `main = b46ba13` at wrap start (this wrap commit follows). Next: REL-1529 fix (22.04/macOS arm64), HTTP POST retention investigation, then 0.3.0 (owner approval). Doorbell armed.

**WRAP 23 (2026-10-20, session 23):** SSE + WebSocket units landed (`src/stream.xi`: chunked `/api/sse` + RFC 6455 `/api/ws`; same-origin/CORS Origin policy; fragmented-message reassembly; startup stream registry + per-route rate; 57/57 pure + 20/20 live on Windows + WSL, both smoke wrappers under the 2 GB RSS cap); CI `39427518984` (stream) + `39482651468` (Origin) green both; `main = 28abfb1` (SSE/WS + Origin + fragmentation + startup registry + per-route rate + workstation RSS cap + linux-arm64 CI + linux-arm64 release dry-run + non-gating macOS witness; this wrap commit follows; CI `39575983499` overall success, release dry-run `39588855890` green on linux-x64/linux-arm64/windows-x64, and macOS x64 green with stdlib `05673f8` in CI `39624153094`). Full gates: suites x2 (95/239/4), smoke 135/135 x2 (jsonl+kv), crash x2 on all three platforms; migrations 21/21, SQL 53/53, stream 57/57 + live 20/20 on both Linux legs; v0.64.8 + stdlib `112c5b6`. Owner memory cap (2026-10-20): `scripts/capped_app.*` default 2 GB RSS; use for every manual/long run. Next: Phase B blocked on compiler m371; Release 0.3.0 (needs the serving SQL surface decision plus jobs/Phase B completeness); platform macOS release legs (x64 green with stdlib 05673f8 pre-pin; arm64 waits on tagged compiler 0717); bench Linux/1M + xlcaptain; realtime follow-ups (user stream handlers, WS auth; Origin + fragmentation + startup registry landed). **BLOCKER (2026-10-21):** stdlib JSON path leaks under repeated build/parse/stringify; the capped Linux bttger leg hit the 2 GB cap after 1,624 `/serialize/big` requests, the builder probe hit 531 MB at ~500 iterations, the parse/stringify probe hit 528 MB at ~1,100 iterations, and the bisect shows parse-only and stringify-only each retain while 2M plain `Str` concats complete under 256 MB (same profile on Windows x64 and WSL). The locus is `JsonValue` node/aggregate lifecycle (`REL-20261020-1704-pulse`). Filed **`REL-20261020-1704-pulse`** (pulse -> stdlib, high); Linux leg + 1M bench are blocked. **Test-back (2026-10-21):** stdlib acked with in-place builders (526fd96); on stdlib main 0bf5984 the builder probe completes 500 iterations and crosses 512 MB at ~1,000-1,200 (vs ~500 for `json_set`), residual m375; not in the pin. Compiler fixed m0717 (aecad8c6c); local debug IR verified. The macOS x64 witness now passes with stdlib **05673f8** (pre-pin): `p_io_listdir_roundtrip` rc 0, migrations 21/21, SQL 53/53, stream/suites/smoke; **`REL-20261021-0918-pulse` is verified**. The fix is on stdlib main, not the pin. The Windows print-probe garbage is the separate known compiler 1609 inline `Result.value[i]` concat. arm64 still waits on a tagged compiler with 0717. Doorbell armed.

**SESSION 23 (2026-10-20 -- SSE + WebSocket, W4):** **REALTIME UNITS LANDED.** `src/stream.xi` (`xiom.pulse.station.stream`) takes over the accepted fd after the frozen gate. `GET /api/sse` streams chunked `text/event-stream` ticks (events/interval clamps, CORS, no `Content-Length`, zero chunk) and `GET /api/ws` performs the RFC 6455 101 handshake plus a masked echo frame loop (text/binary echo, ping/pong, close, 1 MiB cap, 1002/1003/1009; plain GET -> 426). The loop records 200/101 through the shared `record_response` path and closes the fd once; the router/OpenAPI surface is unchanged. Tests: `tests/test_stream.xi` **57/57** (pure; includes the same-origin/CORS Origin policy and the startup stream registry) and `scripts/stream_smoke.*` **20/20** live on Windows + WSL (the wrappers launch the app under the 2 GB RSS cap). Fragmented data messages are reassembled with interleaved control frames; an unexpected continuation closes 1002. Stream routes are in a runtime registry (`init`/`register`; built-in SSE/WS kinds; `routes` CLI prints them) and per-route rate policy applies to their literal path. Design + fastapi/h11/fasthttp matrix: `docs/DESIGN-SSE-WEBSOCKET.md`. User-supplied stream handlers, permessage-deflate and WS authentication remain explicit follow-ups; the Origin guard, fragmentation and startup registry are landed. `main = c062a58`; **CI `39427518984` GREEN both platforms** (ubuntu 6m22s, windows 5m34s).

**2026-10-20 (session 23 -- WebSocket Origin policy):** browser handshakes are now same-origin by default: `Origin` must match `Host` (default ports normalized) or be in `PULSE_CORS_ORIGIN`, otherwise **403 before the 101**; Origin-less non-browser clients stay allowed. This is the same-origin guard, not authentication. `tests/test_stream.xi` 46/46 (9 new Origin checks) and `stream_smoke` 17/17 live (same-origin handshake + cross-origin 403) on both platforms; both smoke wrappers now launch the app under the 2 GB cap, and the smoke pins `PULSE_CORS_ORIGIN=""` so a prior `http_smoke` run cannot mask the check. `main = 5f39ae5` + harness fix `db5cf48`; **CI `39482651468` GREEN both platforms** (ubuntu 6m10s, windows 5m02s). The first run `39481818997` failed only in the harness (exec bit + inherited `PULSE_CORS_ORIGIN=*`), fixed in `db5cf48`.

**2026-10-20 (session 23 -- WebSocket fragmentation):** fragmented data messages are reassembled across continuation frames and echoed as one frame with the original opcode; control frames may interleave; an unexpected continuation or a new data frame mid-fragment closes 1002, and a message over 1 MiB closes 1009. `stream_smoke` **20/20** live on Windows + WSL (fragmented echo + orphan continuation close). Full gates green: suites x2 (95/239/4), smoke 135/135 x2 (jsonl+kv), crash x2, stream 46/46 + live 20/20. `main = 11683c4`; **CI `39498806648` GREEN both platforms** (ubuntu 5m15s, windows 4m45s).

**2026-10-21 (session 23 -- stream registry + per-route rate):** stream routes live in a startup registry (`init`/`register`; GET + built-in SSE/WS kinds; duplicates/invalid paths fail closed). The `routes` CLI prints them, and per-route rate policy applies to the registered literal path after the global bucket (`GET /api/sse=1/1` -> 200 then 429 live). `test_stream` **57/57** (registry/init/path/validation/routes text), live `stream_smoke` **20/20**. Full gates green both platforms: suites x2 (95/239/4), smoke 135/135 x2 (jsonl+kv), crash x2. `main = 005d03f`; **CI `39548433814` GREEN both platforms** (ubuntu 6m31s).

**2026-10-21 (session 23 -- linux-arm64 CI):** the matrix now has a native **ubuntu-24.04-arm** leg. `setup-xiom` selects the SHA256-pinned `xiom-0.64.8-linux-arm64` toolchain, installs clang if absent, and `file` verifies the ELF before the full SQL/migrations/stream/suite/smoke/crash gates run natively. The first attempt on `ubuntu-22.04-arm` failed on a **compiler codegen bug**: module-scope `Vec` initialization emits `load i8*, i8** %struct.Vec*` (invalid for LLVM/clang 14, tolerated by 18). Filed **`REL-20261021-0717-pulse`** (pulse -> compiler, high) with `tests/probes/probe_arm64_ginit.xi`; the 24.04 leg is green. `main = 8cf4992`; **CI `39560182609` GREEN on all three platforms** (arm64, linux-x64, windows-x64).

**2026-10-21 (session 23 -- macOS witness):** `macos-14` (arm64) and `macos-15-intel` (x64) were added to the matrix. The arm64 leg builds until the compiler's invalid module-scope Vec IR (`REL-20261021-0717-pulse`, same load as Linux clang 14); the x64 leg was red on `list_dir` (stdlib witness rc 3), and with stdlib **05673f8** checked out in the non-gating fix step it is now fully green: `p_io_listdir_roundtrip` rc 0, **migrations 21/21**, SQL 53/53, stream 57/57 + live 20/20, suites/smoke. `REL-20261021-0918-pulse` is **verified**; the fix is on stdlib main, not the v0.64.8 pin. The Windows print-probe garbage is the separate compiler 1609 inline concat. Both jobs are **non-gating** (`continue-on-error`); CI `39624153094` is overall success with x64 green and arm64 red on 0717. Release assets remain behind `RELEASE_BUILD_MACOS`; the next pins remove the pre-pin override and make x64 gating.

**2026-10-21 (session 23 -- release dry-run, linux-arm64):** the release matrix now includes `linux-arm64` on `ubuntu-24.04-arm`; `scripts/release.sh` auto-detects aarch64 and emits `pulse-<ver>-linux-arm64.zip` + `.sha256`. Dry-run **`39588855890` is green on linux-x64, linux-arm64 and windows-x64** with the full fleet (suites x2, smoke, rate, crash, kv soak), packaging, artifact upload and provenance. No public release was cut; the next tag ships three assets; macOS stays opt-in. `main = 388bdd5`.

**2026-10-21 (session 23 -- user stream handlers, blocked):** attempted a `StreamHandler` registry (function values stored in a module-level Vec) to complete dynamic stream routes. The pinned compiler infers calls through stored function values as `()` (`let b: Int = g(41)` -> T001 found `()`), and the Vec storage path emits invalid IR (`store i64 %fnptr, i64* ...` where the value is `ptr`). Reverted the attempt; the built-in SSE/WS registry remains. Filed **`REL-20261021-1703-pulse`** (pulse -> compiler, high) with `tests/probes/probe_fnptr.xi`; **verified on compiler main `c9b1f1009`** (local debug HEAD `badba26cd`): `probe_fnptr` rc 0 and the exact `StreamHandler` shape (`fn(Int, &Vec[UInt8], &PulseRequest) -> (Int, Int)`) prints `var=4,7` / `vec=4,7`. Registry restore waits for a tagged compiler.

**WRAP 22 (2026-10-19, session 22):** context-budget wrap after three units, `main = 9b97eb7` at wrap start (clean + pushed; this wrap commit follows). **SQL STORE/REPOSITORY LAYER LANDED:** `src/sql.xi` (`xiom.pulse.station.sql`) over xiom.sqlite 0.4.1 -- integer handles, mandatory value binding, identifier validation, JSON rows, repository CRUD + `limit+1` paging, transactions; `tests/test_sql.xi` 53/53 Windows + WSL; opt-in (serving binary still SQL-free); CI `39328272067` green both. **PER-ROUTE RATE POLICY LANDED (W6):** `PULSE_RATE_ROUTES` token buckets on top of the global bucket, matched by route template (HEAD as GET, `/v1` normalized); test_http 95/95, test_app 239/239, rate_smoke proves 200/429/refill both platforms; CI `39332690326` green both. **BENCH BASELINE PUBLISHED:** `benchmarks/bttger/` six-endpoint contract + adapted autocannon driver; Windows c1 clean -- 454.6/78.1/384.6/142.9/172.4/50.0 req/s, zero errors; c10 adds no throughput and times out the waiting connections (W1 sequential-accept ceiling); report + raw JSON committed; CI `39335266242` green both. Full gates: suites x2 (95/239/4), smoke 135/135 x2 (jsonl+kv), crash x2, migrations 21/21, SQL 53/53, rate smoke, on v0.64.8 + stdlib `112c5b6`. NEXT: SSE + WebSocket, then Phase B when m371 lands, 0.3.0, platform legs, Linux/1M bench follow-ups. Doorbell cancelled for the session boundary.

**WRAP 21 (2026-10-19 evening, session 21):** context-limit wrap. `main = db91d2c` at wrap start (clean + pushed; this wrap commit follows). **PULSE 0.2.2 RELEASED** (tag `pulse-v0.2.2`, `3b515c6`, 18:48Z; release run `39304832557` SUCCESS; linux/windows artifacts + SHA256SUMS) -- ops re-tested the dogfood switch and **CLOSED `REL-20261017-1141-ops` (0.2.2 accepted)**. **Toolchain: XIOM v0.64.8 + stdlib `112c5b6`** (Windows/WSL installs, STDLIB_VERSION + all workflow pins; CI `39302388330` green both). **Beacon `xiom.pulse` 0.3.1** adopted (HookCtx/fallback/HEAD/Server-token; CI `39257841267` green). **Middleware Phase A COMPLETE** (four named units: read / `gate_request` / `build_dispatch_response` / `after_response`; gate harness 11/11; CI `39139728140` green). **Phase B PARKED on compiler m371** (imported-struct identity/field access; explicitly deferred to the cycle after v0.64.8) -- the legacy loop stays; package seams are complete. **SQL class MVP COMPLETE:** xiom.sqlite 0.4.1 wired (vendored C source opt-in), `src/migrations.xi` + `pulse_migrate` with `status|up|down|backup|create`, tracking + single-row lock, stale takeover, per-migration transactions, up/down markers, UTC stubs, applied-but-missing policy (`--allow-missing-applied`), backup fence (VACUUM INTO + manifest, `PULSE_SQL_BACKUP_MANIFEST`, `--no-backup-check`), per-migration heartbeat; **21/21 migrations tests + CI gates green** (`39309185528`, `39312989971`, `39315752929`, `39317250142`, `39321436014`). Current gates: suites x2 (82/237/4), smoke 135/135 x2, crash x2, all CI green. **NEXT UNIT (pick one, in order): (1) SQL store-interface integration** (repository/query layer over the driver; the migrations tooling is ready), **(2) per-route rate policy** on the legacy loop, **(3) bench baseline** (bttger six endpoints; harness), **(4) SSE + WebSocket units**, **(5) Phase B when m371 lands**. Also queued: linux-arm64 CI leg + macOS release legs; a background heartbeat for a single very long migration; release 0.3.0 once the runtime SQL surface lands. Open relay obligations: compiler m371 (next cycle), registry 3.0 pilot gate ping when production-serving; no open PULSE ops items.

**2026-10-19 (session 22 -- SQL store layer):** **SQL STORE/REPOSITORY LAYER LANDED.** `src/sql.xi` (`xiom.pulse.station.sql`) is the opt-in runtime SQL surface over xiom.sqlite 0.4.1: integer connection handles, mandatory value binding (`p_text/p_int/p_real/p_null` through `prepare`/`bind_*`), validated identifiers, JSON row mapping (exact 64-bit ints, typed real/text/null; blobs documented out of v1), repository CRUD (`find/list/count/insert/update/delete`), `limit+1` `has_more` paging, and explicit transactions. `tests/test_sql.xi` **53/53 on Windows + WSL** (bindings, value/identifier injection rejection, CRUD, paging, rollback/commit, error codes); CI gains a Linux SQL gate; the build scripts pass the vendored amalgamation for the SQL module; the serving binary still does not import it (build green without the C source). Design + knex matrix: `docs/DESIGN-SQL-STORE.md`. Local gates on v0.64.8: build both platforms, suites x2 (82/237/4), smoke 135/135 x2 (jsonl+kv), crash x2, migrations 21/21, SQL 53/53. `main = 1fcd1a3`; **CI `39328272067` GREEN both platforms** (ubuntu 6m18s, windows 4m25s; SQL store gate passed).

**2026-10-19 (session 22 -- per-route rate policy, W6):** **PER-ROUTE RATE POLICY LANDED.** `PULSE_RATE_ROUTES` (`METHOD PATH=RATE[/BURST],...`; `*` method; PATH is a route template) adds token buckets on top of the global bucket, which always runs first. `gate_request` resolves the matched route after the global bucket (HEAD as GET, `/v1` normalized) and returns 429 + `Retry-After` through the shared response helper. Invalid entries are named by `cfg_validate`, `--check-config` and startup; `--help` + `docs/DEPLOYMENT.md` document the syntax. test_http **95/95** (13 new policy checks), test_app **239/239** (+2 config checks), `rate_smoke` proves the 200/429/refill path on Windows + WSL. Local gates: suites x2, smoke 135/135 x2 (jsonl+kv), crash x2, migrations 21/21, SQL 53/53. `main = cf42333`; **CI `39332690326` GREEN both platforms** (ubuntu 4m34s, windows 3m38s).

**2026-10-19 (session 22 -- bench baseline, bttger):** **BENCH BASELINE PUBLISHED.** `benchmarks/bttger/` implements the six-endpoint bttger contract on the Beacon core (serialize, serialize/big, plain/text, query, insert, calculate) and adapts the MIT autocannon driver (5,000 requests/endpoint, 50 for calculate, 5s warmup, 1 and 10 connections). Real Windows numbers: **single connection clean** -- 454.6 / 78.1 / 384.6 / 142.9 / 172.4 / 50.0 req/s (p99 3/18/3/8/7/7 ms, zero errors); **10 connections add no throughput and the waiting connections time out**, pinning the sequential-accept loop as the W1 scale-out ceiling (raw JSON + methodology/caveats in `benchmarks/bttger/REPORT.md`). The standard 1M-request run is a separate longer experiment; no cross-framework claims. `main = 9b97eb7`; **CI `39335266242` GREEN both platforms** (ubuntu 6m10s, windows 4m28s; benchmark-app build gate included).

**2026-10-19 (PULSE 0.2.2 RELEASED):** tag `pulse-v0.2.2` (commit `3b515c6`) published at 18:48Z -- release run `39304832557` SUCCESS. Assets: `pulse-0.2.2-linux-x64.zip` (sha `5a54e4f2...`), `pulse-0.2.2-windows-x64.zip` (sha `8bf06605...`), SHA256SUMS. Contents: the **ops site-mode duplicate-Content-Length fix**, Beacon `xiom.pulse` 0.3.1, XIOM v0.64.8 + stdlib `112c5b6`, middleware Phase A, 413 hardening. Ops asked to re-run the xiom-lang.org dogfood switch and verify/close `REL-20261017-1141-ops` (`REL-20261019-1849-pulse`) -- **ops CLOSED `-1141` after the retest: 0.2.2 accepted**. Phase B still parked on m371. **SQL class opened:** xiom.sqlite 0.4.1 wired into both manifests + the CI installer; the build scripts pass the vendored amalgamation only for sqlite-importing entries; `tests/probes/probe_sqlite.xi` is GREEN locally and a new CI Linux linkage gate; **CI `39309185528` GREEN both platforms with the sqlite probe passing**. **SQL migrations MVP landed:** `src/migrations.xi` (tracking + single-row lock, lexicographic discovery, `status`, batched `up`, per-migration transaction or `-- pulse: no-transaction`, stale-lock auto-break) and the standalone `pulse_migrate` binary (`src/migrate.xi`); `tests/test_migrations.xi` is GREEN locally (status/up/no-op/order/stale-lock) and a new CI Linux gate; **CI `39312989971` GREEN both platforms with the migrations gate passing**. **`down` + `create` landed:** files may use `-- pulse:up`/`-- pulse:down` markers; `down` reverses the latest batch in reverse order and `create` writes a UTC-stamped stub (12/12 migration tests GREEN; wall clock fixed to `timestamp_now`); **CI `39315752929` GREEN both platforms with the migrations gate passing**. **Applied-but-missing policy + heartbeat landed:** strict status/up refusal with the missing file list, `--allow-missing-applied` prints the skipped set and proceeds; the lock heartbeat refreshes after each applied migration (18/18 migration tests GREEN; **CI `39317250142` GREEN both platforms with the migrations gate**). **Backup fence landed:** `pulse_migrate backup [path]` (VACUUM INTO + manifest with db/created_at/size); `up` with pending work requires a covering manifest via `PULSE_SQL_BACKUP_MANIFEST` (or `--no-backup-check`), and a fresh backup is needed before each new batch (21/21 migration tests GREEN; **CI `39321436014` GREEN both platforms with the migrations gate**). Remaining: a background heartbeat for a single very long migration (`docs/DESIGN-SQL-MIGRATIONS.md`).

**2026-10-19 (v0.64.8 adoption):** **XIOM v0.64.8 + stdlib tag `112c5b6` ADOPTED** (latest directive): Windows `%LOCALAPPDATA%\xiom.new-v0.64.8`, WSL `~/.local/share/xiom-v0648`, stdlib tag extracted both sides; `STDLIB_VERSION` + ci/heavy/release pins updated with the v0.64.8 SHA set; `dev-env` prefers the new dirs (v0.64.7 fallbacks). The PC crash reset the Windows package home (`%LOCALAPPDATA%\xiom\packages` was empty); all 11 deps were reinstalled (xiom.pulse 0.3.1 + latest set). Gates on v0.64.8, BOTH platforms: build, gate-order 11/11, suites x2 (82/237/4), smoke **135/135 x2** (jsonl+kv), crash x2 GREEN; **CI `39302388330` GREEN both platforms** (windows 4m2s, ubuntu 4m33s). **m371 (imported-struct layout) is still deferred to the next compiler cycle, so Phase B stays parked on the legacy loop.** Doorbell armed.

**2026-10-18 (owner back; v0.64.7 adoption):** relays checked (no PULSE-addressed items beyond the compiler release note). **Compiler v0.64.7 + stdlib-v0.64.7 ADOPTED** (owner latest directive): locally on Windows (`%LOCALAPPDATA%\xiom.new-v0.64.7`) and WSL (`~/.local/share/xiom-v0647`), plus `STDLIB_VERSION` + all three workflow pin blocks (v0.64.7 SHA256 set). **Tag note:** `stdlib-v0.64.7` was re-cut today from `1271dd5` to `f4482b14` (release chore pinning the compiler assets); PULSE pins the current tag commit `f4482b14` and flagged the move to stdlib. **Gates on v0.64.7 both platforms: build green, suites x2 (77/237/4), smoke 135/135 x2 (jsonl+kv), crash x2, gate-order 11/11** -- evidence `probe-logs/adopt-v0647/` (local). Overnight CI `39070435788` (gate-request extraction) was GREEN on both platforms. Current unit: middleware stages 0-3 extracted; stages 4-6 next. Doorbell re-armed 2026-10-18. **CI `39136475037` on the v0.64.7 adoption is GREEN both platforms** (ubuntu 3m53s, windows 3m25s); test-backs filed: `REL-20261018-1432-pulse` (compiler) and `-2` (stdlib tag re-cut). **xiom.pulse 0.2.1 ADOPTED** (hook seam + Server-token seam + package 413): Server header now `xiom-pulse-station/0.2.1` (verified live), local CL guard removed; gates green both platforms; CI `39143531101` GREEN. **Phase B is UNBLOCKED** -- next unit is the full loop adoption onto `serve_with` + pre/after hooks (with the loop-level 408 caveat noted to packages). Test-back `REL-20261018-1606-pulse`. **xiom.pulse 0.3.0 adopted** -- `HookCtx` stateful seam resolves the Phase B blocker (`REL-20261018-1640-pulse`); CI `39146054576` GREEN both platforms. **Phase B route-table mirror landed** (`ed49782`): `register_core_routes()` copies `station.router.route_defs()` into the Beacon table before serving (product loop unchanged, smoke 135/135). Next: the stateful pre/after hook adapter + `serve_with_ctx` switch. **Token-bucket adapter landed** (`ratelimit.bucket_step`, tested in test_http 82/82) for the HookCtx int bag. **Wiring plan de-risked:** the package/product `HandlerOut` type seam must be unified first (prefer a type alias), then the handler adapter (HEAD trim verification), pre hook (CORS headers on pre_stop + CSRF + bucket), after hook (metrics/log/audit; duration excludes send), then `serve_with_ctx` with a temporary legacy-loop fallback. Details in `docs/DESIGN-MIDDLEWARE-JOBS.md` Phase B plan. **HandlerOut field-copy adapter landed** (`to_core_out`, test_http 85/85). **PAUSED 2026-10-19 05:00Z at the session context limit** (doorbell cancelled; no relay items pending). Resume: re-arm the doorbell, then implement `station_handler`, the stateful pre/after hooks, and flip `serve_with_ctx` behind the legacy fallback. **0.3.1 resolves both package gates** (`REL-20261019-1150-pulse`): `HookSet.fallback` for kind 0 and HEAD-as-GET with header-only send. **Phase B is now blocked compiler-side:** cross-module public struct identity/field access is broken on v0.64.7 (`co.status` -> `<error>`; `app.pre_stop` -> "expected HandlerOut, found app.HandlerOut"), so the pre/after hooks cannot be installed. Filed high as `REL-20261019-1309-pulse`; the legacy loop stays, 0.3.1 is pinned, and the product module is renamed `station.core` (no alias shadowing). test_http 82/82 (adapter checks removed), test_app 237/237, smoke 135/135; **CI `39257841267` GREEN both platforms** (ubuntu 4m6s, windows 3m51s). **Compiler v0.64.8 cut (REL-20261019-1432-compiler-2) explicitly defers m371 (PULSE imported-struct layout, 1309/2301) to the NEXT cycle -- PULSE keeps the loop workaround; Phase B stays parked.** v0.64.8 adoption waits for the compiler archive: the **stdlib-v0.64.8 tag is LIVE** (`112c5b6`, "candidate-v0.64.8-r2", 2026-10-19T16:55Z) but the v0.64.8 release assets are still 404 as of 17:00Z -- adopt on the release notice (m371 still NOT included; Phase B stays parked). Next unblocked queue choices: 0.2.2 cut (ops dogfood retest), SQL migrations runner, per-route rate policy, bench baseline.

**WRAP 20 (2026-10-17):** session 20. **STATION-CONSUMES 2a GREEN** -- product modules renamed to `xiom.pulse.station.*` (18 imports / 10 files), the four byte-identical core modules deleted (SHA256 re-verified), `src/version.xi` is now the product version source (release scripts + tag guard + test_smoke repointed), `"xiom.pulse" = "0.1.0"` declared in both manifests + the CI installer; **local gates on BOTH platforms: suites x2 (77/237/4 rc=0), smoke 134/134 x2 (jsonl + kv), crash x2 GREEN**, evidence `probe-logs/station-consumes-2a/` (local). **TOOLCHAIN: v0.64.6 + stdlib tag `8d95815`** adopted locally AND in `STDLIB_VERSION` + all three workflow pin blocks (v0.64.6 SHA256 set); **latest registry deps** (`xiom.http` 0.1.8, `xiom.cookie` 0.1.2, `xiom.jwt` 0.2.1) per owner directive 2026-10-17. **OPS BUG FIXED:** site-mode duplicate `Content-Length` (`REL-20261017-1141-ops`) -- static CL dropped, builder owns framing; live 200 + 304 each carry exactly one CL, suite locks it; ops to re-test the dogfood switch on the next cut. Harness hardening: write-stall smoke now reads the head before the stall clock (WSL drvfs flake gone), crash harness waits for the listener + tolerates the Windows taskkill race. Packages hook seam acked (`REL-20261017-1123-pulse-2`, impl dispatched) -- stage 2b stays gated. Open: compiler resolver answer (`REL-20261017-1123-pulse`), ops clobber flag (`-3`), 0.2.2 cut. **MIDDLEWARE PHASE A STARTED (same session):** `scripts/gate_order.py` pins the gate order (11 checks: CSRF-before-rate, OPTIONS bypass, quit-after-parse, 413-vs-400) and both smoke scripts run it (smoke now **135/135**); it found and fixed a plain-CL body-cap truncation (now **413 `payload_too_large`** before dispatch; package note `REL-20261017-1533-pulse`). Suites x2 + smoke 135/135 x2 + crash x2 green both platforms; CI dry run `39051902537` GREEN both platforms. **Stage 7 landed:** `after_response()` is the single send+metrics+log+audit site for every response path (eight duplicated tails removed, behavior unchanged; gates re-run green both platforms; CI `39062233020` green). **Middleware Phase A COMPLETE:** the ladder is four named units -- read (main loop), `gate_request()` (stages 0-3: parse/too-large/quit/OPTIONS/CSRF/rate, `GateResult`), `build_dispatch_response()` (4-6: dispatch/build/HEAD-trim/beforeSend headers+CORS), `after_response()` (7: send/metrics/log/audit). Gate harness + suites x2 + smoke 135/135 x2 + crash x2 green on v0.64.7 both platforms; **CI `39139728140` GREEN on both platforms** (ubuntu 4m12s, windows 3m15s). Next Phase B = per-route chain + package hook seam (gated on packages 0.2.0). **PAUSED 2026-10-17 evening (owner away for the night): CI `39070435788` dispatched on the checkpoint; doorbell cancelled; next session re-arms it and continues with the stages 4-6 extraction (dispatch/build/HEAD-trim/std-headers+CORS) in `docs/DESIGN-MIDDLEWARE-JOBS.md`.** NEXT = middleware chain (`docs/DESIGN-MIDDLEWARE-JOBS.md`), then 2b on the package publish. `main = 1b13922` (2a commit, pushed); **CI dry run `39035806578` GREEN on both platforms** (ubuntu 3m44s, windows 4m4s); this wrap commit follows.

**WRAP 19 (2026-10-17):** session 19 closed at context limit. `main = b70d681` (clean + pushed; relays `95c4981`). **Beacon `xiom.pulse` 0.1.0 PUBLISHED** (eco-v0.1.192, sha256 `53fcc56e..`) + acceptance stage 1 GREEN; **durability Phase A GREEN** (sweeps + crash x2 both platforms; CI `38947560303`); **reference-study protocol BINDING** (`docs/REFERENCE-STUDY-PROTOCOL.md`). **NEXT UNIT = rename-first station-consumes 2a** (`docs/DESIGN-STATION-CONSUMES.md`: `app`/`config`/`router` -> `xiom.pulse.station.*`, 18 imports / 10 files, delete the 4 verbatim modules, deps + CI installer, suites x2 + smoke x2 both platforms) then the middleware chain. Open obligations: compiler resolver answer (`REL-20261017-1123-pulse`), packages 0.2 hook seam (`-2`), ops clobber flag (`-3`); v0.64.6 adoption + darwin/pin suites queued (item 7). Doorbell must be re-armed by the next session.

**Written:** 2026-10-05; **last wrap:** 2026-10-17 wrap 19 (session-19 log inline below) (keep-alive **A+B landed** (`7924222`, `56eb9f8`) -- Beacon freeze gate GREEN, milestone `REL-20261016-1401-pulse` filed; packages delivered template 0.2.0 + ssl building + otel built + zstd real; NEXT = `xiom.pulse` (Beacon) extraction -> publish-ready item -> durability -> middleware/jobs -> SQL runner -> bench), by the PULSE consumer lane. **Session 19 (live):** doorbell re-armed (2h); sweep acks pushed (`70e342f` bus); roadmap fold `8a1f22e`; **Beacon extraction IN FLIGHT packages-side** (porter carving `56eb9f8` -> `packages/xiom-pulse`, `REL-20261016-1429-packages`; no PULSE action until their relays); **`xiom.template 0.2.0` consumer-verify 15/15 x2 both platforms** (item 1c; unit `docs/repro/template-verify/`; bus reply filed); README refreshed -- tier map (Beacon tier 1 / Station tier 2; convention `REL-20261016-1446-packages`) + current toolchain/connection facts. **17:00Z sweep:** `xiom.ssl 0.1.0` + `xiom.brotli 0.1.0` LIVE (eco-v0.1.189; TLS headline closed on the packages path), **Beacon extraction GREEN + co-verified** (`053cab87`; all PROVENANCE hashes match @`56eb9f8` from our side; no surface changes; publish path next); **17:35Z:** consumer-verify `xiom.ssl` 0.1.0 (**14/14 live x2 win** + 4/4 SKIP x2 wsl) and `xiom.brotli` 0.1.0 (**11/11 x2 both platforms**) GREEN -- bus reply `REL-20261016-1735-pulse`; **durability Phase A landed** (post-17:35Z): `store_append`/`audit_event` sync-before-ack (`PULSE_STORE_SYNC`/`PULSE_AUDIT_SYNC`, default on; `io.append_line_sync` on the pin), `--check-config` prints + disable warnings, claim table flipped (DESIGN-STORE-DURABILITY P5), test_app +11 checks; win sweep FAILED=0 (binary `262909947A..`) + crash harness x2; linux rebuilt on the right pin (stale `dd352f6` hardcode in the local runner fixed to `092dfa0c`) -> sweep FAILED=0 (binary `3ee23a1f..`) + crash harness x2; CI dry run `38947560303` green (both platforms); **Beacon PUBLISHED** (`xiom.pulse 0.1.0` LIVE, eco-v0.1.192, sha256 `53fcc56e..`) + acceptance stage 1 GREEN (installed artifact: suite **125/125 x2 both platforms**, `minimal.xi` live x2; `docs/repro/beacon-acceptance/`); stage 2 = Station-consumes + full fleet next; **21:00Z sweep:** compiler **v0.64.6 RELEASED** (2026-10-16T20:33Z; darwin stream + stdlib pin `b81430ba`) -- asks PULSE: darwin/pin suites on the new archive; adoption + macOS pair re-test queued as the next unit after stage 2. **PAUSED 2026-10-16T23:18Z (owner away until tomorrow):** doorbell cancelled -- resume = re-arm the doorbell (first action), then station-consumes stage 2 -> v0.64.6 adoption + darwin/pin suites -> middleware/jobs -> SQL runner -> bench.

## 0. STATE (2026-10-11 wrap 15) -- CURRENT STATE digest (supersedes the log below)

- **STANDING RULE (owner directive 2026-10-17): REFERENCE-STUDY
  PROTOCOL** -- never design from memory; study the cloned battle-tested
  MIT repos under `E:\repos`, crawl the actual mechanics, convert to
  XIOM, apply from the extracted matrix; blockers (stdlib/packages/BUG)
  go to the lanes on the relay and are tested back on the next
  release/publish. Full rule: `docs/REFERENCE-STUDY-PROTOCOL.md`.
  Production bar -- no MVP shortcuts.

- **Repo:** `E:\xiom-projects\xiom-pulse`, **PUBLIC** since 2026-10-09
  (owner flipped it); rulesets live -- `protect-main` requires DCO +
  `ubuntu-latest` + `windows-latest`, `protect-release-tags` covers
  `pulse-v*` (org-admin pushes bypass; never move a tag -- if a tag's CI
  fails, fix and cut the next patch version). DCO `-s` commits; identity
  Lefteris Notas <lefterisnotas@gmail.com>. Head: `b70d681` (wrap 19 --
  see the WRAP 19 block above; wrap-15
  key commits: `e31d396` release v0.2.0, `f15a6b0` packaging fix,
  `e626939` v0.64.3 CI pins, `41e4ace` site mode landed, `36f08c8`
  wishlist freeze, `4142c96`/`e7cbcbf` reference shelf).
- **Toolchain:** **v0.64.5 pinned + VALIDATED** (wrap 18/19; local pins
  Windows `%LOCALAPPDATA%\xiom.new-20261015-2240`, WSL
  `~/.local/share/xiom-v0645`, stdlib `092dfa0c` both). **v0.64.6 RELEASED
  2026-10-16T20:33Z** (darwin stream + stdlib `b81430ba`) -- adoption +
  darwin/pin suites queued as §3 item 7. Historical v0.64.3 bullet: (2026-10-10 dry run
  `38075327683` green on linux-x64 + windows-x64 with the pinned stdlib
  `48850df`; dl synced; pins in `docs/OPS-REQUEST.md` D.1 and every
  workflow; macOS shas pinned for the gated legs). **Local Windows/WSL
  installs were upgraded to v0.64.3 on 2026-10-10** (the re-extract had
  wiped the package store -- all 10 packages re-added; `xiom-pkg.exe`
  restored from the full extract; repeated after ANY toolchain
  maintenance). Local pin cache: `%LOCALAPPDATA%\xiom-pins\stdlib-dd352f6`. **C-PULSE-13 CLOSED (m232):** package home unified, no
  bridge anywhere (CI included); after any toolchain maintenance verify
  the store (`xiom doctor`; re-add with `xiom pkg install` -- a re-extract
  removes non-archive subdirs like `packages/`). Stdlib lane `d54929d`
  (wave 97); the v0.64.2 pairing is `4dd8844`; **PULSE's 0.2.0 darwin
  verification pins `dd352f6`** (wave 105.1: `read_file_bytes` payload-free clause + the owner-authorized darwin one-off in history). Exact/CI checks use the
  pin (`export XIOM_STDLIB=<pinned checkout>`). `dev-env.{ps1,sh}` respect
  explicit overrides; `dev-env.sh` finds `~/.local/bin/xiom`.
- **Shipped release: 0.2.0** (tag `pulse-v0.2.0`, 2026-10-10; linux-x64
  + windows-x64 -- owner's call: macOS artifacts ship in the follow-up
  once the arm64 memset codegen + Darwin x64 fp128 items land). The full
  0.2 contract slate (pagination, idempotency, `/v1`, OpenAPI, multipart
  uploads, real outbound client); smoke 119/119, four-leg dry run
  `38066169081` green on linux+windows; docs/public refreshed for the
  cut.
- **Shipped release: 0.1.2** (tag `pulse-v0.1.2`, 2026-10-09): session
  store swapped to registry `xiom.session` 0.1.0, v0.64.2 rebuild
  (Windows request-path memory flat), `PULSE_BIND` address-only
  validation, official icon embedded (pinned rcedit, local + CI).
  `pulse-v0.1.1` exists but was never released (its CI gate failed on a
  stale version literal; tags are immutable) -- documented in
  CHANGELOG.md. dl mirror live (`dl.xiom-lang.org/pulse/...`), GitHub
  Release has assets + `SHA256SUMS` + provenance.
- **Relay bus (xiom-relays, owner rollout 2026-10-10):** cross-lane
  coordination goes through the private `xiom-lang/xiom-relays` repo
  (cloned at `E:\xiom-lang\xiom-relays`; `python tools/relay.py`). At
  session start **and** before finishing any task: pull it and process
  items addressed to this lane (`relay.py view --lane pulse`); never
  edit another lane's item -- open a new one. Pulse is acked on the bus
  (`REL-20261010-1548-pulse`); migrated: darwin memset + C-PULSE-12/14/16
  -> compiler, C-PULSE-17/18 -> stdlib, darwin one-off notice ->
  stdlib (see `REL-20261010-1549-pulse*`). Wishlist-row migration
  continues on the doorbell. **Legacy relay docs frozen (freeze headers
  with bus pointers):** `COMPILER-FINDINGS-PULSE.md`,
  `COMPILER-RELAY-2026-10-09-v0.64.2.md`, `ORBITDB-RELAY-PULSE.md`,
  `XVECTOR-RELAY-PULSE.md`; `WEBSITE-RELAY-PULSE.md` stays the live
  0.2.0 cut/claim reference (migrating), `OPS-REQUEST.md` stays the
  standing ops spec. No deletions -- history + evidence stay in-repo.
- **Production references (owner-authorized, 2026-10-11):** MIT-only
  light clones (`--depth 1`) under `E:\repos` to mine battle-tested
  patterns for a full backend framework -- `h11` (HTTP/1.1 connection
  state machine), `bbolt` (crash-safe commit ordering), `gin`
  (middleware chain / context lifecycle / recovery), plus `fasthttp`
  (timeout model), `fastify` (hook taxonomy/schemas), `fastapi` (DI +
  OpenAPI-from-types), `chi` (route groups), `jose` (JWT hardening),
  `helmet` (security headers), `knex` (migration locks), `bullmq`
  (jobs/retries/stalled locks); findings + the version-ordered adopt
  backlog live in `docs/PRODUCTION-REFERENCES.md`.
- **Live demo:** pulse.xiom-lang.org serves the website page **through
  PULSE** (nginx -> loopback; landing via `PULSE_LANDING_PATH`, JSON via
  `/health` + `/api/version`); running **0.1.0** -- ops tried 0.2.0 and
  rolled back on the SIGILL (bus `REL-20261010-1721-ops`); redeploy
  0.2.x once the stdlib fix lands (site buttons/badge auto-follow
  `latest.json`; 0.2.0 zips are live on dl). Linux memory still open:
  keep `MemoryMax` + restart.
  orbitdb./xvector. phase-1 pages live (driver work queued for 0.3);
  docs.xiom-lang.org = versioned compiler-docs root, PULSE docs render
  at pulse.xiom-lang.org/docs/; registry.xiom-lang.org live (490 pkgs;
  GitHub sign-in / SQLite social layer implemented in the registry lane).
- **Current focus: the NEXT release (0.2.1 hotfix / 0.3.0)** -- owner
  shipped **0.2.0** on linux+windows and deferred macOS to the next cut.
  Main is green (`e7cbcbf`): packaging fix + v0.64.3 + **site mode
  landed** are all in; `pulse-v0.2.0` is live on GitHub + dl. Remaining
  gates, all on the bus (check `relay.py view --lane pulse`):
  1. **SIGILL / VPS**: stdlib `REL-20261010-1615-stdlib` + ops
     `REL-20261010-1721-ops` -- when fixed, re-verify and cut (the demo
     stays on 0.1.0 until then; ops rolled back).
  2. **macOS legs**: compiler `REL-20261010-1609-pulse` (arm64 memset
     codegen) + stdlib `REL-20261010-1609-pulse-2` (Darwin x64 fp128
     shims) -- when BOTH fixed: `RELEASE_BUILD_MACOS=true`, four-leg dry
     run, cut with macOS included.
  3. Compiler `REL-20261010-1854/2122-pulse` (the `&HandlerOut` helper
     crash; site mode shipped with the inlining workaround -- re-test
     the helper when fixed, no re-land needed).
  0.2.1 scope already on main: packaging fix + v0.64.3 pins + site mode
  (0.3-fleet item). Follow `docs/RELEASE-CHECKLIST.md` for the cut.
- **Checkpoint 2026-10-11 (post-wrap-15 session):** fresh sweep on
  `496b568` with the pin `dd352f6` is **GREEN on both platforms** --
  fleet 12/12 (incl. `probe_outbound_guard` + `probe_stdlib_server_parse`),
  m212 dash+dot check+run, suites x2, smoke 119/119 jsonl + kv;
  evidence `probe-logs/regress-20261011/` (win exe sha `928d2e1b...`,
  linux `19c0384b...`; WSL pin cache now holds `stdlib-dd352f6`). Bus:
  `REL-20261011-0317-pulse-3` (server_parse_request) and `-4`
  (TcpStream.write_all) **verified + CLOSED** as reporter -- both already
  shipped in `ec64dec` (ancestor of the pin; locked by the fleet probe
  11/11 and stdlib `p_pulse_shapes` exit 0 on win+linux).
- **Security headers unit ADOPTED (backlog order 1, 2026-10-11):**
  `c1b3618` ships the helmet-derived set on every response (nosniff,
  frame DENY, no-referrer, COOP/CORP `same-origin`,
  `Origin-Agent-Cluster: ?1`, HSTS `max-age=15552000; includeSubDomains`,
  DNS-prefetch off, cross-domain none, XSS-filter 0) via
  `http.security_head_lines()` in both builders; CSP is opt-in
  (`PULSE_CSP` / `csp` JSON key -- site mode safety; default off).
  test_http 74 checks green; full sweep FAILED=0 both platforms +
  smoke 119/119 (probe-logs/security-headers-20261011); CI dry run
  `38135447649` green; info to website `REL-20261011-1124-pulse`.
  **Next backlog: keep-alive/deadlines design doc (h11 + fasthttp).**
- **Keep-alive/deadlines design doc DONE (backlog order 2, 2026-10-11):**
  `docs/DESIGN-KEEPALIVE-DEADLINES.md` -- fasthttp's three named timeouts
  (read/write/idle; 408 on read expiry, silent close on idle expiry) +
  the h11 keep-alive state model and 10 adopted rules (keep-alive
  decision, MUST_CLOSE, trailing-buffer pipelining, half-close
  coupling, per-request framing, 16 KiB incomplete-head cap), two-phase
  plan (A: deadlines -- blocked on stdlib `0317-pulse`/`-pulse-2`;
  B: keep-alive on top), per-phase test plan, source index. Interface
  notes filed to stdlib (`REL-20261011-*`). **Next backlog: store
  durability design (bbolt).**
- **Store durability design DONE (backlog order 3, 2026-10-11):**
  `docs/DESIGN-STORE-DURABILITY.md` -- bbolt ordering discipline mapped
  to the store seam: sync-before-ack commit points (jsonl append +
  audit; `PULSE_STORE_SYNC`/`PULSE_AUDIT_SYNC`), compaction rename
  ordering with a new `fsync_dir` ask, seq-in-record as the commit
  marker, backup fence manifests (`fence_seq` + mode), explicit claim
  table, phases A/B/C. Interface notes filed to stdlib. **Next backlog:
  SQL migrations design (knex).**
- **SQL migrations design DONE (backlog order 4, 2026-10-11):**
  `docs/DESIGN-SQL-MIGRATIONS.md` -- knex model (lock table, applied
  tracking, batches, lexicographic UTC names, up/down) plus PULSE
  corrections (live/stale lock heartbeat instead of destructive unlock,
  idempotent first-run DDL, strict applied-but-missing validation,
  per-migration transaction rule incl. sqlite/MySQL caveats), runner
  contract (`pulse_app migrate status|up|down|create|break-lock`,
  explicit CLI step never at startup, `PULSE_SQL_DSN`, backup-fence
  gate). Implementation gated on a SQL driver package (vendored sqlite,
  bindings-11). **Next backlog: OpenAPI generation from route
  metadata.**
- **OpenAPI route-drift guard + single route table (backlog order 5,
  partial, 2026-10-11):** `router.xi` now has one source of truth
  (`route_defs()` -- dispatch, the CLI list and the guards all derive
  from it; the two hand-synced literal blocks are gone).
  `openapi.xi` gains `openapi_template()` and
  `openapi_missing_routes()` (structural JSON check: every route must
  appear as a templated path key with its lowercase method verb);
  test_app asserts zero drift, the undeclared `uploads` tag is fixed,
  CHANGELOG notes it. Remaining for the item: emit the `paths` object
  from the table (static overlay for prose/refs) + `openapi --check`
  mode; the hand-written document stays the source until then.
  **Next backlog: 0.4 middleware chain + jobs design (gin/fastify/bullmq).**
- **Middleware chain + jobs design DONE (backlog order 6, 2026-10-11 --
  ordered backlog complete):** `docs/DESIGN-MIDDLEWARE-JOBS.md` -- nine
  named stages mapped onto today's ladder (gate order preserved; error
  stage reachable from every stage; order tests to add first), gin +
  fastify mechanics (precomputed tables, sent-guard short-circuit,
  explicit reset contract), and the bullmq portable core
  (attempts/backoff, due-time delayed heap, lock heartbeat, two-phase
  stalled sweep, ownership-checked terminals) on a bounded
  loop-boundary runner that never blocks accept. **Ordered framework
  backlog is now fully landed: security headers shipped; all five
  designs (keep-alive, store durability, SQL migrations, middleware
  chain, jobs) waiting on their gates (stdlib runtime wave / SQL
  driver package).**
- **Batch-5 witness ready (2026-10-11):** `docs/repro/handlerout-helper/`
  (witness.patch + protocol) reproduces the `&HandlerOut` ref-param
  helper crash as 0xC0000005 on v0.64.3 (`probe-logs/repro-2122-20261011.log`);
  re-verify = apply patch -> run test_app -> expect GREEN once the
  compiler batch 5 lands, then re-land the helper as a permanent lock
  (no other site-mode re-land pending). Witness-ready note filed to
  compiler.
- **OpenAPI `--check` CLI (2026-10-11):** `pulse_app openapi --check`
  runs the route-drift guard against the served document -- exit 0 with
  OK, exit 1 with the missing list on drift; added to the
  RELEASE-CHECKLIST verify step; verified green + drift-red locally.
  Remaining on the openapi item: generate the `paths` object from the
  table (overlay for prose/refs) and retire the hand-written paths
  block.
- **Batch-5 closed; SIGILL still open (2026-10-11 doorbell):** compiler
  batch 5 shipped -- the frozen witness is **GREEN on m271/v0.64.4**
  (suite exit 0; `probe-logs/witness5-m271-reverify.log`) so
  `REL-20261010-1854/2122` moved fixed->verified->**closed** (relay
  `6ce8946`). The permanent helper re-land is **deferred until the CI
  toolchain pin moves to >= v0.64.4** (v0.64.3 still red on the shape;
  patch frozen in `docs/repro/handlerout-helper/`). **SIGILL check:
  `REL-20261010-1615`'s repro still dies 0xC000001D on m271 AND v0.64.3
  (A/B, isolated workdirs) -- the v0.64.4 wave does not cover it, so
  **0.2.1 stays gated**; negative evidence filed (`REL-20261011-1904-pulse`).**
  Compiler repo is cutting v0.64.4 (all six batches, m271); the
  `openapi --check` unit's dry run `38157843890` is green.
- **`0317-pulse-7` verified + closed (2026-10-11):** module-scope
  fn-pointer reassignment (m265/`fde5548e`) -- witness
  `docs/repro/fnptr-harness/` exits 0 on m271; v0.64.3 control fails
  `error[C001] unresolved 'handler'`. Suites keep dispatch-by-id; the
  harness capability is available for later test-runner work.
- **v0.64.4 wave (2026-10-12): pin ADOPTED, toolchain ON HOLD.** v0.64.4
  installed + verified on Windows/WSL (archives sha256-verified; WSL
  binary byte-identical to the archive). All 10 pinned deps reinstalled
  after the shared store (`%LOCALAPPDATA%\xiom\packages`) was found
  EMPTY during the wave (`REL-20261012-1418-pulse-2`, ops). `STDLIB_VERSION`
  moved to `3df0843` (stdlib-v0.64.4) and is clean (suites GREEN under
  v0.64.3; CI dry run `38261983177` green). **Toolchain adoption held**: a v0.64.4-built binary exits 0
  at startup in kv mode (jsonl fine; v0.64.3 control serves 200;
  pin-independent; repro `docs/repro/kv-hang-0644/`; compiler item
  `REL-20261012-1418-pulse`), so CI pins stay v0.64.3 and the
  `&HandlerOut` helper re-land is deferred with it. SIGILL `1615` repro
  still red on the released v0.64.4 archive (`0xC000001D`) -- **0.2.1
  stays gated**. Wave sweep: `probe-logs/toolchain-0644/` FAILED=1
  (solely smoke-kv on the v0.64.4 combo).
- **Production-grade relay (2026-10-12, owner request):**
  `docs/PRODUCTION-GAPS.md` landed -- 30-row parity matrix vs the
  reference shelf (fastify/gin/fasthttp/h11/helmet/bbolt/knex/bullmq):
  12/30 fully green, 10 designed-and-gated, 8 missing. Filed to the
  bus: stdlib wave 2 `REL-20261012-1946-pulse` (signals/drain,
  poll + accept deadline, SO_REUSEPORT, chunked stream writer for SSE,
  websocket primitives, gzip/deflate, linear json_parse, shutdown
  confirmation), packages `-pulse-2` (SQL driver priority, HTML
  templates + escaping), broadcast `-pulse-3` to all lanes.
  PULSE-internal additions are tracked in PRODUCTION-REFERENCES
  (static conditional/Range, per-route rate policy, test-runner
  harness, SSE/WS units, tracing decision).
- **m276 + wave-115 verified, closed (2026-10-12 late):** kv
  empty-store regression verified fixed on the fresh compiler build
  (m276 `0268c7d9`; PULSE kv leg serves `/health` 200 + creates
  `evt-seg-0000000001.kv`) -- **toolchain re-adoption waits for the
  next archive carrying m276+**. Durability primitives verified via
  the wave-115 lock probe (`p_wave115_shapes.xi` exit 0 on stdlib
  `c65acb5`: `io.fsync` + `sync_io.sync_fd` + real `io.flush_stdout`)
  -- **durability Phase A is cleared to implement once the re-vendored
  pin lands**. Production relay: stdlib wave-2 + packages items acked;
  xvector/engine filed their own gap relays the same day. Bus
  `d98e2f3`.
- **Wave-119 landing (2026-10-13 early): keep-alive + durability
  source-side UNBLOCKED.** `0317-pulse` (socket options; Windows
  SO_REUSEADDR root cause), `-2` (deadline recv; the 250 ms loopback
  lock) and `1134-pulse` (fsync_dir; file-sync-before-rename /
  dir-sync-after) verified via `p_wave119`/`p_wave115`/`p_wave60`
  probes (all rc=0 on stdlib `a9b21b2`/`c65acb5` + the wave runtime via
  `XIOM_RUNTIME_DIR`) and closed on the bus (`b413b0e`). With `-5`/`-6`
  closed earlier, **every critical-path stdlib ask is now fixed**.
  Implementation (keep-alive Phase A/B, durability Phase A/B) waits
  ONLY on the next compiler pin that re-vendors stdlib/runtime (the
  same archive that carries m276+ re-adopts the held v0.64.4
  toolchain). Remaining gates unchanged: SIGILL `1615` (0.2.1), macOS
  pair; production relay wave-2 asks (signals/poll/streaming/WS/gzip/
  json_parse) still `acked`.
- **Game-backend positioning (2026-10-13, owner question):**
  `docs/GAME-BACKEND-POSITIONING.md` -- PULSE is the game HTTP/WS
  backend + control plane (accounts/sessions/JWT, matchmaking queues +
  lobby metadata, leaderboards, telemetry ingest, webhooks with
  idempotency, server register/heartbeat/allocate); XIOM Engine owns
  the realtime plane (tick netcode, UDP/QUIC/WebTransport, prediction,
  relays). Games raise WS/SSE + jobs/matchmaking + multi-worker/sticky
  priorities; engine informed with a reuse offer + `/api/game/*`
  control-route offer (`REL-20261013-1313-pulse`). **Owner endorsed the
  split the same day**; follow-up filed asking the engine to reply with
  its in-engine HTTP stance + the exact `/api/game/*` routes
  (`REL-20261013-1316-pulse`).
- **Wave-2 progress (2026-10-13): near-complete.** stdlib wave 121
  (WebSocket helpers + chunked/stream writers + `send_all`) and wave
  122 (`socket_poll_read/write` + `SO_REUSEPORT`; POSIX double-bind
  locked) landed -- probes `p_wave121_shapes`/`p_wave122_shapes`
  pre-verified rc=0 (`probe-logs/wave121-122/`). **Only signal
  delivery remains** from the wave-2 ask. Triage also resolved two
  asks pre-emptively: `json_parse` linear since wave 111, gzip/deflate
  already in `xiom.compress` (PRODUCTION-GAPS updated).
- **Wave-2 CLOSED + engine contract (2026-10-13):** all rows delivered
  (waves 119-123); locks re-verified (`p_wave121/122/123_shapes` --
  the signals probe green on release v0.64.4 + stdlib main +
  `XIOM_RUNTIME_DIR`) -> `REL-20261012-1946-pulse` verified + **closed**.
  Our entire production wave-2 ask is now source-complete: deadlines,
  drain signals, poll/select, SO_REUSEPORT, chunked/stream writers,
  WebSocket helpers. The engine lane replied with the **`/api/game/*`
  control-plane contract** (`REL-20261013-1455-engine`, acked):
  register / heartbeat(+command piggyback) / config(ETag) / compat /
  match-report / telemetry, per-server bearer tokens, idempotency;
  engine consumes PULSE modules for in-engine HTTP (no second stack,
  never in the tick path). **Queued as the next PULSE-internal unit**
  (PRODUCTION-REFERENCES row; needed stable before their P8 design
  opens; not gated on the compiler pin).
- **Game control plane SHIPPED (2026-10-13, `/api/game/*`):** the P8
  contract is implemented and suite-covered (28 checks in test_app):
  register (per-server bearer token), heartbeat (command piggyback),
  config (revision/ETag/304/409 incompatible_build), compat,
  match-report + telemetry (Idempotency-Key dedup), admin command
  (ops token; 403 when disabled). Records append to `PULSE_GAME_PATH`
  (kind-tagged, latest-wins); config at `PULSE_GAME_CONFIG_PATH`;
  cadence `PULSE_GAME_HEARTBEAT_SECS`; overlay keys
  `game_path`/`game_config_path`/`game_heartbeat_secs`. OpenAPI paths +
  `game` tag added (drift guard satisfied); http-api docs + CHANGELOG
  updated. Static conditional-GET/Range backlog row struck (already
  shipped via `xiom.static`).
- **SQL driver co-verify (2026-10-13):** packages shipped `xiom.sqlite`
  0.4.0 (eco-v0.1.174; checksum+signature verified) and requested
  consumer co-verification. Result: **driver surface GREEN 24/24 on
  v0.64.4 AND v0.64.3** (in-tree vendored sources + `--c-source`
  vendored sqlite3.c; `docs/repro/sql-coverify/`). **Blocking packaging
  finding filed** (`REL-20261013-1715-pulse`): the published package.xi
  lacks the `modules:` list -> `use xiom.sqlite;` = unresolved import
  for every external consumer (kv control imports fine); fix = modules
  list + a consumer-import smoke in the publish gate. Artifact-level
  rerun scheduled on the fixed republish. Doc notes: `rows_affected` =
  `sqlite3_changes` (last statement only); consumer syntax =
  unqualified type statics + module-prefixed free fns. Result:
  `REL-20261013-1718-pulse`. Game-CP dry run `38435178845` green.
- **SQL artifact rerun (2026-10-13):** packages published **0.4.1**
  (modules restored; install verified) in response to our finding --
  `REL-20261013-1715-pulse` verified + **closed**. Rerun on 0.4.1:
  import now accepted but dep symbols still undefined (T001 cascades,
  both syntax forms) -- residual cause is the **compiler multi-module
  consumer-discovery bug** (packages' kv-controlled A/B; their
  `REL-20261013-1731-packages` -> compiler). PULSE filed the `--run`
  datapoint (`REL-20261013-1901-pulse`); in-tree control remains 24/24
  green; artifact rerun repeats on the next compiler candidate
  (`REL-20261013-1721-bindings-3` acked with the result).
- **SIGILL GATE CLEARED AT SOURCE (2026-10-14):** compiler **m297**
  (`6797197d`) fixed the `Path.is_dir` implicit-self recursion (the
  `0xC000001D` startup crash family). PULSE verified on the post-fix
  compiler (m305 range): witness `p_path_println_context_crash` **rc 0**
  (was 0xC000001D), server builds + serves `/health` 200 in **jsonl AND
  kv** modes. **m303 also resolved the sqlite registry-artifact
  consumer blocker**: 0.4.1 probe **24/24 GREEN** via `--run`
  (unqualified type-statics form; the README `driver.`-form nuance
  noted to packages). Ops told to **HOLD** the demo until the archive +
  our redeploy ping (`REL-20261014-1305-pulse/-2/-3`). **Release
  sequence: next compiler archive (m297+) -> toolchain wave-2 (re-pin +
  helper re-land + full sweep both platforms) -> cut 0.2.1 per
  docs/RELEASE-CHECKLIST.md -> ops redeploy.**
- **v0.64.5 candidate HELD (2026-10-14 late):** stdlib's release-gate
  battery found regressions on the candidate (corpus 953/955; probe
  compilefails: `zext float` cast, duplicate `LinkedList.invariant_check`
  emission; `p_wave107/108` crypto pair lengths -1 then AV; controls
  green on v0.64.4 -> release-wave suspects m314-m319;
  `REL-20261014-2123-stdlib`). **The `stdlib-v0.64.5` tag is HELD** and
  the archive now waits on a compiler fix wave + battery re-run. The
  SIGILL fix (m297) is in the candidate; PULSE's wave-2 sequence stays
  staged and fires on the eventual release. No demo change (ops still
  on hold).
- **v0.64.5 RELEASED (2026-10-15T19:18Z):** GH assets live now (windows
  `bd71e2d3...`, linux `246e5e82...`; macos x64/arm64 also); paired
  stdlib pin from the compiler tag (`v0.64.5:STDLIB_VERSION`) =
  **`092dfa0c`** (the moved stdlib-v0.64.5); the dl mirror lands at the
  next :17 sweep. **NEXT SESSION = toolchain wave-2, then cut 0.2.1** --
  full recipe is the §3 paste prompt (wrap 16). Demo stays on 0.1.0
  until the ops redeploy ping.
- **NEW GATE -- v0.64.5 linux-x64 miscompile (xvector,
  `REL-20261015-2142-xvector`, compiler `acked` high):** on Linux,
  v0.64.5 mis-compiles xvector's HTTP service `/search` path (route
  miss -> 404/400; 6 gates red on WSL; **v0.64.4 linux AND v0.64.5
  windows are green**; reproduces with the bundled stdlib; repro
  `docs/repro/xv-http-service-linux` in their repo). PULSE is an HTTP
  server -- treat this as a live risk for the wave-2 Linux legs AND the
  0.2.1 demo (the VPS is Linux). Wave-2 step: if PULSE's Linux sweep
  shows any routing/param anomaly (or suites/smoke red in a
  routing-shaped way), STOP, file with our repro, and hold the cut
  until the compiler item clears; if our Linux legs are green, cut but
  tell ops to validate routing (not just /health) before switching
  traffic, keeping the 0.1.0 rollback armed.
- **0.2.1 RELEASED (2026-10-15T21:23Z) -- wrap 17:** wave-2 adopted
  v0.64.5 + pin `092dfa0c` (fleet 12/12, suites x2, smoke 119/119
  jsonl+kv both platforms; helper re-landed `3743704`; CI pins
  `0e2ee57`; SQL artifact 24/24 on both platforms -- bus: 1718/1901
  closed, bindings reply `REL-20261015-2029-pulse`, compiler `-2` +
  stdlib `-3` INFOs). Cut `9ac3016` (11 literals), dry run `38808053663`
  green, tag `pulse-v0.2.1`, release run `38808850409` green (guard +
  both legs + publish): linux
  `81cce634a0fbcace59ab97045fad1493bf8d5bf99bba7cd1b11a5825148e455c`,
  windows `df96da7c917300e512f431d3b93a15d9933e4243a5f57b284f8fb994999b8daf`;
  release body carries the highlights; dl at the next :17 sweep; ops
  pinged (`REL-20261015-2125-pulse`) to redeploy the demo 0.1.0 -> 0.2.1.
  Local: Windows `xiom.new-20261015-2240` (default `xiom.new`
  byte-identical, v0.64.3 A/B kept), WSL `xiom-v0645`; pin caches
  `stdlib-092dfa0c` both; 11 deps incl. `xiom.sqlite@0.4.1`. Evidence:
  `probe-logs/toolchain-v0645/` (post-bump WIN/LINUX summaries +
  `-prebump` copies) + `sql-coverify/artifact-0645-{win,linux}.log`.
- **Top-tier directive (2026-10-15) -- wrap 17b:** owner escalated the
  goal to #1-class multipurpose framework (static/apps/realtime,
  balancer scale-out, safe/fast/secure, modern + legacy). Roadmap +
  capability truth table + milestones: `docs/ROADMAP-TOP-TIER.md`;
  lane asks filed `REL-20261015-2202-pulse` (stdlib, 10 items, TLS
  first), `-2` (compiler, FFI hardening / ffigen C-headers), `-3`
  (packages, templates/TLS binding/OTLP/codecs), `-4` (ops, edge +
  multi-worker templates), `-5` (broadcast). Headline gap: no TLS
  anywhere in-tree. Compile-speed concern dismissed (controlled A/B
  clean).
- **Site-mode 301 (doorbell unit, 2026-10-15T23:4xZ):** the website
  lane's full-tree pass found slash-less directory paths serving 200
  with broken relative assets; now 301 to the canonical slash form
  (prefix + query preserved), with dir-before-file resolution for POSIX
  (the naive order was Windows-only-correct -- caught by the Linux
  sweep, fixed pre-commit). `74cd0f9`, three new site checks, both
  platforms FAILED=0; `run.sh` log cap 200->400. Reply
  `REL-20261015-2344-pulse`; ships in 0.2.2.
- **Product-split directive (2026-10-16):** owner locked the codenames --
  **PULSE Beacon** (embeddable edition: the `xiom.pulse` package you
  add to an app) / **PULSE Station** (hosted edition: the full product,
  docker/k8s); one protocol core, two editions, never a fork (the
  orbitdb satellite/station pattern; the product is PULSE on both).
  Roadmap §9 (`docs/ROADMAP-TOP-TIER.md`); publish ask
  `REL-20261016-1108-pulse` (packages acked -- `xiom.pulse` slot free,
  porter-flow scoping agreed at the keep-alive A+B freeze); codenames
  note `REL-20261016-1121-pulse`. Sequence: keep-alive A/B -> core
  extraction (Beacon) -> Station consumes -> publish + registry canary.
- **Keep-alive A+B LANDED -- Beacon freeze gate GREEN (2026-10-16):**
  Phase A (`7924222`): deadlines -- `PULSE_READ_TIMEOUT`/
  `PULSE_WRITE_TIMEOUT`/`PULSE_IDLE_TIMEOUT` + check-config/warns,
  bounded recv per request, non-blocking poll-gated send (the Linux
  50 MB stream check caught the blocking-send bypass), `408` from
  IDLE. Phase B (`56eb9f8`): per-connection trailing buffer +
  `request_complete` pre-check (pipelined requests never wait on a
  recv), one-way reuse latch (comma-token `Connection: close`,
  HTTP/1.0 never reuses, incomplete framing closes after the
  response), in-order pipelining with no data loss, silent idle
  expiry, EOF-mid close, garbage -> 400+close; `PULSE_KEEPALIVE=0`
  restores close-per-request. Smoke 119->134 per backend; both
  platforms FAILED=0, 134/134 x2. Freeze milestone FILED:
  `REL-20261016-1401-pulse` (packages -- porter flow open). The
  A+B check set is the Beacon core's frozen semantics.
- **Packages deliveries on the top-tier asks (2026-10-16):**
  `xiom.template 0.2.0` LIVE (blocks/loops/auto-escape -- top-tier
  item 1; consumer-verify queued §3 1c); `xiom.ssl` BUILDING (the
  TLS ceiling item); `xiom.otel 0.1.0` built green (held on the ops
  scope); `xiom.zstd 0.3.0` real (vendored 1.5.7); real brotli in
  flight at bindings; `xiom.pulse` slot reserved + porter SPEC
  armed (refs `REL-20261016-1111/-1150-packages`, acks `65a11b7`).
  Registry mojibake fixed (`a54862a`; validate clean, 596 items).
- **0.2 PULSE-side progress:** DONE -- OpenAPI 3.1 served
  (`/openapi.json`, version token substituted at serve time) + `pulse
  openapi`; full CLI set (`routes`, `version`, `check-config`); additive
  error `status` in every envelope (incl. the 405 Allow path); official
  icon adopted + embedded; **pagination `Link` on `GET /api/events`**
  (seq-in-record cursor: durable `seq`, legacy fallback ordinal,
  `next_cursor` + RFC 8288 `Link rel="next"`, `?before=` walk-back,
  `400 invalid_cursor`); **idempotency keys on event writes**
  (`Idempotency-Key` header, durable `idem` marker in the record, replay
  with `deduplicated:true`, `400 invalid_idempotency_key`); **`/v1`
  versioned alias** (every route resolves under both forms; new surfaces
  go `/v1` first; `Link` preserves the client's prefix); **outbound
  client base** (`xiom.http` **0.1.4**, SSRF guard
  `xiom.pulse.outbound` + `probe_outbound_guard` in the fleet;
  libcurl transport seam proven end-to-end via the 0.1.5 recipe, below);
  **multipart uploads** (`POST /api/uploads` + `/v1` alias; PULSE-side
  parser, per-part/part-count caps, generated on-disk names, stable
  415/400/413 errors); **outbound client REAL** (`xiom.http` **0.1.5**
  adopted 2026-10-10: bridge shims + recipe; `scripts/outbound_transport_probe.{ps1,sh}`
  proves guard-block -> allowlist -> real GET 200 on both platforms);
  fleet **12/12**, smoke **119/119** on both
  platforms (Linux run with the pinned stdlib). **The 0.2 PULSE-side
  slate is COMPLETE and the docs/public-set refresh is DONE** (wrap 14
  follow-up: public pages refreshed; `docs/RELEASE-CHECKLIST.md` encodes
  the mechanical cut incl. every version literal; `package.xi` manifest
  drift fixed -- version, `xiom.http` 0.1.4, module list) -- next: the
  0.2.0 cut when macOS is green (upstream gates below).
- **0.3 interop (first tranche, wrap 14):** ORBITDB + XVector consumer
  conformance probes built and GREEN both platforms --
  `tests/interop/orbitdb/probe_pkg_orbitdb.xi` (**39/39**; roundtrip +
  reopen x2 at 1k keys, query edges, open/order/stale-handle errors, txn
  commit/abort, delete persistence) and
  `tests/interop/xvector/probe_pkg_xvector.xi` (**30/30**; exact Flat
  roundtrip, top-k edges, dimension limits, delete/re-add, duplicate-id
  overwrite, WAL persist/recover, torn-tail prefix). Source-level
  composition (nested `xiom.toml` + relative `source-roots`; lanes'
  pattern), local-only until the packages publish. Trap note filed in
  both relays: `search(k=0)` / `create_collection(dim=0)` are contract
  traps, not Err. **Follow-up (2026-10-10): XVector filters (scenario 2,
  +12 checks -> 42/42) and the ORBITDB hard-kill harness (scenarios 2/3:
  writer/uncommitted-txn -> marker -> SIGKILL -> verify) are GREEN on
  both platforms** (`scripts/interop_orbitdb_crash.{ps1,sh}`); the
  hybrid join stays with the ORBITDB lane's `probe_hybrid` until the
  0.3 drivers compose it. **Site mode (2026-10-11): `PULSE_SITE_DIR`
  LANDED + CI-verified** (commit `41e4ace`, dry run `38098415021` green
  on linux+windows with the stdlib pin `dd352f6`) -- whole-tree serving,
  clean URLs, `404.html`, `application/wasm`; the website cutover and
  the playground static bundle can ride it.
- **Bug gates:** C-PULSE-08/10/11 CLOSED; **C-PULSE-02 CLOSED**
  (no-source-roots build verified); **C-PULSE-09 CLOSED + swap shipped**
  (fleet 11/11 both platforms); **C-PULSE-13 CLOSED (m232)**; **C-PULSE-14
  split on v0.64.2**: Windows flat, **Linux still grows (~87 KB/req
  steady; worse than v0.64.1)** -- retest on the next archive;
  **C-PULSE-16 OPEN** (`PULSE_BIND` advisory; address-aware bind filed;
  demo firewalled); C-PULSE-12 open (rename workaround used twice;
  import-alias syntax ask); **C-PULSE-17 NEW** (`io.list_dir` returns
  dangling names on v0.64.2 -- repro
  `docs/repro/io-list-dir-dangling/`; PULSE avoids list_dir entirely);
  **C-PULSE-18 NEW** (`time.sleep_ms` is a NO-OP on v0.64.2, both
  platforms -- repro `docs/repro/time-sleep-noop/`; harness writers
  busy-wait on monotonic deadlines); **bus round 2 (2026-10-11):**
  C-PULSE-17's sibling (`read_file_bytes` nested-read trap) FIXED by
  stdlib `dd352f6`, verified+closed (`REL-20261010-2122-pulse-2`);
  compiler helper crash bisected (`REL-20261010-1854/2122-pulse`,
  worked around); wishlist rows all migrated to the bus
  (`REL-20261011-0317-pulse*`).
- **Score:** ~55.4% production grade (`docs/PROGRESS.md`).
- **Stores:** jsonl = default; kv = verified opt-in both platforms
  (20m + 45m Linux soaks); flip still gated on the recorded
  prerequisites. **`xiom.http` 0.1.5 in-repo** (bumped on the 0.1.5
  adoption; real client proven via `scripts/outbound_transport_probe.*`;
  see the wishlist for the remaining auto-hook ask); all ten package
  gates green.
- **Wrap 4 (chunked + manifest + soak):** `Transfer-Encoding: chunked`
  REQUEST decoding landed (caps, extensions ignored, trailers validated;
  TE+CL -> 400; other codings -> 501) with smoke **76/76** on both
  platforms (test_http +11 parse cases, route cases in test_app);
  `xiom.toml` `source-roots` RETIRED -- the manifest has no machine
  paths (C-PULSE-02 closed). The fresh 30m Linux HTTP soak surfaced
  **C-PULSE-14** (see bug gates; the "Windows flat" comparison there was
  later invalidated by the wrap-6 soak-sampling bug). Evidence:
  `probe-logs/soak-http.summary.txt` + the progress curve; runtime repro
  `tests/probes/probe_alloc_loop.xi`.
- **Wrap 5 (config validation):** invalid values now warn at startup and
  in `--check-config` (port/uint/TTL/bool/enum; test_app +8 checks, smoke
  **78/78** on both platforms). Configuration 80 -> 85.
- **Wrap 5b (kv ops surface):** Dockerfile exports
  `PULSE_KV_DIR=/data/pulse-kv`; `backup.{sh,ps1}` are kv-aware
  (`--kv-dir`/`-KvDir`, env default, `kv-store/` snapshot with per-file
  hashes; verified both platforms); `DEPLOYMENT.md` covers the kv store +
  snapshot/restore and the current Linux systemd guidance. Flip still
  gated on a longer kv soak (crash/reopen covered by `store_soak`).
- **Wrap 6 (C-PULSE-14 correction + tools):** the Windows soak sampler
  measured the `cmd.exe` wrapper, not the server -- all historical
  "flat memory" numbers are invalid and the leak is **cross-platform**
  (~32 KB/req Windows, ~48 KB/req Linux). Fixed `soak_http.ps1` +
  `concurrent.ps1`; added `scripts/rss_probe.{sh,ps1}` (steady-state
  growth per request in ~2 min, either OS). m235 in the compiler lane is
  the candidate fix (loop-body static allocas) -- retest on the next
  archive. Reliability 40 -> 35, Testing 82 -> 80. Also: **45m kv soak
  green** (977/0, compact + hard-kill reopen intact, single 90 KB
  segment) -- the flip gate is now only the >= 24h aggregated bar.
- **Wrap 7 (release pipeline, owner-greenlit demo sequence):** CI infra
  committed -- `.github/actions/setup-xiom` (pinned v0.64.1 toolchain,
  SHA256-verified per platform, stdlib checkout at `STDLIB_VERSION`
  `4dd884423ab7ea39a3962630d1ea2552bfd16a2d`, the C-PULSE-13 bridge, ten
  pinned deps), `ci.yml` (PR tier: suites x2 + smoke on both OS),
  `release.yml` (guard -> fleet -> `pulse-<ver>-<os>-<arch>.zip` +
  `.sha256` + `SHA256SUMS` -> GitHub Release on `pulse-v*`), `heavy.yml`
  (weekly 30m HTTP + kv soaks + RSS probe). Sequence executed: main
  pushed; rulesets verified live (owner-applied protect-main +
  protect-release-tags; CI contexts `DCO`/`ubuntu-latest`/`windows-latest`
  added to protect-main); dry run green on the Linux leg and it **caught
  a mis-transcribed Windows toolchain SHA** (fixed, re-run fully green);
  tag `pulse-v0.1.0` cut at `cc3e741`; **GitHub Release published** with
  `pulse-0.1.0-{linux,windows}-x64.zip` + per-asset `.sha256` + combined
  `SHA256SUMS`, build provenance attested. Ops mirrors to
  `dl.xiom-lang.org/pulse/...` (slug `pulse`, hourly at :17); the
  website then wires downloads + the live badge; demo deploy per runbook.
- **Wrap 7b (docs + conventions):** public docs phase A delivered in-repo
  (`docs/public/`: summary + Introduction/Install/Quick start/
  Configuration/HTTP API/Operations/Security/Releases; ASCII, front
  matter, relative links) and `CHANGELOG.md` added; the GitHub release
  body carries the 0.1.0 highlights. Conventions confirmed with the
  website lane (no macOS artifact; mirror layout; `/api/version` ==
  tag). Relay-back in `docs/WEBSITE-RELAY-PULSE.md` section 11.
- **Wrap 7c (ops env correction):** `PULSE_BIND=<addr>:<port>` is a silent
  trap (the port part is ignored; ops hit it on the VPS and fixed the
  unit to `PULSE_BIND=127.0.0.1` + `PULSE_PORT=3500`). Now covered by
  config validation: an `addr:port` / `[v6]:port` value warns at startup
  and in `--check-config` (bare IPv6 like `::1` is not flagged);
  test_app +4 checks; runbooks (public + internal) all state
  address-only. Verified both platforms (suites x2, smoke 78/78).
  Side-finding filed: the compiler silently accepted a stray `}` that
  left code outside the function body (COMPILER-FINDINGS wrap 7c).
- **Wrap 8 (macOS prep + bind finding):** macOS release support prepared
  (setup-xiom macOS branch, SHA-pinned x64/arm64 toolchains; release
  matrix macos-x64/macos-arm64 with suites x2 + smoke; portability: lsof
  `wait_listen` fallback, `timeout`/`gtimeout` watchdog fallback,
  `pulse_sha256` sha256sum/shasum helper, `release.sh` OS detection ->
  `pulse-<ver>-macos-<arch>.zip`; the first dry run surfaced upstream
  darwin blockers (runtime C `_SC_AVPHYS_PAGES`, arm64 x86 asm, a
  codegen intrinsic -- all filed), so the legs are gated behind
  `RELEASE_BUILD_MACOS` and the next release is not blocked).
  **C-PULSE-16 filed:** ops verified `PULSE_BIND` is not enforced (stdlib
  wildcard bind; local repro LISTEN `0.0.0.0`); demo firewalled;
  address-aware bind filed upstream; fix + LISTEN-address smoke check
  with the next release (owner: next cut = compiler fixes + macOS).
  Score: Security 46 -> 42, Testing 80 -> 88 -> ~55.4%.
- **Wrap 9 (v0.64.2 adoption):** both platforms on v0.64.2; the CI setup
  action's C-PULSE-13 bridge removed. **C-PULSE-09 CLOSED** -- probe
  fleet 11/11 on Windows AND Linux (`probe_adopt_smoke` steps 1..10, exit
  0 on both). **C-PULSE-13 CLOSED** (m232; verified installs + doctor).
  Suites x2 + smoke 78/78 on both platforms; m212 gate green; crash 6/6.
  **C-PULSE-14: Windows FIXED (flat over 206 req); Linux still grows
  ~87 KB/req steady (worse than v0.64.1's ~48)** -- retest on the next
  archive. Incident: a concurrent toolchain re-extract wiped the WSL
  packages store mid-sweep (reinstalled via `xiom pkg install`; green
  after) -- verify the store after any install. **NEXT: the session-store
  swap retry (bridge `220f814`) -- now unblocked on both platforms.**
- **Wrap 10 (framework roadmap):** `docs/FRAMEWORK-ROADMAP-PULSE.md`
  filed -- the production-grade contract (capability map with per-area
  upstream asks; milestones: 0.1.1 -> 0.2 foundations [driver seam, auth
  core, OpenAPI/problem+json/pagination, CLI subcommands, multipart,
  HTTP client] -> 0.3 data drivers [OrbitDB embedded, XVector vector,
  SQL via bindings, migrations] -> 0.4 integrations [payments, email,
  OIDC, webhooks, jobs] -> 1.0 production grade) and the **next
  candidate release plan for ALL OSs** (0.1.1 = v0.64.2 rebuild +
  session swap + fixes; `pulse-0.1.1-{linux,windows}-x64` ready, macOS
  x64/arm64 gated on the darwin blockers -- ship all four when green,
  else carry macOS to 0.1.2). Driver seam = versioned
  `xiom.pulse.driver` contract; every integration ships with a
  conformance probe.
- **Wrap 10b (orbitdb/xvector handshake):** two relay messages filed --
  `docs/ORBITDB-RELAY-PULSE.md` and `docs/XVECTOR-RELAY-PULSE.md` --
  asking each lane to write `docs/PULSE-INTEGRATION.md` in their repo
  (embedding API + snippets, build/link contract + platform matrix, pin,
  consumer-affecting findings incl. recovery/memory, conformance test
  proposal, cross-asks). PULSE reads it locally (read-only), then builds
  `probe_pkg_orbitdb` / `probe_pkg_xvector` and wires the 0.3 drivers;
  the vector use cases are events search + RAG endpoints, and the hybrid
  (OrbitDB rows + XVector embeddings) is the intended showcase.
- **Wrap 11 (0.1.1 cut):** session-store swap DONE -- `src/session.xi`
  wraps registry `xiom.session` 0.1.0 (ids/expiry/pruning from the
  package; user as the "user" entry; module renamed
  `xiom.pulse.sessions` for C-PULSE-12). Verified both platforms: build
  + `probe_adopt_smoke` + suites x2 + smoke 78/78. Version 0.1.1
  (rebuilt on v0.64.2: Windows memory flat + BIND validation warning +
  docs); CHANGELOG + public docs updated. Tag `pulse-v0.1.1` cuts
  linux+windows artifacts; **macOS stays gated** (darwin blockers).
- **Wrap 11b (package-lane relay):** durable-DB ask SERVED and verified
  signed on the registry -- `xiom.sqlite 0.2.0` (vendored amalgamation;
  waits on the `--c-source` build-hook story for registry consumers),
  `xiom.libpq 0.2.0` + `xiom.odbc 0.2.0` (dynamic-loader, SKIP when
  absent), and `xiom.http 0.1.4` (real-libcurl GET/POST -- no outbound
  binding needed; PULSE bumps in 0.2 and adds the SSRF guard). Filed in
  the package wishlist + roadmap; no 0.1.1 scope change.
- **Wrap 12 (0.1.2 ships):** the `pulse-v0.1.1` tag's CI gate failed on
  a stale version literal in `test_smoke.xi` (PULSE-side; nothing
  published); tags are immutable (protect-release-tags, no bypass), so
  the fixed cut is **0.1.2**: all expected-version literals updated
  (pulse.xi, server APP_VERSION, http Server header x2, test_smoke,
  test_http, smoke twins), verified with the pinned stdlib (CI parity),
  re-tagged. **`pulse-v0.1.2` published green:** guard + linux/windows
  packages + GitHub Release (assets + per-asset `.sha256` + `SHA256SUMS`,
  provenance attested; release body carries the 0.1.2 highlights).
  Relay-back + ops mirror note: `WEBSITE-RELAY-PULSE.md` section 13.
  Bindings-lane addendum filed: sqlite README carries the
  3-line consumer snippet + the required `--c-source` flag (ergonomic
  fix filed by that lane); xiom.http 0.1.4 covers outbound; they
  keep-fresh and target accelerators after the `xiom.vectors` extraction.
  Compiler finding updated: the `@llvm.memset.p0i8.i64` IR warning also
  reproduces on Linux CI (llvm-16), not only darwin.
- **Wrap 12b (0.2.0 direction):** owner decision -- the next release must
  matter: **macOS x64 + arm64 artifacts and real gap coverage** (not a
  maintenance cut). macOS critical path confirmed upstream and unfixed on
  the current lane sources: `xiom_runtime.c:4222` (`_SC_AVPHYS_PAGES`),
  `fp128_helpers.c` (x86 asm on arm64), compiler `@llvm.memset.p0i8.i64`
  emission (xiom-codegen `emitter.rs:859`, `expr.rs:3774`,
  `stmt.rs:713/1131`) -- fix sketches filed in the two wishlists. 0.2.0
  PULSE-side slate fixed in the roadmap: OpenAPI + additive problem+json
  + pagination + idempotency, CLI subcommands, `xiom.http` 0.1.4 + the
  SSRF-guarded client wrapper, multipart uploads, docs refresh. 0.1.2
  remains the shipped release.
- **Wrap 13 (0.2 starts: OpenAPI contract):** `GET /openapi.json` serves
  the OpenAPI 3.1 document (`resources/openapi.json`; the version token
  is substituted at serve time from the running build, so the contract
  and `/api/version` cannot drift); CLI gains its first subcommands --
  `pulse_app openapi` and `pulse_app routes` (17 routes, argv[0] note:
  args scan includes the exe path); config gains
  `PULSE_OPENAPI_PATH`; test_app +7 checks; smoke 78 -> **84/84** on
  BOTH platforms (Linux run with the pinned stdlib). Roadmap 0.2 items
  1/2 partially ticked; problem+json, pagination, idempotency, `/v1`,
  flag promotions next.
- **Wrap 13b (icon):** owner-provided `pulse.ico` (187,396 B, sha256
  `d424af89...`) adopted as the canonical icon at
  `resources/img/pulse-ico.ico` (all references, release staging and the
  `/favicon.ico` route stay stable); the **Windows exe now carries it**
  via **pinned rcedit v2.0.0** (`build.ps1` resolves PATH -> npm global
  -> `%LOCALAPPDATA%\xiom-tools`; the CI setup action fetches and
  sha256-verifies it for release builds). Verified: exe +187,904 B,
  `ExtractAssociatedIcon` loads 32x32; suites x2 + smoke 84/84 on both
  platforms. `xiom --icon` is still absent in v0.64.2 -- ask stands.
- **Wrap 13c (error status + CLI set):** every error path now mirrors the
  HTTP status additively in the envelope (`{"error":{"status":N,...}}`;
  the 405 Allow-header path uses the same shared helper); the CLI set is
  complete -- `version` and `check-config` subcommands join
  `openapi`/`routes`. test_app +3 checks; smoke 84 -> **89/89** on both
  platforms (Linux pinned-stdlib). Roadmap 0.2 item 2 done, item 1
  partially; pagination/idempotency/`/v1` next.
- **Wrap 14 (0.2 slate COMPLETE + first 0.3 interop):** pre-work full
  regression (fleet, suites x2, smoke 89/89 both platforms) against the
  wrap-13c binaries; then, in order: **pagination `Link`** on
  `GET /api/events` (seq-in-record cursor, legacy ordinal fallback,
  `next_cursor`, RFC 8288 `rel="next"`, `400 invalid_cursor`) `9301052`;
  **idempotency keys** (`Idempotency-Key`, durable `idem` marker, replay
  `deduplicated:true`) `a6a55b9`; **`/v1` alias** (`v1_path`; Link
  preserves the client's prefix) `602c9e6`; **outbound base** (`xiom.http`
  **0.1.4**, SSRF guard `xiom.pulse.outbound` + `probe_outbound_guard`
  42 checks in the fleet; libcurl transport seam isolated pending the
  `--c-source` hook) `bf6d9b0`; **multipart uploads**
  (`POST /api/uploads` + `/v1`, parser + caps + generated names; found +
  filed **C-PULSE-17** `io.list_dir` dangling names with a staged repro,
  and an `io.create_dir` requires-exists trap) `130a54b`; **interop
  probes** for ORBITDB (39/39) + XVector (30/30) with relay responses
  `6171304`. Every unit: suites x2 + smoke (final **119/119**, jsonl+kv,
  Linux pinned stdlib) + signed commit. Smoke PS twin now file-redirects
  server output and reads exit codes through cmd (pipe-deadlock +
  empty-ExitCode traps fixed); `check()` needles are wildcard-escaped.
- **Compiler relay received (2026-10-09, `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md`):**
  **v0.64.2 is release-ready, tag held for the owner.** Fixes in batch:
  C-PULSE-09 (m223..m227; re-run `probe_adopt_smoke` on the archive),
  C-PULSE-13 (m232 installer home unified -- test dropping the bridge!),
  C-PULSE-11, plus m228/m231/m234/m239. **Not** in this batch: the BIND
  primitive (C-PULSE-16) and the darwin blockers -- macOS stays gated.
  On publish: install both platforms, re-run the probe fleet + suites +
  smoke, retest C-PULSE-14 soaks (m235 still the candidate), and drop
  obsolete workarounds (C-PULSE-13 bridge if m232 holds), then cut the
  next release (0.1.1) per the standing routine.
- **Website lane relayed Phase-2 readiness (2026-10-09); PULSE reply
  filed** (`docs/WEBSITE-RELAY-PULSE.md` section 9): endpoint/binding
  facts, release naming (`pulse-v0.1.0`, `pulse-<ver>-<os>-<arch>.zip`),
  claim deltas (smoke 78/78; no memory/long-uptime claims on any OS),
  badge fetch approved (same-origin); **greenlight is owner-only**.
  `PULSE_CORS_ORIGIN` is now a comma-separated allowlist (verified both
  platforms) for the pulse-origin + hub-embed case.
- **Showcase/site (owner decisions 2026-10-08):** `pulse.xiom-lang.org`
  DNS is live (no staging subdomain needed); `orbitdb.`/`xvector.` pages
  later (DNS records exist). Phase 1: the **website lane** owns the
  marketing pages (`docs/WEBSITE-RELAY-PULSE.md` = brief + paste prompt);
  PULSE owns the product UI (`PULSE_LANDING_PATH`/`PULSE_ASSETS_DIR`) and
  claim review; ops owns infra. On greenlight: GH Actions release -> repo
  public + `main` rulesets -> dl publish -> ops deploys the demo. Cover
  image lands at `resources/img/` (owner drops it; PULSE wires the
  landing).
- **v0.64.1 known-issue cautions (from the notes):** `from_utf8` by-ref
  (pass by value), optional-into-vector-element assignment, nested-field
  mutation copies -- designs avoid all three.
- **Capabilities landed 2026-10-07/08:** 12 `.ps1`+`.sh` twins (all
  verified; PS exe defaults aligned to `out\pulse_app.exe` in wrap 3 --
  one stale default had hung a smoke run), registry wave
  (metrics/static/middleware adopted), stdlib
  `write_all` + `server_parse_request` adopted, TE smuggling guard,
  Expect/Date protocol fix, schema helper, audit rotation,
  `--version`/`--check-config`, showcase `/assets` + `PULSE_LANDING_PATH`,
  `PULSE_BIND`, Dockerfile, release + backup tooling; **v0.64.1 adoption
  complete on both platforms** (Linux sweep green, incl. the 20m kv soak);
  ops answered (staging parked; Linux toolchain pin v0.64.1 recorded; CI
  on greenlight).
- **Score:** ~55.4% production grade (`docs/PROGRESS.md`).
- **NEXT (in order):** 1) the **session-store swap retry** (bridge
  `220f814`) -- now unblocked on both platforms (C-PULSE-09 closed on
  v0.64.2: fleet 11/11, adopt_smoke green both); after it, cut 0.1.1
  (v0.64.2 pins already in the workflows; macOS stays gated). 2) watch
  the lanes: compiler (C-PULSE-16 address-aware bind; darwin
  runtime/codegen blockers; C-PULSE-12 alias ask), bindings (DB/KV
  binding, store seam). 3) non-blocked hardening: chunked RESPONSES
  (with keep-alive), a fresh 30-60m soak, or the longer kv soak for the
  flip gate; **C-PULSE-14 Linux memory retest on the next archive**
  (Windows flat on v0.64.2). 4) kv default flip only after the recorded
  prerequisites; otherwise keep kv opt-in. 5) release ops: pulse-v0.1.0
  live (demo + dl + docs verified); wire the owner's cover image
  (`resources/img/`) into the product landing when it lands.
- **Gotchas:** PS 5.1 strips embedded quotes in native args (use files,
  `--etag-save/--etag-compare`); when driving WSL from PS avoid inner
  quotes (write scripts to `/tmp` instead); `io.flush_stdout` is a no-op
  (durable step logs); no inline if-expressions; module last-segment
  collisions shadow imports (C-PULSE-12); no module-scope package
  constructors (Vec-holder pattern); **C-PULSE-13 is CLOSED (m232): no
  bridge -- `xiom pkg` resolves the compiler home; after any toolchain
  maintenance verify the store (`xiom doctor`; re-add with `xiom pkg
  install` -- a concurrent re-extract can wipe `packages/`)**;
  `wsl --shutdown` clears CLR/paging errors (system commit pressure, not
  the build); **version bumps: update EVERY expected-version literal --
  `src/pulse.xi`, `src/server.xi` APP_VERSION, `src/http.xi` Server
  header (x2), `tests/test_smoke.xi`, `tests/test_http.xi`,
  `scripts/http_smoke.{sh,ps1}` -- and run the suites with the pinned
  stdlib before tagging (CI parity; a stale literal cost the 0.1.1
  tag).** The openapi version assertion in `tests/test_app.xi` is part
  of that set.

### Session log 2026-10-07/08 (chronological history; superseded by the digest above)

- **Repo:** unchanged (`E:\xiom-projects\xiom-pulse`, private, no push
  without owner approval). Commits this session: `b58f7a8` (bash twins +
  Linux build path + m212 repro), `220f814` (registry wave adoptions +
  findings), plus this docs wrap.
- **Toolchain (owner policy: track latest):**
  - Windows: compiler v0.64.0 (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`),
    stdlib `E:\xiom-lang\stdlib`, `XIOM_RUNTIME_DIR` retired.
  - **Linux (NEW, verified):** WSL Ubuntu compiler v0.64.0 at the
    canonical Unix install (`~/.local/share/xiom`, `xiom` on PATH);
    stdlib from `XIOM_STDLIB=/mnt/e/xiom-lang/stdlib` when present, else
    the compiler's bundled tree; registry packages live in
    `~/xiom/packages` (legacy home) and install from the live registry
    (reachable from WSL, signatures verified).
- **Linux binary:** `out/pulse_app` (native x86-64 ELF, 609 KiB) built by
  `scripts/build.sh`; full runtime green.
- **WINDOWS SESSION MUST-DO:** the app now imports `xiom.metrics`,
  `xiom.static`, `xiom.http.middleware`; install them on Windows first:
  `xiom pkg install xiom.metrics@0.2.0 xiom.http.middleware@0.1.0
  xiom.static@0.1.0` (then suites x2 + smoke to re-verify Windows).
  Windows source-roots for the wave are already staged in `xiom.toml`.
- **Green evidence this session (Linux/WSL):** 12 `.sh` twins verified
  (run hello + crypto KAT, 3 binaries built, smoke 61/61, concurrent
  64/64, soak_tcp 25/25, crash 6/6, rate smoke, store_soak 20s, soak_http
  20s, proxy_e2e 11/11 via nginx 1.24 TLS); on the adopted binary: suites
  x2 all 0 failures, smoke 61/61, crash/rate/store-soak/proxy-E2E green;
  probes green: metrics, middleware, session (package surface), static,
  state-holder, adopt-smoke, session-inline.
- **Registry wave status:** `xiom.metrics` 0.2.0 -> `src/metrics.xi`
  (labeled counters + latency preset + exposition); `xiom.static` 0.1.0 ->
  favicon route (mime/ETag/Cache-Control/304/Range/traversal-guard);
  `xiom.http.middleware` 0.1.0 -> CSRF + CORS. `xiom.session` 0.1.0 store
  integration DEFERRED (C-PULSE-09 crash via wrapper modules; inline
  green; local store retained). `xiom.kv` 0.1.0 BLOCKED (C-PULSE-10
  kv_get corruption; JSONL fallback stays; `probe_pkg_kv` is the
  known-red gate).
- **New findings (details in relay docs):** C-PULSE-08 (m212 dotted-key
  latent, repro `docs/repro/dep-roots-name-form`), C-PULSE-09 (session
  store integration crash), C-PULSE-10 (kv_get corruption; classification
  open), C-PULSE-11 (`pub type X = PackageType` invisible cross-module ->
  "defaulting to i64" warning), C-PULSE-12 (module last-segment shadows an
  imported stdlib alias; renamed the app module).
- **Ops relay updated:** `docs/OPS-REQUEST.md` now carries the Linux
  evidence (VPS OS question resolved: Linux is fine) and the WSL-vs-Docker
  guidance for staging rehearsal.
- **2026-10-08 continuation:** **Windows re-verify GREEN** -- wave
  packages installed on Windows (`xiom pkg install xiom.metrics@0.2.0
  xiom.http.middleware@0.1.0 xiom.static@0.1.0`), then build + suites x2
  + smoke 61/61 + crash 6/6 + rate smoke all green on
  `out\pulse_app.exe`. **Stdlib wishlist delivered and adopted**:
  `TcpStream.write_all` replaces PULSE's send loop; the shared
  `xiom.net.server.server_parse_request` backs `http.parse_request`
  (PULSE caps preserved: 16 KiB guard, 100-header cap, trimmed values;
  invalid Content-Length now rejected); parity pinned by
  `tests/probes/probe_stdlib_server_parse.xi` (12 checks, both
  platforms). **Module renamed** `xiom.pulse.server` -> `xiom.pulse.app`
  (C-PULSE-12: a last-segment name shadows an imported stdlib alias --
  `server.` calls broke until the rename). Ops answered the relay
  (docs/OPS-REQUEST.md section D): staging is parked by owner decision;
  Linux toolchain source pinned at dl (`xiom-v0.64.0-linux-x64.tar.gz`,
  SHA256SUMS, immutable pins); CI mechanics specified for greenlight.
- **Env note (2026-10-08):** the Windows box hit pagefile/commit
  exhaustion mid-session (PowerShell/WSL errors: "paging file is too
  small", "Starting the CLR failed", UTF-16 mangled interop output); a
  `wsl --shutdown` cleared it before the RAM bump + restart. If WSL
  commands return CLR/paging errors, suspect system commit pressure, not
  the build. PULSE's own footprint is small (single clang compiles, tiny
  test servers); Docker Desktop + WSL VMs dominate.
- **2026-10-08 (later):** audit rotation landed (`src/audit.xi`,
  `PULSE_AUDIT_MAX_BYTES` default 5 MB, probe 6/6 + app-level E2E on
  Linux); CLI `--version`/`--help` and `/api/version` commit/build fields
  (runtime `PULSE_BUILD_COMMIT`/`PULSE_BUILD_DATE` until a compiler
  define flag exists -- filed). Both platforms re-verified green.
  Blocked-work survey: `xiom.os.signal` has no handler-install API ->
  SIGTERM graceful stop stays blocked (stdlib wishlist filed); keep-alive
  stays gated on recv timeouts (`socket_set_timeout` stub) because one
  idle keep-alive client would stall the single-threaded loop. Next
  unblocked M4 item: schema helper.
- **2026-10-08 (schema close-out):** `src/schema.xi` landed (typed
  rule-list validator: required/optional, length + numeric bounds,
  first-failure code/field/message) and routes 4/7/8 use it with
  field-specific 400s (probe_schema 14/14); the flaky JWT tamper check is
  fixed (append a char -- replacing the last base64url char can decode to
  identical bytes; one Windows run flaked). Unblocked M4/M5 work is now
  exhausted: keep-alive / recv timeouts / signals wait on stdlib
  capabilities (filed), CI / packaging / true build stamping wait on the
  public greenlight (ops mechanics ready).
- **2026-10-08 (packaging round):** TE/chunked smuggling guard (any
  `Transfer-Encoding` -> 501; CL.TE desync closed; test_app 105 checks +
  smoke 62/62), status table completed (206/304/501... had rendered
  "Unknown"), `scripts/release.{ps1,sh}` (dist artifacts per the ops
  naming, zip + sha256 verified on both platforms) and
  `scripts/backup.{ps1,sh}` (timestamped store+audit snapshots with
  sha256 manifest + prune; tested; restore runbook in DEPLOYMENT §9).
  Compiler check: dl still v0.64.0; **m215/m216/m217 (C-PULSE-08/10/11
  fixes) are in the lane source, not in an archive** -- v0.64.1 is the
  next adoption gate; C-PULSE-09 was triaged not-reproducible from
  committed sources (PULSE will retry the session-store swap on the next
  archive using the arrangement in git history 220f814).
- **2026-10-08 (pre-flight round):** `--check-config` CLI (effective
  config dump; exits 1 only on an unreadable configured file; never
  prints the secret -- flags dev-default vs env) + smoke pre-flight
  checks (`--version`/`--check-config` before start; 66 checks). Suites
  x2 + smoke green on both platforms. **Lane map:** a dedicated
  **bindings lane** (`E:\xiom-packages\bindings`, worktree of the
  packages lane) now builds binding packages; PULSE files binding
  requests via the packages lane and keeps the seam map in PROGRESS
  ("Integration seams for future bindings").
- **2026-10-08 (showcase round):** general `/assets/<path>` serving
  (`PULSE_ASSETS_DIR`, same ETag/304/Range/traversal machinery) +
  `PULSE_LANDING_PATH` per-site landing content + `PULSE_BIND` (loopback
  default; containers set 0.0.0.0) + `deploy/Dockerfile` (build verified,
  container E2E: health/version/assets). Smoke 71/71 on both platforms.
  These are the PULSE-side prerequisites for the planned
  `pulse.xiom-lang.org` / `orbit.` / `xvector.` showcase sites (one
  binary + per-site env; honest beta framing) and for the offline
  benchmark harness after release. Owner plan discussed this wrap; ops
  side unchanged (staging parked; one nginx site per subdomain when
  greenlit).
- **2026-10-08 (protocol round):** `Expect: 100-continue` (interim before
  the body; raw-socket proof) and the `Date` response header landed;
  test_http +4, smoke 73/73 both platforms. Owner plan agreed: adopt the
  next compiler/stdlib/package release, sweep bugs/blockers against it
  (C-PULSE-08/09/10/11 gates ready), then coordinate ops for the three
  showcase sites; non-blocked hardening continues until then.
- **2026-10-08 (v0.64.1 sweep):** the installed Windows toolchain was
  updated in place to **v0.64.1**; the package store was wiped by that
  maintenance and all ten deps were reinstalled. **C-PULSE-08 CLOSED**
  (m212 gate: dash + dot both exit 0, no source-roots), **C-PULSE-10
  CLOSED** (kv probe GREEN; kv_get returns the stored text), C-PULSE-11
  alias fix confirmed by the release notes. Full regression on v0.64.1:
  suites x2 + smoke 73/73 + crash 6/6 + rate, all green. **NEW finding:**
  v0.64.1's extern-unsafe enforcement breaks the published `xiom.http`
  0.1.1 (67 T001s) -- PULSE pruned the already-unused package
  (`probe_pkg_http` is the known-red republish gate; the packages lane
  owns the fix). **Session-store swap retried on v0.64.1:** now compiles,
  but still crashes (0xC0000005) at the first cross-module access to the
  module-level `Vec[SessionStore]` (C-PULSE-09 stays OPEN; durable step
  evidence in `probe_adopt_smoke` via `pulse-adopt-steps.txt`; local
  store stands). **kv backend adopted (opt-in):** `PULSE_STORE_BACKEND=kv`
  (+ `PULSE_KV_DIR`/`PULSE_KV_PREFIX`) routes the event store through
  `xiom.kv` behind the same API; verified on v0.64.1 (smoke 73/73 through
  kv, store-soak 20s kv green, default jsonl smoke 73/73 regression).
  Next: Linux-side sweep when dl publishes v0.64.1, then ops on
  greenlight.
- **Next action:** session-store swap retry with the alias design (m216
  fix; keep the local store until suites pass), kv backend adoption
  behind the same store API, Linux-side probe sweep + suites when dl
  publishes v0.64.1, adopt socket timeouts / signals / define flag when
  the stdlib exposes them, watch the bindings lane for the durable DB/KV
  binding (store seam, PROGRESS 6b); when the owner greenlights: CI file
  + dl release flow + the three showcase sites (ops mechanics in
  docs/OPS-REQUEST.md).

## 0b. STATE HISTORY (2026-10-05) -- superseded

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
- **Last green slice:** **through-proxy TLS E2E GREEN 11/11** on
  `out\pulse_app_v9.exe`: nginx 1.28.3 terminates TLS (self-signed cert
  via Git-OpenSSL) on 127.0.0.1:8443 -> PULSE :18091; verified health,
  HSTS, `Server: nginx` with no upstream token leak, POST bodies, metrics,
  404+rid. Script `scripts\proxy_e2e.ps1`; production example
  `deploy\nginx\pulse.conf.example`. Before it: wave 6 (config file,
  events `?kind=`, 10m store soak 841/841/841 GREEN) and wave 5
  (compaction, `?limit`, rid, gauges).
- **Registry wave ready to wire (owner relay 2026-10-07):** all published
  and signature-verified: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.metrics` 0.2.0, `xiom.router` 0.1.0,
  `xiom.http.middleware` 0.1.0, `xiom.session` 0.1.0, `xiom.static`
  0.1.0, `xiom.kv` 0.1.0.
- **Pipeline-hang lesson (cost the owner hours):** launching a detached
  child (nginx) with inherited stdout/stderr pipes makes the caller wait
  on the pipe forever, past any process timeout. Always `Start-Process`
  with file redirection, poll readiness with a bounded socket connect,
  and kill by PID tree.
- **Next action (owner-ordered):** FIRST port every script to a `.sh`
  twin (dev-env, run, build, smoke, soak, concurrent, crash, rate,
  store, proxy-e2e) so Linux developers can use them; THEN adopt the
  registry wave (`xiom.metrics` 0.2.0 labels/latency preset,
  `xiom.http.middleware`, `xiom.session`, `xiom.static` for the favicon/
  landing, `xiom.kv` as the durable store replacement); continue M4/M5
  hardening per `docs/PROGRESS.md`.
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

## 3 (superseded by the handoff prompt at the top). Paste prompt (2026-10-22 wrap 24 earlier draft)

```
You are the PULSE lane for E:\xiom-projects\xiom-pulse (the official
XIOM web backend / multipurpose framework). Read SESSION.md first -- the
WRAP 24 digest at the top is authoritative (the WRAP 23/22/21 digests sit
below it); then docs\PROGRESS.md,
docs\PRODUCTION-REFERENCES.md, docs\PRODUCTION-GAPS.md, docs\ROADMAP-
TOP-TIER.md and the unit design docs. Relays: E:\xiom-lang\xiom-relays.
Reference shelf: E:\repos (PULSE web set is MIT; xlcaptain has no LICENSE).

RE-ARM YOUR DOORBELL FIRST (crons are session-scoped): every 2h with the
standard sweep (git fetch + merge --ff-only, never `git pull`; view
--lane pulse; process items; wrap on change). Then continue the queue.

STATE AT WRAP 24 (2026-10-22):
- **WRAP 24 STATE:** compiler **v0.64.8** production (v0.64.9
  WITHDRAWN; v0.65.0 gate open) + **stdlib-v0.64.9 (`aa8b656`)**;
  **user StreamHandler registry reverted** (`5a927d3`; returns with a
  fixed archive); **macOS x64 gating** with the stdlib `list_dir` fix.
  `REL-20261021-0717-pulse` / `REL-20261022-1529-pulse` keep
  22.04/macOS arm64 non-gating; 24.04 arm64 gating. CI `39815111372`
  green on four gating legs; release dry-run `39816871164` green on
  linux-x64/linux-arm64/windows-x64. Re-run both on the fixed compiler.
- `main = db91d2c` at the WRAP 21 start (historical).
  CI: every run below is green on BOTH platforms where noted.
- **PULSE 0.2.2 RELEASED**: tag `pulse-v0.2.2` (3b515c6), release run
  `39304832557` SUCCESS; linux/windows artifacts + SHA256SUMS; **ops
  CLOSED REL-20261017-1141-ops -- dogfood accepted after the retest**.
- **Toolchain: XIOM v0.64.8 + stdlib `112c5b6`** (Windows
  %LOCALAPPDATA%\xiom.new-v0.64.8; WSL ~/.local/share/xiom-v0648;
  stdlib-tag dirs both sides; STDLIB_VERSION + all three workflow pins).
- **Beacon xiom.pulse 0.3.1** consumed (stateful HookCtx, kind-0 fallback,
  HEAD-as-GET, Server token `xiom-pulse-station/0.2.2`); deps latest
  (xiom.sqlite 0.4.1 wired).
- **Middleware Phase A COMPLETE**: read / gate_request (0-3) /
  build_dispatch_response (4-6) / after_response (7); gate_order.py 11/11.
- **Phase B PARKED on compiler m371** (imported-struct identity/field
  access breaks hooks/serve_with_ctx); m371 is explicitly deferred to the
  cycle AFTER v0.64.8. The legacy loop stays; package seams are complete
  (0.3.1). Do not fork the limiter.
- **SQL class MVP COMPLETE**: `src/migrations.xi` + `pulse_migrate`
  (status/up/down/backup/create), tracking + single-row lock, stale
  takeover, per-migration transactions, `-- pulse:up/-- pulse:down`
  markers, UTC stubs, applied-but-missing policy, backup fence
  (VACUUM INTO + manifest, PULSE_SQL_BACKUP_MANIFEST, --no-backup-check),
  per-migration heartbeat. tests/test_migrations.xi 21/21, CI gates green.
- **SQL STORE/REPOSITORY LAYER LANDED (session 22):** `src/sql.xi`
  (`xiom.pulse.station.sql`) -- integer handles, mandatory value binding,
  identifier validation, JSON rows, repository CRUD + `limit+1` paging,
  transactions; `tests/test_sql.xi` **53/53 Windows + WSL**; CI Linux
  gate; **not imported by the serving binary** (builds green without the
  C source). Design: `docs/DESIGN-SQL-STORE.md`. `main = 1fcd1a3`;
  **CI `39328272067` GREEN both platforms**.
- **PER-ROUTE RATE POLICY LANDED (session 22, W6):**
  `PULSE_RATE_ROUTES` (`METHOD PATH=RATE[/BURST],...`; `*` method; route
  template PATH) on top of the global bucket; invalid entries named by
  `cfg_validate`/`--check-config`/startup; `rate_smoke` proves
  200/429/refill on both platforms. `main = cf42333`;
  **CI `39332690326` GREEN both platforms**.
- **BENCH BASELINE PUBLISHED (session 22):** `benchmarks/bttger/` (six
  endpoints on Beacon + adapted MIT autocannon driver); Windows c1 clean
  -- 454.6/78.1/384.6/142.9/172.4/50.0 req/s, zero errors; c10 adds no
  throughput and times out the waiting connections (W1 sequential-accept
  ceiling). Report + raw JSON committed. `main = 9b97eb7`;
  **CI `39335266242` GREEN both platforms**, benchmark-app build gate
  included.
- **REALTIME UNITS LANDED (session 23, W4):** `src/stream.xi`
  (`/api/sse` chunked event stream + `/api/ws` RFC 6455 echo) after the
  frozen gate; 37/37 pure + 15/15 live on both platforms; router surface
  unchanged; user stream handlers and WS auth are follow-ups (Origin +
  fragmentation + startup registry landed).
  `main = c062a58`; **CI `39427518984` GREEN both platforms**.
- **LINUX-ARM64 CI LEG (session 23):** native `ubuntu-24.04-arm` in the
  matrix; arm64 toolchain pin + clang check + ELF verify; full gates
  native. `main = 8cf4992`; **CI `39560182609` GREEN on all three
  platforms**. The 22.04/clang-14 build exposed a compiler codegen bug
  (`REL-20261021-0717-pulse`); 24.04 passes.
- **macOS WITNESS (session 23):** `macos-14` + `macos-15-intel` added
  **non-gating**. x64 is fully green with stdlib **05673f8** (pre-pin):
  witness rc 0, migrations 21/21, SQL 53/53, stream/suites/smoke;
  `REL-20261021-0918-pulse` verified. arm64 is still blocked by
  `REL-20261021-0717-pulse` (fixed on compiler main, not in the pin).
  `main = 28abfb1`; CI `39624153094` overall success (x64 green, arm64
  red on 0717). macOS release assets remain behind `RELEASE_BUILD_MACOS`.
- **LINUX-ARM64 RELEASE DRY-RUN (session 23):** release matrix includes
  `linux-arm64` on `ubuntu-24.04-arm`; dry-run `39588855890` green on
  linux-x64/linux-arm64/windows-x64 (full fleet + package + provenance).
  Next tag ships `pulse-<ver>-linux-arm64.zip`; macOS remains opt-in.
- Current gates on **compiler v0.64.8 + stdlib-v0.64.9**: suites x2
  (95/239/4), smoke 135/135 x2 (jsonl+kv), crash x2 on linux-x64,
  linux-arm64 (24.04), windows-x64 and macOS x64; migrations 21/21, SQL
  store 53/53, stream 57/57 + live 20/20; rate smoke, benchmark-app
  build, sqlite probe. macOS arm64 is non-gating (0717/1529).

NEXT -- queue (dependency order):
1. **Phase B when compiler m371 lands**: re-apply the stateful pre/after
   hooks + serve_with_ctx behind the legacy fallback; the earlier
   implementation is in git history and DESIGN-MIDDLEWARE-JOBS. Still
   blocked on the compiler lane.
2. **Release 0.3.0**: the serving SQL surface is **decided as an opt-in
   application library; stock `pulse_app` stays SQL-free**
   (`docs/DESIGN-SQL-SERVING.md`). Owner approval is the remaining gate;
   then bump src/version.xi + APP_VERSION + package.xi, CHANGELOG, tag
   `pulse-v*` (guard: tag == version, ancestor of main), watch the
   release fleet, ping ops for dogfood.
3. Platform: **linux-arm64 CI + release dry-run done (2026-10-21)**;
   the next tag ships three assets. macOS x64 is green with stdlib
   05673f8 (pre-pin); the next stdlib pin removes the override and makes
   x64 gating. arm64 waits on a tagged compiler with 0717; then add the
   macOS assets. `REL-20261010-1609-stdlib` (Windows inline payload) is
   separate. A background heartbeat for a single very long migration.
4. Follow-up bench work: Linux leg + the full 1M-request bttger amount
   (the baseline report explains why the reduced run was used); the
   xlcaptain scenarios. **Blocked on `REL-20261020-1704-pulse`** (stdlib
   JSON builder leak); run only under the 2 GB cap.
5. Realtime follow-ups: user-supplied stream handlers are **fixed on
   compiler main `c9b1f1009`** (verified locally); restore the registry
   on the next tagged compiler. The startup registry + built-in kinds are
   landed. Permessage-deflate and authentication before user data on
   `/api/ws` remain (Origin guard and fragmentation are landed).

OPEN OBLIGATIONS / RELAYS: compiler m371 (`REL-20261019-1309-pulse`,
next cycle); **stdlib JSON path leak (`REL-20261020-1704-pulse`,
acked)** -- in-place builders 526fd96 tested on stdlib main 0bf5984:
500 iterations complete, 512 MB crossed at ~1,000-1,200 (vs ~500 for
json_set); residual m375; builder API is not in the v0.64.8 pin, so
Linux/1M bench stays blocked. **arm64 module-scope Vec codegen
(`REL-20261021-0717-pulse`, fixed at aecad8c6c)** -- local debug build
emits the GEP load; re-test the 22.04 arm64 leg and macOS arm64 on the
next tagged compiler. **macOS `list_dir`
(`REL-20261021-0918-pulse`, VERIFIED fixed 05673f8)** -- the stdlib
witness passes on macos-15-intel and migrations 21/21 with the fix; the
fix is on main and lands in the next pin, then x64 becomes gating.
**Windows inline payload index (`REL-20261010-1609-stdlib`, acked,
high)** -- our print probe hits the known compiler inline
`Result.value[i]` concat bug; separate from the macOS fix.
**Stored function values (`REL-20261021-1703-pulse`, VERIFIED fixed
`c9b1f1009`)** -- local debug HEAD verifies `probe_fnptr` and the exact
`StreamHandler` shape; restore the user handler registry on the next
tagged compiler. Pinned v0.64.8 still cannot build it.
registry 3.0 pilot gate ping when production-serving
(`REL-20261013-1707-registry`); no open PULSE ops items (1141 closed).
**RELAY BUS NOTE (2026-10-20):** `items/REL-20261020-2355-owner.md`
(owner -> engine) has no front matter and makes `relay.py view` raise
`missing front matter`; use `relay.py show <id>` or grep item files until
the engine normalizes it. Do not edit another lane's item.
Check the relay first every session -- packages/compiler move fast.

POST-v0.64.9-WITHDRAWAL STATE (2026-10-22):
1. **Compiler v0.64.9 is WITHDRAWN** (`REL-20261022-1826-compiler`);
   production pin remains **v0.64.8**. Stdlib-v0.64.9 (`aa8b656`) is kept
   as the package pin (it pins compiler v0.64.8 and carries the list_dir
   fix/builders); v0.65.0 will pin stdlib-v0.65.0. The user StreamHandler
   registry is reverted (`5a927d3`).
2. **v0.65.0 is the next production target** (P0 correctness incl. nested
   patterns/1451/1550, then production hardening, then MCU; no candidate
   before the gate is green + owner GO). Re-test on the v0.65.0 archive:
   `probe_arm64_ginit`, `probe_fnptr`, `probe_stream_handler`,
   `p_io_listdir_roundtrip`, migrations 21/21, then restore the registry,
   make 22.04/macOS arm64 gating, enable macOS packaging. Holds
   `REL-20261021-0717-pulse`, `REL-20261022-1529-pulse` are acceptance
   input.
3. **JSON/bench:** stdlib v0.64.9 builders are in; on v0.64.8 the m375
   residual remains, the legacy `json_set` path still grows, and bttger
   `/insert` over HTTP hit 2GB while the standalone insert loop is flat.
   Investigate the PULSE request/response lifecycle before any Linux/1M
   run; never uncapped.
4. Release 0.3.0: owner approval is the only gate (SQL serving decision
   is proposed in `docs/DESIGN-SQL-SERVING.md`); use compiler v0.64.8 +
   stdlib-v0.64.9, bump the literals, tag, watch the fleet, ping ops.

DISCIPLINE: OWNER DIRECTIVE (2026-10-20) -- every manual or long app run
on the workstation goes through `scripts\capped_app.ps1` /
`scripts\capped_app.sh` (default **2048 MB RSS**, `PULSE_MAX_RSS_MB`
override; the watchdog kills the tree at the cap, exit 137). Never run the
1M benchmark or a soak uncapped. CI runners are isolated; short smoke
scripts are bounded. Always the LATEST compiler, stdlib and
registry packages. Pinned local builds: Windows
%LOCALAPPDATA%\xiom.new-v0.64.8 + xiom-pins\stdlib-tag-v0.64.8; WSL
~/.local/share/xiom-v0648 + ~/.cache/xiom-pin/stdlib-tag-v0.64.8 (refresh
on a new release). Reference-Study Protocol binding (docs\
REFERENCE-STUDY-PROTOCOL.md): cite the matrix, no design from memory,
blockers relay first and test back on the next release. Gates before any
done claim: suites x2 + smoke 135/135 x2 + crash x2 on linux-x64,
linux-arm64 and windows-x64;
rate smoke (global + per-route); stream 57/57 + live 20/20; SQL store
53/53 + migrations 21/21; SQL builds pass the vendored sqlite C
source ONLY for entries importing xiom.sqlite, the migrations module or
the SQL store module. Signed conventional commits; commit/push per unit;
update SESSION + docs/PROGRESS at every wrap.
```

## 3 (superseded, wrap 20). Paste prompt for the next PULSE session (2026-10-17 wrap 20)

```
You are the PULSE lane for E:\xiom-projects\xiom-pulse (the official
XIOM web backend / full backend framework). Read SESSION.md first -- the
CURRENT STATE digest at the top is authoritative; then docs\PROGRESS.md,
docs\PRODUCTION-REFERENCES.md, docs\PRODUCTION-GAPS.md and your designs
(docs\DESIGN-*.md). Relays: E:\xiom-lang\xiom-relays. Reference shelf:
E:\repos\.

RE-ARM YOUR DOORBELL FIRST (crons are session-scoped): every 2h with the
standard sweep prompt (pull the relays; view --lane pulse; process items;
wrap on change). Use `python tools/relay.py` in the relays clone; NEVER
`git pull` there; never edit another lane's item.

STATE AT WRAP 20 (2026-10-17):
- **`main = 1b13922`** (the 2a commit; pushed), CI dry run
  `39035806578` GREEN on both platforms (ubuntu 3m44s, windows 4m4s);
  this wrap commit follows. Relays: pull at boot (the site-mode fix ack +
  the 2a result are filed there).
- **STATION-CONSUMES 2a GREEN:** product modules are
  `xiom.pulse.station.{app,config,router,version}` (18 imports / 10
  files); the byte-identical `http`/`envelope`/`reqctx`/root modules are
  deleted (SHA256 re-verified against the installed package);
  `src/version.xi` is the product version source (release scripts, tag
  guard, test_smoke); `"xiom.pulse" = "0.1.0"` is declared in both
  manifests + the CI installer. Gates on BOTH platforms: suites x2
  (test_http 77, test_app 237, test_smoke 4, rc=0), smoke 134/134 x2
  (jsonl + kv), crash x2 GREEN (`probe-logs/station-consumes-2a/`,
  local); CI dry run `39035806578` green on both platforms.
- **TOOLCHAIN: v0.64.8 + stdlib release tag `112c5b6`** adopted 2026-10-19
  locally AND in `STDLIB_VERSION` + ci/heavy/release pin blocks (v0.64.8
  SHA256 set). **Latest registry deps** per owner directive 2026-10-17:
  xiom.pulse 0.3.1, xiom.http 0.1.8, xiom.cookie 0.1.2, xiom.jwt 0.2.1
  (the rest already latest). Always consume the newest fixes. m371
  (imported-struct layout) remains the Phase B compiler gate.
- **OPS: site-mode duplicate `Content-Length` FIXED**
  (`REL-20261017-1141-ops`): the static engine's CL is dropped and
  `http.build_response_bytes()` owns framing; live 200 + 304 responses
  carry exactly one CL, and the suite locks it. Ops re-tests the
  xiom-lang.org dogfood switch on the next cut (0.2.2).
- Beacon (xiom.pulse 0.1.0) PUBLISHED + acceptance stage 1 GREEN;
  packages hook seam acked (`REL-20261017-1123-pulse-2`, implementation
  dispatched now) -- **stage 2b stays GATED on that publish** +
  the middleware chain. The package's carved `Server: xiom-pulse/0.2.1`
  literal is package-owned (finding C in the design) -- ask packages to
  parameterize/neutralize it in 0.2.0.
- Reference-study protocol BINDING (`docs/REFERENCE-STUDY-PROTOCOL.md`).
- Open obligations: compiler resolver-policy answer
  (`REL-20261017-1123-pulse`, still open), ops shared-home clobber flag
  (`-3`), 0.2.2 cut.

NEXT -- queue (dependency order):
1. **Middleware chain (item 3):** order tests FIRST, then the chain
   refactor, then the jobs core (`docs\DESIGN-MIDDLEWARE-JOBS.md`;
   matrix extracted from gin/fastify/bullmq -- nine stages, sent-guard,
   precomputed tables; do not re-invent).
2. **Stage 2b**: full loop/router/config adoption, gated on the packages
   hook-seam publish; test the seam back on the next package publish
   (`REL-20261017-1123-pulse-2`).
3. **v0.64.7 darwin/pin suites + linux-arm64**: Windows + Linux x64 are
   adopted locally; the macOS legs run through the release/CI path
   (`RELEASE_BUILD_MACOS`) and the new **linux-arm64** archive needs an
   arm64 CI leg before the top-tier platform claim -- the compiler lane
   asked for the new-archive re-verify (`REL-20261017-2259-compiler`).
4. **0.2.2 RELEASED** (tag `pulse-v0.2.2`): watch the ops dogfood
   retest and close `REL-20261017-1141-ops`; then prep the next cut.
   Version literals start at `src/version.xi` (+ APP_VERSION).
5. SQL class: migrations runner per docs\DESIGN-SQL-MIGRATIONS.md (wire
   xiom.sqlite into package.xi + the CI install list when the unit
   opens; the SQL driver artifact is co-verified green).
6. Bench baseline (six bttger endpoints; E:\repos\
   web-framework-benchmarks + -xlcaptain), SSE + WebSocket units,
   per-route rate policy, OpenAPI paths-generation remainder,
   test-runner harness.
7. Registry pilot gate ping when production-serving
   (REL-20261013-1707); game CP follow-ups via REL-20261013-1701-pulse.
8. Watch the ops redeploy (demo -> 0.2.1/0.2.2) + the website
   `latest.json` follow; note the dl mirror timing (:17).
9. Open obligations/test-backs: compiler resolver answer; packages 0.2
   hook seam + version-header seam; ops clobber flag. **Doorbell re-arm
   = first action of the session.**

DISCIPLINE: OWNER DIRECTIVE 2026-10-17 -- always use the LATEST compiler,
stdlib and registry packages (fixes land there; PULSE is the hardening
consumer). Local builds: Windows `%LOCALAPPDATA%\xiom.new-v0.64.8` +
`%LOCALAPPDATA%\xiom-pins\stdlib-tag-v0.64.8`; WSL
`~/.local/share/xiom-v0648/bin/xiom` +
`~/.cache/xiom-pin/stdlib-tag-v0.64.8` (refresh the versioned dirs on the
next release; `dev-env` prefers them). Suites x2 + smoke 135/135 x2 + crash x2 on both
platforms; signed conventional commits; bus sweep before finishing any
task; wrap at every stopping point (SESSION.md digest + docs\PROGRESS.md).
**REFERENCE-STUDY PROTOCOL (owner 2026-10-17) binding:** every unit cites
its reference matrix; blockers relay first and are tested back on the
next release/publish.
```

## 3 (superseded, wrap 19). Paste prompt for the next PULSE session (2026-10-17 wrap 19)

```
You are the PULSE lane for E:\xiom-projects\xiom-pulse (the official
XIOM web backend / full backend framework). Read SESSION.md first -- the
CURRENT STATE digest at the top is authoritative; then docs\PROGRESS.md,
docs\PRODUCTION-REFERENCES.md, docs\PRODUCTION-GAPS.md and your designs
(docs\DESIGN-*.md). Relays: E:\xiom-lang\xiom-relays. Reference shelf:
E:\repos\.

RE-ARM YOUR DOORBELL FIRST (crons are session-scoped): every 2h with the
standard sweep prompt (fetch+merge --ff-only relays; view --lane pulse;
process items; wrap on change). Use `python tools/relay.py` in the
relays clone; NEVER `git pull` there; never edit another lane's item.

STATE AT WRAP 19 (2026-10-17, session 19 closed at context limit):
- **`main = b70d681`**, clean + pushed. Relays last push `95c4981`.
- **Beacon PUBLISHED:** `xiom.pulse` 0.1.0 LIVE in eco-v0.1.192
  (sha256 `53fcc56e...`; publish close `REL-20261016-1810-packages-3`,
  acked with the acceptance result). Acceptance stage 1 GREEN on the
  installed artifact: checksum + signature verified on both stores,
  carved suite 125/125 x2 both platforms, `minimal.xi` live x2
  (`docs/repro/beacon-acceptance/`). NOTE: the Windows package home was
  reset overnight -- reinstalled (checksum re-verified); WSL unaffected.
- **Durability Phase A GREEN** (sync-before-ack store + audit; knobs
  default on): sweeps FAILED=0 + crash x2 both platforms; CI dry run
  `38947560303` green; Storage 68 -> 72, total ~55.8%.
- Top-tier packages path COMPLETE + consumer-verified: template 0.2.0
  (15/15 x2), ssl 0.1.0 (14/14 live x2 win + 4/4 SKIP x2 wsl), brotli
  0.1.0 (11/11 x2 both), otel 0.1.0 (consumer-verify still queued),
  zstd 0.3.0 real.
- **REFERENCE-STUDY PROTOCOL is BINDING** (`docs/REFERENCE-STUDY-PROTOCOL.md`;
  §0 standing rule). Plan reordered + reference-annotated (NEXT below).
- **Station-consumes path PROVEN rename-first** (`docs/DESIGN-STATION-CONSUMES.md`):
  declaring the dep silently binds duplicate module names to the PACKAGE
  (W001 warning only), so `app`/`config`/`router` must become
  `xiom.pulse.station.*` (18 imports / 10 files) BEFORE the package core
  is consumed; then delete the four byte-identical modules, declare the
  dep (both manifests + CI installer) and run suites x2 + smoke x2 both.
  The flip experiment was REVERTED -- main stayed green.
- Open relay obligations: compiler resolver-policy answer
  (`REL-20261017-1123-pulse`), packages `xiom.pulse` 0.2 hook-seam
  wishlist (`-2`; the stage-2b gate), ops shared-home clobber flag
  (`-3`).
- v0.64.6 RELEASED (2026-10-16T20:33Z; darwin stream + stdlib pin
  `b81430ba`); PULSE adoption + darwin/pin suites queued (item 7).

NEXT -- the post-release queue (dependency order; the top-tier program
in docs\ROADMAP-TOP-TIER.md frames the whole queue and holds the
lane-ask refs REL-20261015-2202-pulse..-5; TLS is the ceiling):
0. Top-tier tracker: fold lane replies to the asks into the milestone
   plan as they land; W10 bench baseline is the first proof artifact.
1. ~~Keep-alive Phase A + B~~ DONE (2026-10-16): `7924222` + `56eb9f8`;
   freeze gate green (smoke 134/134 x2 both platforms).
1b. **Beacon extraction -- PUBLISHED** (`xiom.pulse` 0.1.0 LIVE,
    eco-v0.1.192, sha256 `53fcc56e..`; acceptance stage 1 GREEN: carved
    suite 125/125 x2 both platforms + `minimal.xi` live x2;
    `docs/repro/beacon-acceptance/`). **Station-consumes = the closing
    half, split per the reference-study protocol:**
    **2a -- consume the core (rename-first; path proven 2026-10-17):**
    declaring `xiom.pulse` makes the catalog resolve DUPLICATE module
    names in favour of the PACKAGE (W001 warning only) -- so the
    product's colliding modules must be renamed FIRST:
    `app`/`config`/`router` -> `xiom.pulse.station.*` (18 imports across
    10 files), then delete the byte-identical `http`/`envelope`/
    `reqctx`/root `pulse` (PROVENANCE sha set), declare the dep in both
    manifests + the CI installer -> suites x2 + smoke x2 both platforms
    must stay 134/134. Full matrix + evidence:
    `docs/DESIGN-STATION-CONSUMES.md`. Refs: PROVENANCE byte-set +
    fastify/gin composition; resolver policy relayed to compiler.
    **2b -- full loop/router/config adoption, GATED:** the product's
    loop features (metrics/audit/CORS/access log) live inside the
    monolith loop and the 0.1.0 seam has no pre/post hooks -> build the
    middleware chain first (item 3; gin/fastify hook taxonomy in
    `DESIGN-MIDDLEWARE-JOBS.md`) and close the packages wishlist for the
    hook seam + module-precedence answer; re-test on the next package
    publish. One core, never a fork.
1c. ~~Consumer-verify `xiom.template 0.2.0`~~ **DONE (session 19,
    2026-10-16):** 15/15 x2 both platforms on the v0.64.5 pin
    (`docs/repro/template-verify/`; registry artifact, sha256 matched;
    reply filed to packages, ref `REL-20261016-1111-packages`).
2. ~~Durability Phase A~~ DONE (2026-10-16; sync-before-ack + knobs +
   claim table; sweeps + crash x2 both platforms; CI `38947560303`).
   Phase B remains (compaction rename ordering + backup fence; the bbolt
   matrix is already extracted in `docs/DESIGN-STORE-DURABILITY.md`).
3. **Middleware -- the adoption path (start here next):** order tests
   FIRST, then the chain refactor, then the jobs core
   (`docs\DESIGN-MIDDLEWARE-JOBS.md`; extracted from gin/fastify/bullmq
   -- nine stages, sent-guard, precomputed tables; do not re-invent).
4. SQL class: migrations runner per docs\DESIGN-SQL-MIGRATIONS.md (wire
   xiom.sqlite into package.xi + the CI install list when the unit
   opens; the SQL driver artifact is co-verified green).
5. Bench baseline: bench\ profile for the six bttger endpoints
   (E:\repos\web-framework-benchmarks + -xlcaptain); pre/post
   keep-alive numbers.
6. SSE + WebSocket units; per-route rate policy; OpenAPI paths
   generation remainder; test-runner harness (fn-ptr fixed).
7. macOS pair (REL-20261010-1609-pulse/-2) -- **v0.64.6 MOVED
   (2026-10-16T20:33Z; darwin stream + stdlib pin `b81430ba`;
   `REL-20261016-2034-compiler` asks PULSE: darwin/pin suites on the new
   archive)**: adoption + re-test queued as the next unit after
   station-consumes stage 2 (bump workflow toolchain pins + macos legs +
   suites on the new archive).
8. Registry pilot gate ping when production-serving
   (REL-20261013-1707); game CP follow-ups via REL-20261013-1701-pulse.
9. Watch the ops redeploy (demo -> 0.2.1) + the website `latest.json`
   follow; note the dl mirror timing (:17).
10. Open obligations/test-backs (filed 2026-10-17): compiler resolver
    policy answer (`REL-20261017-1123-pulse`); packages `xiom.pulse` 0.2
    hook-seam (`-2`; gate for 2b) -- test back on the next publish; ops
    clobber flag (`-3`). **Doorbell re-arm = first action of the
    session.**

DISCIPLINE: pinned toolchain for ALL local builds (export
XIOM_COMPILER/XIOM_STDLIB explicitly -- Windows versioned v0.64.5 / WSL
xiom-v0645 + the `stdlib-092dfa0c` caches); suite watchdog >= 300s on
Linux (drvfs slowness); signed conventional commits; bus sweep before
finishing any task; wrap at every stopping point (SESSION.md digest +
docs\PROGRESS.md). **REFERENCE-STUDY PROTOCOL (owner 2026-10-17)
binding:** every unit cites its reference matrix
(`docs\REFERENCE-STUDY-PROTOCOL.md`); blockers relay first and are
tested back on the next release/publish.
```

## 3d. Paste prompt (2026-10-15 wrap 16, superseded)

```
You are the PULSE lane for E:\xiom-projects\xiom-pulse (the official
XIOM web backend / full backend framework). Read SESSION.md first -- the
CURRENT STATE digest at the top is authoritative; then docs\PROGRESS.md,
docs\PRODUCTION-REFERENCES.md, docs\PRODUCTION-GAPS.md and your designs
(docs\DESIGN-*.md). Relays: E:\xiom-lang\xiom-relays. Reference shelf:
E:\repos\ (fastify, gin, fasthttp, h11, helmet, bbolt, knex, bullmq +
the two benchmark suites).

RE-ARM YOUR DOORBELL FIRST (crons are session-scoped): every 2h with the
standard sweep prompt (fetch+merge --ff-only relays; view --lane pulse;
process items; wrap on change). Use `python tools/relay.py` in the
relays clone; NEVER `git pull` there; never edit another lane's item.

STATE AT WRAP 16:
- 0.2.0 shipped (linux+windows; demo still 0.1.0 on purpose).
- Game control plane /api/game/* SHIPPED (2e65965): register / heartbeat
  (command piggyback) / config (ETag/409) / compat / match-report +
  telemetry (Idempotency-Key) / admin command; P8 convention FROZEN
  (additive-only); engine build note filed (REL-20261013-1701-pulse).
- SIGILL fixed at source (compiler m297) and PULSE-verified (witness rc 0;
  server serves jsonl + kv on a post-fix build); ops told to HOLD the demo
  until our redeploy ping (REL-20261014-1305-pulse).
- The whole critical-path stdlib wave-2 is delivered + reporter-verified:
  deadlines/socket options (0317-pulse, -2), fsync family (-5, -6,
  fsync_dir 1134-pulse), signals/poll/SO_REUSEPORT/WS/chunked (1946-pulse
  CLOSED). Keep-alive + durability designs are ready to implement.
- SQL driver co-verified 24/24 (in-tree) and the registry-artifact path
  works on m303+ (xiom.sqlite 0.4.1, unqualified type-statics form).
- CI pins TODAY (before your first wave): XIOM_TOOLCHAIN_VERSION v0.64.3
  (+4 sha256s), STDLIB_VERSION 3df0843. Local: Windows pinned v0.64.3 at
  %LOCALAPPDATA%\xiom.new-20261010-212636; v0.64.4 at xiom.new; WSL
  default v0.64.4 + pinned v0.64.3 copy at ~/.local/share/xiom-0643;
  pin caches %LOCALAPPDATA%\xiom-pins\stdlib-3df0843 + WSL
  ~/.cache/xiom-pin/stdlib-3df0843; package store has the 10 pinned deps
  + xiom.sqlite 0.4.0/0.4.1.

*** v0.64.5 IS RELEASED (2026-10-15T19:18Z) -- YOUR FIRST JOB IS THE
TOOLCHAIN WAVE-2, THEN CUT 0.2.1. ***

v0.64.5 facts (verified from the release + the compiler tag):
- assets (gh release download -R xiom-lang/xiom v0.64.5 works NOW; the
  dl.xiom-lang.org mirror lands at the next :17 sweep):
  windows-x64.zip  sha256 bd71e2d357b7a7218ad5e440396b7278767ed8bc080ba720192c60742b78907f
  linux-x64.tar.gz sha256 246e5e826640e9e115df188330f1d6d643e4adb30248320d532400acd3a4b7fb
  macos-x64.tar.gz sha256 d4073c84a7c385612a5c08f47db1b8dedc813804942dffd1d884aafe22b46350
  macos-arm64.tar.gz sha256 7636eb6698182ab893d6999f922c5e133d558b443f50f93245c39c5e3a83bf77
- paired stdlib pin (compiler v0.64.5:STDLIB_VERSION):
  092dfa0cc0dc813943154278eecfc4fbb144d6e8  (stdlib-v0.64.5, the MOVED tag)

WAVE-2 RECIPE (do it fully before the cut):
1. Bus sweep as always. Download the 4-5 assets above (SHA256SUMS from the
   GH release or dl) and verify hashes.
2. Install Windows: extract to %LOCALAPPDATA%\xiom.new-20261015-<ts>;
   refresh the xiom.new copy; update the user PATH entry (replace the
   xiom.new-20261010-212636 segment). Install WSL: extract to a versioned
   dir (e.g. ~/.local/share/xiom-v0645), point ~/.local/bin/xiom at it;
   KEEP the v0.64.3 copy for old-pin A/B.
3. Deps for the new toolchain (both platforms): xiom pkg install
   xiom.http@0.1.5 xiom.cookie@0.1.1 xiom.jwt@0.2.0 xiom.router@0.1.0
   xiom.rate@0.2.0 xiom.metrics@0.2.0 xiom.http.middleware@0.1.0
   xiom.session@0.1.0 xiom.static@0.1.0 xiom.kv@0.1.0 xiom.sqlite@0.4.1
4. Pin cache: export stdlib 092dfa0c into %LOCALAPPDATA%\xiom-pins\
   stdlib-092dfa0c and the WSL ~/.cache/xiom-pin/stdlib-092dfa0c
   (git -C E:\xiom-lang\stdlib archive -o file.tar <sha>; tar -x; NEVER
   pipe git archive through PowerShell).
5. Re-land the helper: git apply docs/repro/handlerout-helper/witness.patch
   (permanent suite lock now that the toolchain is >= m261).
6. Pre-sweep checks: SIGILL witness
   (E:\xiom-lang\stdlib\tools\known_failures\p_path_println_context_crash.xi)
   rc 0; build both pulse_app binaries; serve /health in jsonl AND kv.
7. CI pins: STDLIB_VERSION -> 092dfa0cc0dc813943154278eecfc4fbb144d6e8;
   XIOM_TOOLCHAIN_VERSION "v0.64.5" + the four sha256s above in ci.yml,
   release.yml, heavy.yml. Commit -s + push.
8. Full sweep both platforms into probe-logs\toolchain-v0645\ (copy the
   scripts from probe-logs\game-cp-20261013\; Linux: export
   XIOM_COMPILER=<v0645> + XIOM_STDLIB=<new pin>; suites carry
   --timeout-sec 300; expect fleet 12/12 + suites x2 + smoke 119/119
   jsonl+kv both platforms). Commit with evidence pointers.
   *** GATE WARNING: v0.64.5 linux-x64 has a known HTTP-routing
   miscompile (xvector REL-20261015-2142-xvector, compiler acked). If
   the Linux legs show routing/param anomalies or routing-shaped
   failures, STOP and file with us; do not cut 0.2.1 for Linux until
   the compiler item clears. Windows is reported clean. ***
9. release.yml dry run (gh workflow run release.yml) -> watch to green.
10. SQL artifact re-verify on the new pin: run docs/repro/sql-coverify/
    (artifact form, 0.4.1) -> expect 24/24; then verify+close the
    co-verify on REL-20261013-1540-packages / REL-20261013-1718-pulse and
    reply on REL-20261013-1721-bindings-3.

CUT 0.2.1 (docs\RELEASE-CHECKLIST.md is the authority):
- Bump EVERY version literal: project version (src\pulse.xi APP_VERSION),
  the twin `Server: xiom-pulse/<ver>` headers in src\http.xi, the
  openapi literal in tests\test_app.xi, CHANGELOG (Unreleased -> 0.2.1 +
  date), digest references.
- Dry run first (release.yml dispatch) -> green both legs.
- Tag pulse-v0.2.1 (rules: protect-release-tags; org-admin bypass is
  normal), push tag, watch the release run green (dl assets published).
- Ping ops on REL-20261010-1721-ops: artifacts live + hashes -> ops
  redeploys the demo 0.1.0 -> 0.2.1 (website badge follows latest.json).
- Update the digest + PROGRESS with the cut.

AFTER 0.2.1 (dependency order):
1. Keep-alive Phase A + B per docs\DESIGN-KEEPALIVE-DEADLINES.md
   (primitives delivered in the wave-119+ runtime).
2. Durability Phase A/B per docs\DESIGN-STORE-DURABILITY.md.
3. Middleware order tests FIRST, then the chain refactor, then the jobs
   core (docs\DESIGN-MIDDLEWARE-JOBS.md).
4. SQL class: migrations runner per docs\DESIGN-SQL-MIGRATIONS.md (wire
   xiom.sqlite into package.xi + the CI install list when the unit opens).
5. Bench baseline: bench\ profile for the six bttger endpoints
   (E:\repos\web-framework-benchmarks + -xlcaptain); pre/post keep-alive
   numbers.
6. SSE + WebSocket units; per-route rate policy; OpenAPI paths
   generation remainder; test-runner harness (fn-ptr fixed).
7. macOS pair (REL-20261010-1609-pulse/-2) is v0.64.6 scope (owner
   decision); re-test when that toolchain moves.
8. Registry pilot gate ping when production-serving (REL-20261013-1707).
9. Game CP: engine replies / further /api/game/* asks via
   REL-20261013-1701-pulse.

DISCIPLINE: pinned toolchain for ALL local builds (the WSL default is
v0.64.4-ish and will drift -- always export XIOM_COMPILER/XIOM_STDLIB
explicitly); suite watchdog >= 300s on Linux (drvfs slowness); signed
conventional commits; bus sweep before finishing any task; wrap at every
stopping point (SESSION.md digest + docs\PROGRESS.md).
```

## 3a. Paste prompt (2026-10-11 wrap 15, superseded)

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (the official
XIOM web backend, growing into the ecosystem's full backend framework).
Read SESSION.md first -- the CURRENT STATE digest at the top is
authoritative; then docs\PROGRESS.md, docs\PRODUCTION-REFERENCES.md and
the relay docs it lists. The repo is PUBLIC; org rulesets gate PRs on
DCO + ubuntu-latest + windows-latest (admin pushes bypass; never move a
published tag -- on a failed tag run, fix and cut the next patch
version). Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages (or its bindings worktree
E:\xiom-packages\bindings) -- the only standing exception is the
owner-authorized 2026-10-10 darwin runtime one-off (already landed in
stdlib as 48850df); keep the boundary otherwise. Identity "Lefteris
Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s; when a
message contains quotes or slash-paths use git commit -F <file> (PS
mangles native-arg quoting).

COORDINATION: the xiom-relays bus (private xiom-lang/xiom-relays, cloned
at E:\xiom-lang\xiom-relays) is the only cross-lane channel. At session
START and BEFORE FINISHING any task: fetch+merge there (plain
`git pull --ff-only` errors with "Cannot fast-forward to multiple
branches" in this clone -- use `git fetch origin` then
`git merge --ff-only origin/main`), then `python tools/relay.py view
--lane pulse` and process items to pulse (ack; as reporter move
fixed->verified->closed with evidence; never edit another lane's item --
open a new one). A doorbell cron may already be active; keep it or
reschedule every 2-4 hours.

TOOLCHAIN: v0.64.3 everywhere (pins in every workflow +
docs\OPS-REQUEST.md D.1; local Windows/WSL installs upgraded 2026-10-10
-- after ANY toolchain maintenance `xiom doctor` and re-add with
`xiom pkg install`, the re-extract wipes non-archive dirs). Ops hygiene (REL-20261011-1134-ops / TOOLCHAIN_HYGIENE.md): never delete or downgrade the shared homes (%LOCALAPPDATA%\xiom*, ~/.local/share/xiom, ~/xiom); install/uninstall/cleanup tests must use an isolated XIOM_HOME + a lane-local extraction and announce destructive windows to:all first; unresolved-package T001s that recover on a rerun get reported to ops with timestamps. Stdlib pin =
dd352f6 (STDLIB_VERSION, wave 105.1). Local Windows pin cache:
%LOCALAPPDATA%\xiom-pins\stdlib-dd352f6; export via `git -C
E:\xiom-lang\stdlib archive -o file.tar <sha>` + tar -x (NEVER pipe git
archive through PowerShell -- it corrupts the stream). Linux uses the
pinned checkout via XIOM_STDLIB.

TASK ORDER:
1. FIRST: bus sweep (above) + quick regression: probe fleet (12/12) +
   m212 + suites x2 + smoke 119/119 (jsonl and kv) on Windows and Linux
   (Linux with the pin); compare against probe-logs\regress-20261010\.
2. WATCH lanes / verify as fixes land (bus items to pulse):
   - SIGILL: stdlib REL-20261010-1615-stdlib + ops REL-20261010-1721-ops
     -- when fixed, include in the next cut and tell ops to redeploy.
   - macOS legs: compiler REL-20261010-1609-pulse (arm64 memset) +
     stdlib REL-20261010-1609-pulse-2 (Darwin x64 fp128) -- when BOTH
     fixed: RELEASE_BUILD_MACOS=true, dry-run all four legs, cut.
   - Compiler REL-20261010-1854-pulse / REL-20261010-2122-pulse (the
     &HandlerOut helper crash; site mode shipped with the inlining
     workaround) -- when fixed, re-test and note.
   - website REL-20261010-1658-website (fixed; website verifies) +
     REL-20261010-1549-website-6 (acked).
3. RELEASE (next = 0.2.1 hotfix): packaging fix + v0.64.3 + site mode
   are already on main; 0.2.1 waits on the SIGILL fix; macOS joins when
   its two items land. Follow docs\RELEASE-CHECKLIST.md (every version
   literal incl. the twin Server: headers; dry run; tag; CI; ops at
   :17; website auto).
4. CONTINUE the framework backlog (docs\PRODUCTION-REFERENCES.md, in
   order): security headers (helmet checklist) -> keep-alive/deadlines
   design doc (h11 + fasthttp three-timeout model) -> store durability
   discipline (bbolt) -> SQL migrations (knex) -> OpenAPI generation
   from route metadata -> 0.4 middleware chain (gin + fastify stage
   names) + jobs (bullmq). Each unit: full suites (Linux pinned) +
   smoke, docs + relay updates, signed commit; end with a green CI dry
   run when it touches the server. Reference shelf lives in E:\repos
   (MIT-only, light clones; owner-authorized).
5. OPS/SITE: demo stays 0.1.0 until the SIGILL fix; website is waiting
   for the cut ping; wire the owner's cover image when it lands.
6. Wrap at every stopping point: SESSION.md digest + relay docs +
   PROGRESS.md, commit signed, push.

DISCIPLINE: probes in-repo; suites x2; outputs to files, never inherited
pipes (chatty servers: file-redirect stdout; the PS smoke reads exit
codes through a cmd wrapper); durable step logs; every struct literal
lists every field; no module-scope package constructors (Vec-holder
pattern); no const-receiver .to_str(); explicit *p for &mut Int reads;
quoted dotted TOML dep keys; avoid inner quotes driving WSL from PS
(write scripts to files); wsl --shutdown on CLR/paging or clang crashes
(system commit pressure, not the build); guard io.create_dir with
io.is_dir (contract requires absence); avoid io.list_dir until
C-PULSE-17 lands; kill stray test servers after any stopped monitor;
NEVER re-land a revert by merge without `git diff --name-only <base>
<branch>` (revert-merge pitfall -- cost us one red CI round); do not
trust `git pull --ff-only` in the relays clone.
```

## 3c. Paste prompt (2026-10-07, superseded)

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (official XIOM
full web backend). Read SESSION.md first, then docs\PROGRESS.md and the
reference relay docs it lists. Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; do not push to origin without owner approval. Identity
"Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Track the LATEST toolchain: Windows compiler v0.64.0
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe); Linux/WSL compiler v0.64.0
(~/.local/share/xiom) — the Linux lane is verified and every script has a
verified .sh twin (scripts/*.sh + scripts/lib.sh). XIOM_RUNTIME_DIR
retired. Registry consumption still needs xiom.toml source-roots
(C-PULSE-02).

TASK ORDER (owner-ordered, 2026-10-07 wrap):
1. WINDOWS RE-VERIFY of the registry wave: first run
   `xiom pkg install xiom.metrics@0.2.0 xiom.http.middleware@0.1.0
   xiom.static@0.1.0` (the app imports them now; Windows source-roots are
   already in xiom.toml), then suites x2 + smoke + crash + rate on
   Windows; record deltas vs the Linux run.
2. Continue M4/M5 per docs\PROGRESS.md: keep-alive, schema helper, recv
   timeouts (stdlib), CI file when the repo goes public, packaging per
   docs/OPS-REQUEST.md.
3. Watch the compiler lane for C-PULSE-08 (m212 dotted-key gate:
   docs/repro/dep-roots-name-form both variants must exit 0), C-PULSE-09
   (xiom.session store integration crash), C-PULSE-10 (xiom.kv kv_get
   corruption; probe_pkg_kv is the known-red gate), C-PULSE-11 (package
   type aliases). Re-run the probes when the next archive lands; swap the
   session store and the kv backend when green.
4. Update SESSION.md STATE + the three relay docs + PROGRESS.md at every
   wrap; commit signed (DCO -s).

Discipline: every struct literal lists every field; never init module
vars with package constructors (use the Vec-holder pattern,
probe_pkg_state_holder); no const-receiver .to_str(); explicit *p for
&mut Int reads; quote dotted TOML dep keys; probes in-repo; suites x2;
outputs to files, never inherited pipes; durable step logs for anything
that can crash (io.flush_stdout is a no-op).
```

## 3b. Paste prompt (2026-10-05, superseded)

```
You are the PULSE session for E:\xiom-projects\xiom-pulse (official XIOM
full web backend). Read SESSION.md first, then docs\PROGRESS.md and the
reference relay docs it lists. Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; do not push to origin without owner approval. Identity
"Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Track the LATEST toolchain: compiler v0.64.0
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe), stdlib E:\xiom-lang\stdlib,
XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1. Registry
consumption needs xiom.toml source-roots (C-PULSE-02, still open).

TASK ORDER (owner-ordered, 2026-10-07):
1. PORT EVERY SCRIPT TO A .sh TWIN so Linux developers can use them:
   scripts\dev-env, run, build, http_smoke, soak_http, soil_tcp?, concurrent,
   crash_test, rate_smoke, store_soak, proxy_e2e -> each gets a bash
   equivalent that runs on WSL/Linux (same flags, same exit-code gating,
   watchdog via `timeout`). Verify each .sh from WSL before moving on.
2. ADOPT THE PUBLISHED REGISTRY WAVE (all signature-verified):
   xiom.metrics 0.2.0 (labels + latency preset) to replace/extend our
   counters; xiom.http.middleware 0.1.0 for the middleware chain;
   xiom.session 0.1.0 to replace src\session.xi; xiom.static 0.1.0 for
   favicon/landing serving; xiom.kv 0.1.0 as the durable store backend
   (keep the JSONL fallback documented). Run each consumer probe first
   (tests\probes\probe_pkg_*.xi pattern), then swap, suites x2 + smoke.
3. Continue M4/M5 per docs\PROGRESS.md (proxy E2E is GREEN 11/11 via
   scripts\proxy_e2e.ps1 + deploy\nginx\pulse.conf.example; keep-alive,
   schema helper, audit rotation, CI file when public).
4. Update SESSION.md STATE + the three relay docs + PROGRESS.md at every
   wrap; commit signed.

Discipline: every struct literal lists every field; never init module vars
with package constructors; no const-receiver `.to_str()` (use
convert.int_to_string); explicit `*p` for &mut Int reads; probes in-repo;
suites x2; outputs to files, never inherited pipes (Start-Process +
redirection, bounded socket polls, kill by PID tree).
```

