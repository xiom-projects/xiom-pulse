<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> compiler lane: findings (pin v0.63.1)

**Relay:** hand this file to the compiler-lane session together with the
matching `docs/repro/<bundle>/` directories from the PULSE repo
(`E:\xiom-projects\xiom-pulse`). PULSE is a consumer lane; it does not edit
the compiler tree.

**Pin this file was produced on (2026-10-05):**

| Component | Version / hash |
|---|---|
| compiler | v0.63.1 (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`) |
| stdlib | `E:\xiom-lang\stdlib` @ `15cb889` (2026-10-05T14:03:35+03:00) |
| env | `XIOM_STDLIB=E:\xiom-lang\stdlib`, `XIOM_RUNTIME_DIR=E:\xiom-lang\stdlib\runtime` |

Every finding below has a minimal repro staged in-repo (never `%TEMP%\kilo`),
run with `.\scripts\run.ps1 <probe> -Quiet` (watchdog + exit-code gate).

## Open findings

| Date | Finding | Evidence | Workaround in PULSE | Impact |
|---|---|---|---|---|
| 2026-10-05 | **C-PULSE-01 (RESOLVED in v0.64.0): a method named `read` with exactly ONE argument is hijacked by the raw-pointer codegen builtin. PULSE re-verified: `probe_method_matrix.xi` exit 0; `probe_read_no_io.xi` and `probe_net_roundtrip.xi` now green; the stdlib `TcpStream.read` path is functional.** | `docs/repro/read-method-builtin-shadow/` | none needed on v0.64.0 (raw `socket_recv` still used by the server for `&mut Vec` clarity) | resolved |
| 2026-10-05 | **C-PULSE-04 (STILL OPEN on v0.64.0): a `&mut Int` parameter used BARE in value position (arithmetic RHS or `return`) yields the pointer ADDRESS, not the pointee.** Explicit `*p` is correct. Re-verified 2026-10-05 on v0.64.0: `mut-int-ref bad=5`, `bare_add a=180233435864 r=180233435856`. | `docs/repro/mut-int-bare-read/` | always `*p = *p + k; return *p;` (existing `xiom.gbnf` pattern) | silent wrong values in cursor-style parsers; broke `xiom.http` v0.1.0's parser for consumers |
| 2026-10-05 | **C-PULSE-02 (STILL OPEN on v0.64.0): installed registry packages are not mapped to module-catalog source roots.** `[dependencies]`/`dependencies:` are parsed by `xiom-graph` but never resolved to directories; re-tested on v0.64.0 with source-roots removed: 13x `T001 undefined variable 'http_*'`. | `docs/repro/registry-dep-resolution/` | `xiom.toml` `[project].source-roots` lists the installed package `src/` dirs | `xiom pkg install` alone cannot be `use`d; registry adoption requires manual wiring |
| 2026-10-05 | **C-PULSE-07 (OPEN on v0.64.0): a module-scope `var` initialized by a cross-package constructor call is accepted but emits `call @rate_keyed_new` with no definition (clang: `use of undefined value`) or crashes at module init (0xC0000005).** | `docs/repro/module-scope-package-init/probe.xi` (clang undefined value); PULSE `src/ratelimit.xi` first version crashed the suite before any output; caller-owned `Limiter` value fixed it (suite 75 checks green). | keep package aggregates in function-scoped / caller-owned values (module-scope stdlib constructors are fine) | crashes before `main`/first log line; looks like a linker or runtime fault, not a checker gap |
| 2026-10-05 | **C-PULSE-06 (OPEN on v0.64.0): a struct literal with a MISSING field compiles with no diagnostic; the omitted field reads uninitialized garbage.** In PULSE's server this produced `0xC0000005` on real requests. | `docs/repro/missing-struct-field/probe.xi`: `Pair{ a: 1; }` (missing `b: Vec[UInt8]`) compiles; `p.b.len()` prints `2296606801712`. App crash evidence: `server_exit=-1073741819` on `POST /api/session/login` before the fix; smoke 44/44 after. | always initialize every declared field (pin discipline extended to struct literals) | silent uninitialized memory; crashes that look like unrelated regressions |
| 2026-10-05 | **C-PULSE-05 (OPEN; v0.64.0 delta: now ABORTS): the erased-interface default stub fires for a module-`const` receiver method call.** On v0.63.1 `SCHEMA_VERSION.to_str()` rendered EMPTY (invalid JSON); on **v0.64.0 it terminates the process with exit `0x80000003`** (STATUS_BREAKPOINT) and the same W005 warning. `probe_const_to_str.xi` reproduces. Call-result receivers in the same module render correctly. | `tests/probes/probe_const_to_str.xi`; PULSE `src/store.xi schema_line()` (workaround in place) | `xiom.convert.int_to_string(n)` free function instead of the interface method | silent data corruption on v0.63.1 -> hard abort on v0.64.0; any package module using `.to_str()` on a const receiver dies |

## C-PULSE-01 -- details

- **Where:** `crates/xiom-codegen/src/call.rs:3177`:

  ```rust
  // Builtin read(ptr): load value through raw pointer.
  if fn_name == "read" && args.len() >= 1 {
      let (ptr_val, ptr_ty) = self.compile_expr(&args[0])?;
      if ptr_ty.ends_with('*') { ... return Ok((tmp, pointee)); }
  }
  ```

  The guard checks only the name and arg count, not the receiver. For a
  method call `sock.read(&mut buf)` the `&mut Vec` argument lowers to
  `%struct.Vec*`, which ends in `*`, so the builtin fires and the real method
  is never emitted. The sibling `write` builtin (`call.rs:3141`) requires
  `args.len() >= 2`, which is why `stream.write(&msg)` still works.

- **Repro:** `docs/repro/read-method-builtin-shadow/probe.xi`
  (a local matrix, no networking):

  | Variant | Shape | v0.63.1 |
  |---|---|---|
  | A | `read(self, &mut Vec[UInt8]) -> Result[Int, Int]` | **BROKEN** |
  | B | same body, named `take2` | ok |
  | C | `read(self, &mut Vec[UInt8]) -> Int` | **BROKEN** |
  | D | `take3(self) -> Result[Int, Int]` | ok |
  | E | `read5(self, &mut Vec[UInt8]) -> Result[Int, Int]` | ok |

  `.\scripts\run.ps1 docs\repro\read-method-builtin-shadow\probe.xi -Quiet`
  -> `program_exit=5` (= A|C broken, B/D/E green).

- **IR evidence (`--emit-ir`):** `define @SockA.read` and `@SockC.read` are
  emitted but **never called** from `main`; `@SockB.take2`, `@SockD.take3`,
  `@SockE.read5` are called. In the networking repro the call site's
  `Result.is_ok` folds to `icmp ne i64 0, 0` (constant false).

- **App-context evidence:** `tests/probes/probe_net_roundtrip2.xi` —
  `socket.socket_recv(server_stream.fd, ...)` reads the 4 bytes the peer
  wrote, while `server_stream.read(&mut got)` (stdlib
  `xiom/net/net.xi:105`) fails on the same fd. `probe_tcp_server.xi` (the
  TcpStream-based server) could not serve; `probe_tcp_server2.xi` (raw fd)
  is green (60s soak 145/145).

- **Suggested fix:** gate the builtin on the *receiver* being a raw pointer
  (`receiver_expr` present and receiver type `*T`), or on "no user method
  resolves". Add a diagnostic when a user method collides with a codegen
  builtin name (`read`/`write`/`offset`/`len`).

- **Test-gap note (compiler e2e):** no stdlib or package suite exercises
  `TcpStream.read/write` (grep over `E:\xiom-lang\stdlib\tests` and the
  packages tree). A loopback socket-pair fixture would have caught this.

## C-PULSE-04 -- details

- **Repro:** `docs/repro/mut-int-bare-read/probe.xi`.
  Output on v0.63.1:

  ```
  bare_add a=1056790543816 r=1056790543808
  deref_add b=11 r=11
  bare_read c=10 r=1056790543744
  deref_read d=10 r=10
  mut-int-ref bad=5
  ```

  `bare_add` = `p = p + 1; return p;`; `deref_add` = `*p = *p + 1; return *p;`.
  The printed values are Windows stack addresses of the caller's local.

- **Relationship to the resolved matrix:** the v0.62.2/v0.62.3 write-drop
  row (`packages docs/repro/v0622-regressions`) covered the write side
  (bare assignment now writes through). This is the remaining **read side**:
  the reference is used as a value instead of being loaded through.

- **App-context evidence:** `xiom.http` v0.1.0 `src/parser.xi`
  (`parse_request_line` keeps its cursor in `&mut Int pos_ref` and does
  `pos_ref = pos_ref + str_len + 1`); a consumer calling
  `http_parse_request("POST /api/echo ... Content-Length: 7 ...")` gets
  `Unexpected end of request line pos=372324169712` (address).

- **Suggested fix:** auto-deref `&T`/`&mut T` parameters in value position,
  or emit a diagnostic requiring the explicit `*`.

## C-PULSE-02 -- details

- **Where:** `crates/xiom-graph/src/manifest.rs` `resolve_source_roots`
  returns only the project's own roots; `crates/xiom/src/lib.rs`
  catalog setup adds file parent + project `src/` + graph roots + stdlib
  dirs. `DependencySpec` entries (TOML `[dependencies]`, legacy
  `dependencies:`) are parsed but unused for catalog roots.
- **Evidence:**
  1. `xiom pkg install xiom.http` -> installed to
     `%LOCALAPPDATA%\xiom\packages\xiom-http-0.1.0` (sha256 + signature
     verified).
  2. `tests/probes/probe_pkg_http.xi` with deps declared: 13x
     `error[T001] undefined variable 'http_*'`.
  3. Adding `xiom.toml` `source-roots = ["src", ".../xiom-http-0.1.0/xiom-http/src"]`
     loads the package; the remaining errors were a package defect (filed
     separately).
- **Suggested fix:** resolve deps to
  `$XIOM_HOME/packages/<name-dashed>-<version>/<inner>/src` plus the
  package root (barrels like `http.xi` live there) and feed them into
  `expand_sources_with_graph` / catalog `add_external_dir`; `xiom pkg lock`
  already has the resolved tree.

## C-PULSE-06 -- details (missing struct field)

- Repro and evidence above. The PULSE crash happened because `HandlerOut`
  gained `body_bytes: Vec[UInt8]`; two literals were not updated, the build
  stayed green, and the missing Vec read garbage at runtime.
- **Hardening suggestion (compiler lane):** reject incomplete struct
  literals (or warn). The ecosystem already pins "initialize every local";
  struct literals are the remaining hole.
- **PULSE-side policy (adopted):** every struct literal lists every field,
  even defaults.

## C-PULSE-07 -- details (module-scope package ctor)

- Module-level `var b = rate_keyed_new(1, 1);` (cross-package call) is
  accepted by the checker; codegen emits `call i64 @rate_keyed_new(...)`
  with **no definition** -> clang `error: use of undefined value
  '@rate_keyed_new'`. In PULSE's larger `src/ratelimit.xi` first version the
  program built and crashed with `0xC0000005` during module init, before
  the first test printed. Caller-owned values are unaffected.
- Repro: `docs/repro/module-scope-package-init/probe.xi`.
- **PULSE-side policy (adopted):** no package calls in module initializers;
  package aggregates live in function-scoped / caller-owned values.

## Feature gap -- Windows exe icon embedding (not a defect)

PULSE received the official app icon (`resources/img/pulse-ico.ico`,
270 KB multi-size). There is no toolchain support to embed it into the AOT
executable on Windows (no `--icon` flag, no `.rc`/winres handling in
`xiom --help`, compiler source, or the pkg manifest). PULSE serves it as
`/favicon.ico` instead and keeps the landing page wired to it.

**Compiler lane reply (2026-10-05):** workaround until shipped --
post-build `rcedit app.exe --set-icon app.ico` (one line; PULSE wired it
into `scripts\build.ps1`, active automatically when rcedit is on PATH).
Planned implementation queued for **v0.64.1+**: `xiom --icon app.ico
file.xi` (Windows first) -- writes a tiny `.rc`
(`IDI_ICON1 ICON "app.ico"`), compiles with the already-present LLVM
(`llvm-rc /fo app.res`), includes the `.res` in the link args, cached by
icon hash next to the runtime cache; ships with `--help`, compiler
`AI_CONTEXT.md`, and website docs per the docs-coupling rule. macOS/Linux
icons (Info.plist / .desktop) are separate scope. PULSE will re-test and
delete the rcedit hook when `--icon` lands.



## C-PULSE-05 -- details (W005 delta: const receiver)

- **Warning:** `warning[W005]: unresolved call '@to_str' from
  @pulse.store.schema_line (IR line N) is a known erased-interface/
  contract-clause gap; emitting a typed default stub (see
  docs/COMPILER_BUGS.md)`.
- **Minimal shape:** in a project package module,

  ```xiom
  const SCHEMA_VERSION: Int = 1;
  fn schema_line() -> Str {
    return "{\"kind\":\"schema\",\"version\":" + SCHEMA_VERSION.to_str() + "}";
  }
  ```

  renders `{"kind":"schema","version":}` (empty) on v0.63.1. Replacing the
  method call with `convert.int_to_string(SCHEMA_VERSION)` renders `1`.
  `time.unix_timestamp().to_str()` (call-result receiver) in the same file
  renders correctly.
- **Delta vs the documented W005 rows** (`docs/COMPILER_BUGS.md`
  m142/m146 sections): those cover contract clauses and interface VALUES
  in `Option[Error]` payloads / erased receivers. This is a plain concrete
  `Int` receiver that happens to be a module-level `const` inside a
  compiled package module; the receiver type is statically known, so a
  default stub is strictly worse than either static dispatch or a hard
  error.
- **v0.64.0 delta (2026-10-05):** the same shape now **aborts the process**
  with exit `0x80000003` (STATUS_BREAKPOINT) after the identical W005
  warning; nothing is printed. Repro: `tests/probes/probe_const_to_str.xi`
  (`const V: Int = 41; ... V.to_str()`), exit code `-2147483645` via the
  `xiom --run` wrapper. This upgrades the impact from silent corruption to
  hard crash while the receiver type is statically known.
- **Suggested fix:** const-fold the receiver and resolve through the
  concrete impl (same path the call-result receiver takes), or turn the
  W005 stub into a compile-time error when the receiver type is concrete.

## Positive confirmations on the pin (do not chase)

- `Vec[StructType]`, module-level `const` tables, const match arms, mixed
  numeric literals: all green in PULSE code (consistent with the packages
  lane's v0.62.4/v0.63.x resolutions).
- The runtime-dir discovery gap is the known upstream `5b7547b0`; the
  `XIOM_RUNTIME_DIR` override also links `sha256_sw.c` and **fully unblocks
  stdlib SHA-256** (NIST KAT green in `tests/probes/probe_crypto.xi`).
- Contracts on PULSE's code (`requires: true` only) evaluated cleanly; the
  v0.63.1 contract-evaluator fix holds.

## Upstream status (v0.64.0 adopted 2026-10-05, owner decision: latest-tracking)

PULSE now tracks the latest compiler/stdlib/packages (no fixed pin). v0.64.0
fleet results from the PULSE side:

| Item | v0.64.0 result |
|---|---|
| `XIOM_RUNTIME_DIR` / runtime-link | **RESOLVED** -- env-free compile+run (both `XIOM_STDLIB` and `XIOM_RUNTIME_DIR` unset) green; doctor reports `lib\runtime` |
| crypto-link (SHA-256 KAT) | **RESOLVED env-free** -- `sha256(abc)=ba7816bf...15ad` with no overrides |
| C-PULSE-01 (`read` elision) | **RESOLVED** -- matrix exit 0; `probe_read_no_io` + `probe_net_roundtrip` green |
| C-PULSE-04 (`&mut Int` bare read) | **OPEN** -- exit 5, stack addresses printed |
| C-PULSE-05 (const `.to_str()` W005) | **OPEN and WORSE** -- silent empty on v0.63.1 becomes `0x80000003` abort on v0.64.0 (`probe_const_to_str.xi`) |
| C-PULSE-06 (missing struct field) | **OPEN** -- struct literal without a field -> garbage read / crash (`probe_missing_field.xi`) |
| C-PULSE-07 (module-scope package ctor) | **OPEN** -- accepted init emits undefined call / crashes at module init (`probe_module_pkg_init.xi`) |
| C-PULSE-02 (deps -> catalog roots) | **OPEN** -- 13x T001 with source-roots removed |
| Stricter checking | **POSITIVE** -- v0.64.0 rejects argument type mismatches that v0.63.1 silently accepted; it caught a stale PULSE test (`test_http.xi` passing strings to the Step-2 `handle_route`) which is now fixed. Consider a migration note: code compiled under v0.63.1 may not type-check under v0.64.0. |
| Fleet on v0.64.0 | suites x2 (`test_smoke`/`test_http`/`test_app`), smoke 38/38, 64/64 concurrent, registry probes, read probes -- all green on `out\pulse_app_v3.exe` |

**Bump procedure (for the next release):** run `probe_crypto`, `probe_method_matrix`,
`probe_mut_int_ref`, `probe_const_to_str`, `probe_store_debug`, the three
suites x2, smoke, 64 concurrent, and a 30m dual soak; record any deltas in
this doc and SESSION.md.

## Suggested compiler-side hardening from PULSE's session

1. A lint/diagnostic for user definitions colliding with codegen builtin
   names (`read`, `write`, `offset`, `len`, `size_of`, `sizeof`,
   `align_of`) — C-PULSE-01 was invisible without `--emit-ir`.
2. An e2e fixture for `xiom.net.TcpStream.read/write` over a loopback pair
   (would have caught C-PULSE-01 and any partial-send behavior).
3. A `--emit-ir` "call not emitted" warning is impossible in general, but a
   differential test between JIT and AOT for the stdlib net module would
   catch builtin-vs-method divergence.

## Delta 2026-10-07 (Linux/WSL session)

**Headline:** the Linux target is real and verified. The same v0.64.0
source builds a native Linux ELF from WSL (`out/pulse_app`, x86-64),
crypto links env-free (NIST SHA-256 KAT), and the full fleet is green on
Linux: suites x2 (`test_http`/`test_app`/`test_smoke`, 0 failures), smoke
61/61, crash 6/6, rate smoke, store soak 20s, proxy E2E 11/11 (nginx
1.24 TLS, extracted from Ubuntu debs, no root). All 12 `.sh` twins were
written and verified from WSL.

| Finding | Evidence | Impact |
|---|---|---|
| **C-PULSE-08 (m212 latent, dotted keys):** `dependency_roots_under` (`crates/xiom-graph/src/manifest.rs`, not in the shipped v0.64.0 binaries) matches `dep.name` verbatim, so canonical dotted keys (`xiom.rate`) will never match installed dirs (`xiom-rate-0.2.0`). Its unit tests cover dash-form keys only. | `docs/repro/dep-roots-name-form/` -- on v0.64.0 both dash and dot variants fail identically (6x T001); the gate is "both exit 0" once m212 ships | keeps the `source-roots` workaround on both platforms; next archive would otherwise leave dotted-key consumers with no roots |
| **C-PULSE-09 (package-aggregate integration crash):** a `Vec[SessionStore]` store driven from PULSE wrapper modules crashes at runtime (exit -1, no output) while the identical calls inline in the consuming module are green. Repro pair: `tests/probes/probe_adopt_smoke.xi` (crashes at the session step) vs `tests/probes/probe_session_inline.xi` (green, 15 durable steps). Same class suspected as C-PULSE-07 (module-state vs package aggregates). | above probes, 2026-10-07, WSL Linux; PULSE reverted the session-store swap (local store retained) | any consumer wrapping a package aggregate behind a second PULSE module; needs a compiler-lane bisect |
| **C-PULSE-10 (kv_get Str corruption, classification open):** after `kv_put`, `kv_get` returns an address-like decimal `Str` for every key; multi-key writes also corrupt `kv_get_bytes` (9-byte value read back as 6). Stored bytes verified correct via `kv_get_bytes` + `from_utf8` in a clean single-key run. | `docs/repro/kv-get-str-corruption/`; `tests/probes/probe_pkg_kv.xi` (known-red gate) | blocks `xiom.kv` adoption; could be a package-internal Str construction miscompiled on v0.64.0 (C-PULSE-04/05 family) -- packages + compiler lanes to triage |
| **C-PULSE-11 (type alias to a package type fails cross-module):** `pub type Store = SessionStore;` in module A is "unknown type 'Store'" in module B; the build emits `warning: unknown type 'Store' -- defaulting to i64` and continues (silent miscompile risk). | session-adoption build log 2026-10-07; wrapper-struct workaround used | any consumer exposing a package type through an alias; the defaulting warning should be a hard error at least |
| **POSITIVE -- holder pattern for package aggregates:** module-scope `Vec[Registry].new()` (a builtin, not a package ctor) + push-in-function + `&mut v[0]` works and is now used by `src/metrics.xi`. Pinned by `tests/probes/probe_pkg_state_holder.xi`. | probe green on v0.64.0 | the sanctioned C-PULSE-07 workaround for process-global package state |

**Bump procedure addendum:** also run `probe_pkg_state_holder`,
`probe_adopt_smoke`, `probe_session_inline`, `probe_pkg_kv` (the kv gate
should flip to green), and both variants of
`docs/repro/dep-roots-name-form/` on the next archive.

## Delta 2026-10-08 (Windows re-verify + stdlib adoption)

| Finding | Evidence | Impact |
|---|---|---|
| **C-PULSE-12 (module-name/alias shadowing):** a module whose last segment matches an imported module's alias shadows that alias in every compilation that includes it. `xiom.pulse.server` (the app entry) vs `use xiom.net.server;` in `src/http.xi` -> inside http.xi, `server.server_parse_request(raw)` is misread as a method call on an expression ("cannot call 'server_parse_request' on this expression"), and the unqualified name is "undefined"; a compilation that imports `xiom.pulse.server` via `use` poisons the alias the same way. | `src/http.xi` 2026-10-08 build logs; workaround: rename `xiom.pulse.server` -> `xiom.pulse.app` (done) | any consumer whose module name collides with a stdlib module's last segment; an import-alias syntax (`use xiom.net.server as net_server;`) or full-path qualification would remove this trap |
| **POSITIVE -- stdlib write_all adopted:** `TcpStream.write_all` (stdlib 2026-10-07) replaced PULSE's hand-rolled partial-send loop; the 270 KB favicon path is green through `send_all`. | suites x2 + smoke 61/61 both platforms | retires the last C-PULSE-01-adjacent send workaround |
| **POSITIVE -- stdlib server_parse_request adopted:** `xiom.net.server.server_parse_request` now backs `http.parse_request` behind PULSE's caps (16 KiB guard, 100-header cap, trimmed values); invalid Content-Length is now rejected (hardening). Differential parity pinned by `tests/probes/probe_stdlib_server_parse.xi` (12 checks). | probe + test_http x2 (47 checks) + smoke + suites both platforms | the stdlib lane's PULSE-hardening delivery consumed; parser duplication removed |
| **Windows re-verify (registry wave):** `xiom pkg install` of metrics/middleware/static on Windows, then suites x2 + smoke 61/61 + crash 6/6 + rate smoke -- all green on `out\pulse_app.exe`. | 2026-10-08 run logs | both platforms now exercise the same adoption set |

**Bump procedure addendum 2:** add `probe_stdlib_server_parse` to the
archive-bump fleet (it gates the parser contract) and re-run the Windows
`xiom pkg install` + suite set after any compiler archive change.

## Delta 2026-10-08 (v0.64.1 sweep -- Windows toolchain updated in place)

**Closed by v0.64.1 (verified):**
- **C-PULSE-08 CLOSED:** `docs/repro/dep-roots-name-form/` -- BOTH the
  dash and dot dependency-key variants now exit 0 with no `source-roots`
  workaround. The m215 dotted-key normalization works.
- **C-PULSE-10 CLOSED:** `probe_pkg_kv` GREEN -- `kv_get` returns the
  stored text (m217 nested payload chains), multi-key reads stable. The
  `docs/repro/kv-get-str-corruption/` bundle should now pass as written.
- **C-PULSE-11 (package type aliases in vectors): fixed per the release
  notes** (m216); the session-store swap retry using the alias design is
  the acceptance test (next step).
- **Regression:** suites x2 (`test_http`/`test_app`/`test_smoke`), smoke
  73/73, crash 6/6, rate smoke -- all GREEN on v0.64.1 on Windows.

**NEW (consumer-visible breakage, needs the packages lane):**
- **v0.64.1 enforces extern-unsafe confinement in catalog bodies and the
  published `xiom.http` 0.1.1 violates it**: 67 T001s ("calling extern
  \"C\" function 'xiom_alloc' requires an `unsafe` block"; "safe fn
  'make_ptr_value' cannot return raw pointer type '*UInt8'"). Any project
  with `xiom-http-0.1.1/src` on the catalog path fails to compile.
  PULSE response: `xiom.http` was already unused (the stdlib parser
  adoption replaced it), so it is pruned from `xiom.toml`/`package.xi`;
  `tests/probes/probe_pkg_http.xi` is the known-red gate. **`xiom.http`
  needs a compat republish (unsafe-wrapped internals) before other
  consumers adopt v0.64.1.** The release notes list "Breaking changes:
  None" -- this should be called out or the enforcement gated.

**Consumer cautions from the v0.64.1 release notes (known issues):**
- Passing a byte vector by reference to `Str.from_utf8` can emit invalid
  code -- pass by value (PULSE's kv workaround already does).
- Assigning an optional into an existing vector element can leave the
  slot unreadable; a mutating method through a nested field can update a
  copy -- relevant to any wrapper-struct aggregate design (the C-PULSE-09
  class); PULSE's alias-based retry avoids nested fields.

**C-PULSE-09 (session store integration) -- REMAINS OPEN on v0.64.1
(retest 2026-10-08):** the bridge arrangement now **compiles** (the alias
and nested-payload compile fixes landed), but still **crashes at run time
with 0xC0000005 at the first bridge access to the module-level store**:
durable steps show 1-5 (metrics + `session_reset`) complete, then the
crash inside `session_count()` -> `sb_ensure`/`sb_count` -> element access
on a module-level `Vec[SessionStore]` owned by a different PULSE module.
Single-module direct usage (`probe_pkg_session`) is green on **both**
compiler versions, so the open question is specifically cross-module
package-aggregate vector access. Evidence: `tests/probes/probe_adopt_smoke.xi`
(steps now written to the portable `pulse-adopt-steps.txt`). PULSE keeps
the local session store; the swap retries when this runtime class is
fixed. Suggested reduction for the compiler lane: two catalog modules,
module A pushes a `SessionStore` into a module-level `Vec`, module B
calls `session_count(&a_vec[0])`.

**Bump procedure addendum 3:** run `probe_pkg_http` too (expected red
until the package republishes) and `probe_pkg_middleware`/`probe_pkg_*`
after any compiler change.

**Toolchain asks (2026-10-08 continuation):**

- **Compile-time build stamping:** no `--define KEY=VAL`-style flag exists
  (checked `xiom --help`), so `pulse --version` and `/api/version` surface
  provenance from runtime env (`PULSE_BUILD_COMMIT` / `PULSE_BUILD_DATE`).
  A define flag (or compile-time env capture) would let release artifacts
  embed commit/build date truthfully.
- **C-PULSE-12 addendum (family namespaces):** the shadowing also applies
  to module *families*: inside `xiom.pulse.*` modules, the `pulse` alias
  resolves to the family namespace (not the `xiom.pulse` module), so
  `pulse.pulse_version()` is a method-call-on-expression error. PULSE
  keeps a local `APP_VERSION` const in sync instead; an import-alias or
  full-path call syntax would remove the trap.

**Lane status observed 2026-10-08 (for the v0.64.1 adoption gate):**

- `9033c6b8 fix(graph): m215 dotted dependency keys resolve (C-PULSE-08)`
  -- once archived, the `docs/repro/dep-roots-name-form/` gate (both dash
  and dot variants exit 0) becomes runnable for real.
- `0c5337e0 fix(codegen): m216 alias Vec elements resolve (C-PULSE-11)`
  and `fd6ea4c6 fix(codegen): m217 nested Option/Result payload chains
  keep inner type (C-PULSE-10)` -- m217 is the suspected kv_get
  corruption root cause (`Result[Option[Str], Str]` chain); re-run
  `probe_pkg_kv` plus `docs/repro/kv-get-str-corruption/` on v0.64.1.
- `479afffe docs(relay): C-PULSE-09 triage -- wrapper-aggregate crash not
  reproducible from committed sources` -- the committed tree no longer
  contains the failing arrangement (the session-store swap was reverted).
  PULSE will re-attempt the swap on v0.64.1 using the arrangement in git
  history (`220f814`) and re-file with the exact source if it still
  crashes; m216/m217 may have addressed it.
- dl latest is still **v0.64.0** (2026-10-05); the fixes above are in the
  lane source only. PULSE's fleet is ready to re-run the day v0.64.1 is
  published (the addenda above list the exact probes).

## Delta 2026-10-08 (Linux/WSL v0.64.1 sweep -- fleet green, C-PULSE-09 narrowed to Windows)

**Install (verified):** WSL compiler updated to **v0.64.1** from the
published archive (`xiom-0.64.1-linux-x64.tar.gz`, 29,352,608 B, published
2026-10-08, sha256 `6f6787a3...c91b5601`); `sha256sum -c SHA256SUMS` OK and
`diff -rq` between the extracted archive and the installed tree is
byte-identical. Compiler binary sha256 `36dd6fb5...b3b36b`; stdlib lane
checkout `4dd8844` (0.64.2 pin prep). Pin recorded in
`docs/OPS-REQUEST.md` section D.1.

**Fleet results (logdir `probe-logs/linux-sweep-20261008T134143Z/`):**

- **Probe fleet 11/11 green**, including `probe_adopt_smoke` **twice in a
  row**: steps 1-10 all complete, `program_exit=0`, `[PASS] adopt-smoke`.
  **C-PULSE-09 does NOT reproduce on Linux v0.64.1** -- the cross-module
  `Vec[SessionStore]` path (`session_reset`/`session_count`/
  `session_create`/`session_get`/`csrf_*` through wrapper modules) runs
  clean under WSL. The Windows 0xC0000005 crash evidence stands; the open
  question is now **Windows-specific** (or platform ABI-specific). Please
  keep the m216/m217 class in mind; PULSE will re-run this probe on both
  platforms when the next archive lands.
- **m212 gate (C-PULSE-08) green on Linux**: `dash` and `dot` variants,
  `--check` and `--run`, all exit 0 -- **after** repairing the local
  package-home mismatch found this session (C-PULSE-13, filed in
  `docs/PACKAGE-WISHLIST-PULSE.md`; the failure was `xiom pkg` installing
  to `$HOME/xiom/packages` while `xiom_home()` resolves the existing
  canonical `~/.local/share/xiom`). With `XIOM_HOME=~/xiom` both variants
  passed pre-repair too, so **m215 dotted-key normalization is confirmed
  on Linux**; the gate red was purely the install-layout mismatch.
- **Regression suites x2** (`test_http`/`test_app`/`test_smoke`), **smoke
  73/73 on jsonl and kv**, crash 6/6, rate smoke, **kv store-soak 20m
  green** (756 writes / 0 fail, compact + hard-kill reopen counts intact,
  `server_exit=0`) -- all on Linux v0.64.1.
- `probe_stdlib_server_parse` (12 checks) and all package probes green:
  m217 kv reads, m216 alias vectors, metrics/middleware/static/session
  surfaces behave on the Linux archive.

**Cross-lane note:** first sweep pass had the m212 gate red because of
the C-PULSE-13 layout mismatch; the pre-repair evidence is kept in
`probe-logs/linux-sweep-20261008T132937Z/` (for the record), the green
post-repair sweep is the `...T134143Z/` logdir.

## Delta 2026-10-08 (wrap 3) -- C-PULSE-13 routed here; xiom.http closed

- **C-PULSE-13 (Unix shipped-installer layout) was routed to this lane**
  (compiler/installer) by the packages lane: `xiom pkg install` writes
  `$HOME/xiom/packages` while `xiom_graph::paths::xiom_home()` resolves
  the existing canonical `~/.local/share/xiom`, so `<home>/packages`
  misses the store. Evidence + local workaround in
  `docs/PACKAGE-WISHLIST-PULSE.md` (row C-PULSE-13); suggested fix:
  unify the two resolvers (preferred: `xiom-pkg` uses
  `xiom_graph::paths::xiom_home()`), and re-run `xiom doctor` on a fresh
  Unix install as the regression check.
- **`xiom.http` 0.1.2 republish verified; the package was re-added:**
  `probe_pkg_http` GREEN on Windows and Linux v0.64.1; suites x2 + smoke
  73/73 green with `xiom.http` back in `xiom.toml`/`package.xi`. The
  v0.64.1 67-T001 extern-unsafe breakage from 0.1.1 is closed (packages
  lane fix eco-v0.1.103, sha256 `994271f0...`).

## Delta 2026-10-08 (wrap 4) -- C-PULSE-02 fully closed; chunked decode landed

- **C-PULSE-02 CLOSED (no-source-roots build verified):** with v0.64.1
  the `[dependencies]` table alone resolves every registry package
  (m212/m215); PULSE removed the absolute-path `source-roots` workaround
  from `xiom.toml` and re-verified: build + suites x2 + smoke 76/76 on
  Windows and Linux, plus `probe_pkg_http`/`probe_pkg_kv` green. The
  manifest now carries no machine-specific paths (release hygiene).
- **C-PULSE-13 recurrence observed:** a Unix toolchain re-extract
  (happened locally 2026-10-08 ~17:24Z) removed the
  `~/.local/share/xiom/packages` symlink bridge -- it must be re-created
  after toolchain maintenance until the resolver/installer is unified.
  Installer-side suggestion: create the canonical `packages/` entry
  (or point it at the legacy store) as part of every install.
- **PULSE-side feature over the stdlib parser:** `Transfer-Encoding:
  chunked` request bodies are now decoded (chunk extensions ignored,
  trailers validated + skipped, 1 MiB decoded cap, TE+CL -> 400, other
  codings -> 501). The stdlib `server_parse_request` stays head +
  Content-Length focused; no compiler/stdlib ask from this wrap.

## Delta 2026-10-08 (wrap 4, continued) -- NEW C-PULSE-14: request-path RSS growth

> **Correction (wrap 6, 2026-10-09): the growth is NOT Linux-only.** The
> "Windows stays flat" comparison used a Windows soak whose sampler
> measured the `cmd.exe` wrapper instead of the server -- see the wrap-6
> section at the end of this doc. Both platforms grow; the wrap-6 numbers
> supersede the Linux-only scope below.

- **Symptom (first Linux-server HTTP soak, 30m, 1 req/500ms, /health):**
  RSS 2,560 KB -> 148,992 KB -- **~48 KB per request, linear** (3,097
  requests, 0 errors, fds 5 -> 5, clean exit). Windows v0.64.1 the same
  day: **flat** (+86 KB over 588 requests, handles flat).
- **PULSE-side bisection:** NOT the chunked change (scratch HEAD build:
  identical ~47.7 KB/req); NOT the recv chunk size (4 KiB vs 64 KiB
  `socket_recv` max: identical); generic allocator reuse is fine
  (`tests/probes/probe_alloc_loop.xi`: 524 MB Vec churn -> flat 67 MB
  peak); an idle server is flat, so the retention is in the served
  request path. Suspects: per-request retention in the runtime socket
  send/recv path (stdlib `socket_recv` + `TcpStream.write_all` each use
  64 KiB stack buffers) or another per-request structure in the v0.64.1
  Linux runtime/allocator.
- **Evidence:** `probe-logs/soak-http.summary.txt` + the 2026-10-08 RSS
  curve in `probe-logs/soak-http-progress.txt`; A/B 5m scratch build at
  the same rate; Windows 5m soak flat.
- **Ask:** runtime/allocator investigation on Linux (RSS retention per
  request; the minimal repro is a loop of one accept + one small
  request/response, or valgrind/massif on `out/pulse_app`). If some
  arena deliberately retains, a release/trim hook would work too.
- **Impact:** Linux is the Phase-2 demo/deployment target; an unattended
  public instance needs this fixed or a `MemoryMax` + restart cadence
  (noted to ops). Phase-1 website work is unaffected.

## Delta 2026-10-09 (wrap 6) -- C-PULSE-14 CORRECTION: cross-platform; Windows soak measurement bug fixed

- **The Windows soak's memory sampler measured the wrong process.**
  `soak_http.ps1` (and `concurrent.ps1`) start the server through a
  `cmd.exe` log-redirection wrapper and sampled `$srv.Id` -- cmd.exe's
  working set, not the server's. Every historical "flat memory" Windows
  figure (the 1h soak `+48 KB / handles flat`, the 6,543/6,543 soak, the
  64-concurrent check, and the wrap-4 Linux-vs-Windows bisection) measured
  the wrapper. Fixed in both scripts: they now resolve the real child
  process (Win32_Process parent lookup) before sampling.
- **Corrected Windows numbers:** 5m soak (587 requests, 0 failures):
  ws 5,300,224 -> 24,113,152 B = **~32.0 KB/request, linear**. The new
  `rss_probe.ps1` independently reports ~32-34 KB/request steady-state.
  Linux: ~48 KB/request long-run (30m soak) / ~54 KB/request short-run
  (`rss_probe.sh`). Handles/fds flat on both; pure Vec churn flat on both
  (`probe_alloc_loop`) -- so the retention is in the served request path
  on **BOTH platforms**, same magnitude class.
- **Repro tooling (in-repo):** `scripts/rss_probe.{sh,ps1}` (steady metric
  from the 2nd sample), `tests/probes/probe_alloc_loop.xi`, and the
  corrected soaks. Evidence: `probe-logs/soak-http-windows-5m.summary.txt`,
  `probe-logs/rss-probe.summary.txt`, `probe-logs/kv-soak-45m*`.
- **Candidate fix already in the lane:** **m235 "hoist loop-body static
  allocas to the entry block" (C-ORBIT-05)** is exactly the class of bug
  that would allocate once per request iteration; PULSE will re-run the
  probe/soak on the first archive containing m235. The runtime lane
  should treat this as a cross-platform request-path retention (not a
  Linux port issue).
- **Impact:** unchanged conclusion, wider scope -- an unattended public
  instance on any OS needs the fix or `MemoryMax` + restart cadence.

## Delta 2026-10-09 (wrap 6b) -- soak/backup housekeeping

- `soak_http.ps1`/`concurrent.ps1` now sample the real server process
  (see above). `soak_tcp.ps1` was already correct (direct start).
- New `scripts/rss_probe.{sh,ps1}`: start the server, serve /health on an
  interval, report warmup-inclusive and steady-state (2nd sample onward)
  growth per request; exit gates only on a clean start/stop.

## Delta 2026-10-09 (wrap 7c) -- compiler leniency: stray `}` silently accepted

While adding the PULSE_BIND warning, a stray `}` after the bind check left
the tail of `cfg_validate` (rate/burst/audit/TTL/CSRF/log/backend checks
plus `return w`) outside the function -- and the build still succeeded
(rc 0), with the function silently returning early. It cost a debugging
cycle. If module-scope statements are intentional (script mode), please
confirm; otherwise a parse error (or at least a warning) for statements
outside a function body would be safer for consumers.

## Delta 2026-10-09 (wrap 8) -- C-PULSE-16: PULSE_BIND not enforced (wildcard bind)

- **Repro:** `PULSE_BIND=127.0.0.1 PULSE_PORT=18099 ./out/pulse_app` ->
  `ss -ltn` shows LISTEN on `0.0.0.0:18099`: the configured address is
  ignored. Root cause is in the runtime/stdlib boundary:
  `xiom.net.socket.socket_bind` is documented wildcard-only and
  `xiom_socket_bind(sock, port)` takes no address.
- **Found by ops on the live demo** (verified: port blocked by the host
  firewall, so exposure is mitigated); PULSE 0.1.x leaves `PULSE_BIND`
  advisory and documents the proxy/firewall expectation.
- **Ask:** address-aware bind in the runtime + stdlib (details and the
  PULSE verification plan in `docs/STDLIB-WISHLIST-PULSE.md`, wrap-8
  row). PULSE adds a smoke check asserting the LISTEN socket's local
  address once the primitive lands (next release).

## Delta 2026-10-09 (wrap 8b) -- PULSE macOS build blocked upstream (dry-run evidence)

The first four-platform release dry run (workflow_dispatch, no release)
was green on linux-x64 + windows-x64 and failed both macOS legs at the
build step, all upstream:

- `stdlib/runtime/xiom_runtime.c:4222`: `_SC_AVPHYS_PAGES` is undeclared
  on darwin (Linux-only sysconf constant) -- hits x64 and arm64.
- `stdlib/runtime/fp128_helpers.c`: x86 inline asm (`leaq`/`movq`)
  compiled on arm64 -- needs an arch guard or an arm64 path.
- darwin codegen (arm64 log): `use of undefined value
  '@llvm.memset.p0i8.i64'` -- the intrinsic declaration is missing on the
  darwin target.

PULSE's macOS release legs are now gated behind the repository variable
`RELEASE_BUILD_MACOS` (skipped by default; the release job tolerates the
skip, mirroring the xiom workflow), so the next tag is not blocked.
Re-running the dry run with `gh variable set RELEASE_BUILD_MACOS --body
true` is the acceptance test once these clear.

## Delta 2026-10-09 (wrap 9) -- v0.64.2 adoption results (answering the relay ask)

Both platforms moved to **v0.64.2** (dl live; SHAs pinned in all PULSE
workflows; the CI setup action's C-PULSE-13 bridge is removed).

- **C-PULSE-09 CLOSED.** The full probe fleet is 11/11 on Windows AND
  Linux; `probe_adopt_smoke` completes steps 1..10 with exit 0 on both
  (the m223..m227 batch fixed the Windows cross-module crash). The
  session-store swap retry (bridge `220f814`) is PULSE's next unit.
- **C-PULSE-13 CLOSED (m232 verified).** `xiom pkg install` now lands in
  the compiler's resolved home (`~/.local/share/xiom/packages`) and
  `xiom doctor` agrees; the legacy bridge was removed from this box and
  from the CI setup action; installs + builds verified without it.
- Suites x2 + smoke 78/78 on both platforms; m212 dash+dot gate green;
  crash 6/6; rate green.
- **C-PULSE-14 split by platform on v0.64.2:** **Windows is FIXED**
  (`rss_probe`: ws flat over 206 requests, -240 B/req steady; the v0.64.1
  growth of ~32 KB/req is gone). **Linux still grows and is worse**:
  ~87 KB/req steady over 176 requests (v0.64.1 was ~48 KB/req). m235 was
  not in the v0.64.2 batch; please keep it/this in the runtime scope --
  the `rss_probe` twins + `probe_alloc_loop` repros are ready, and PULSE
  re-runs them on the next archive.
- Environment note: a **concurrent toolchain re-extract wiped the WSL
  packages store mid-sweep** (looked like mass T001s until the store was
  re-checked); reinstalling via `xiom pkg install` restored everything.
  Not a compiler defect -- noted for reproducibility.
