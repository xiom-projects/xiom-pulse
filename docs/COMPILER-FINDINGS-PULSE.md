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
| 2026-10-05 | **C-PULSE-01: a method named `read` with exactly ONE argument is hijacked by the raw-pointer codegen builtin.** | `docs/repro/read-method-builtin-shadow/` | raw `xiom.net.socket.socket_recv(fd, max)`; never name one-arg methods `read` | kills `xiom.net.TcpStream.read` (all stdlib networking reads) and `os.Pipe.read`; silent, no diagnostic |
| 2026-10-05 | **C-PULSE-04: a `&mut Int` parameter used BARE in value position (arithmetic RHS or `return`) yields the pointer ADDRESS, not the pointee.** Explicit `*p` is correct. | `docs/repro/mut-int-bare-read/` | always `*p = *p + k; return *p;` (existing `xiom.gbnf` pattern) | silent wrong values in cursor-style parsers; broke `xiom.http` v0.1.0's parser for consumers |
| 2026-10-05 | **C-PULSE-02: installed registry packages are not mapped to module-catalog source roots.** `[dependencies]`/`dependencies:` are parsed by `xiom-graph` but never resolved to directories; the driver adds only project roots + stdlib. | `docs/repro/registry-dep-resolution/` | `xiom.toml` `[project].source-roots` lists the installed package `src/` dirs | `xiom pkg install` alone cannot be `use`d; registry adoption requires manual wiring |

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

## Positive confirmations on the pin (do not chase)

- `Vec[StructType]`, module-level `const` tables, const match arms, mixed
  numeric literals: all green in PULSE code (consistent with the packages
  lane's v0.62.4/v0.63.x resolutions).
- The runtime-dir discovery gap is the known upstream `5b7547b0`; the
  `XIOM_RUNTIME_DIR` override also links `sha256_sw.c` and **fully unblocks
  stdlib SHA-256** (NIST KAT green in `tests/probes/probe_crypto.xi`).
- Contracts on PULSE's code (`requires: true` only) evaluated cleanly; the
  v0.63.1 contract-evaluator fix holds.

## Suggested compiler-side hardening from PULSE's session

1. A lint/diagnostic for user definitions colliding with codegen builtin
   names (`read`, `write`, `offset`, `len`, `size_of`, `sizeof`,
   `align_of`) — C-PULSE-01 was invisible without `--emit-ir`.
2. An e2e fixture for `xiom.net.TcpStream.read/write` over a loopback pair
   (would have caught C-PULSE-01 and any partial-send behavior).
3. A `--emit-ir` "call not emitted" warning is impossible in general, but a
   differential test between JIT and AOT for the stdlib net module would
   catch builtin-vs-method divergence.
