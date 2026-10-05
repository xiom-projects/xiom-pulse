<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> stdlib lane: wishlist

**Relay:** hand this file to the stdlib-lane session. PULSE is a consumer
lane; it never edits `E:\xiom-lang\stdlib`. Evidence paths are from
`E:\xiom-projects\xiom-pulse` (app context) or exact stdlib `file:line` on
the pin below.

**Pin:** compiler v0.63.1, stdlib `15cb889` (2026-10-05T14:03:35+03:00),
`XIOM_RUNTIME_DIR=E:\xiom-lang\stdlib\runtime`.

## Open items

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| **RESOLVED (2026-10-05):** `str_bytes(s: Str) -> Vec[UInt8]` exists as `xiom.string.slice.str_bytes` (`slice.xi:135`, `ensures: result.len() == s.len()`); submodule import required (root `xiom.string` does not re-export it). PULSE adopted it in `src/http.xi` and `tests/test_app.xi`. | stdlib slice.xi:135; PULSE `src/http.xi str_to_bytes` now delegates | -- | resolved; do not re-request |
| Socket option exposure: real `SO_RCVTIMEO` (`socket_set_timeout`), `SO_REUSEADDR` (`socket_reuse_addr`), and non-blocking mode; the Windows `xiom_socket_bind` path does not set `SO_REUSEADDR` while the POSIX branch does | stubs: `xiom/net/socket.xi:287,302,360`; Windows bind `runtime/xiom_runtime.c:4737` (no `setsockopt`), POSIX :4816 (sets it). PULSE: `src/server.xi` accept loop; soak scripts | restart retry/backoff; alternate ports; document the slow-client exposure | production hardening (slow clients, graceful restarts); **stdlib lane confirmed queued** (runtime-backed: needs `XIOM_RUNTIME_DIR` until archives bundle the newer `runtime/`) |
| Deadline-capable receive: `socket_recv(fd, max)` is untimed and blocking; `TcpStream.read` is also dead on this pin (compiler C-PULSE-01) | `xiom/net/socket.xi:170`; PULSE `src/server.xi read_request()` | none -- clients must behave; watchdog only in tests | DoS/slowloris resistance; **queued by the stdlib Pulse-hardening wave** |
| Full request-head parser on the server side: `xiom.net.server` parses only the request line (`server_parse_request_line`) and builds responses; header parsing + `Content-Length` framing + body slicing are missing, so every server re-implements them. Suggested shape: `server_parse_request(bytes) -> Result[ServerRequest, Str]` with header list + body span | stdlib: `xiom/net/server.xi:24` (request line only, no header API); PULSE hand-rolled `src/http.xi` (parse_request/header_get/content_length_of, 250 lines) | PULSE-local parser (this session) | every XIOM server/codec duplicates HTTP head parsing; **queued by the stdlib wave (pure XIOM, lands immediately)** |
| `TcpStream.write` guarantees: it returns `Ok(n)` without looping, so a partial `send` is reported as success; a `write_all` equivalent (loop until all bytes sent) is needed for >64 KiB responses. **PULSE hit this in production: serving the 270 KB app icon via one `socket_send` returned a short write and the client got nothing; the server now chunks+loops (`send_all`).** | `xiom/net/net.xi:124` (`TcpStream.write` -> `xiom_socket_send`); PULSE `src/server.xi send_all`; smoke `favicon 200`/`favicon length` green after the fix | `send_all` loop (PULSE local) | large payloads/streaming cannot be served safely; **`write_all` queued by the stdlib wave -- this is the consumer-level evidence** |
| Durable `flush_stdout` -- **confirmed empty body at `io.xi:903`** (stdlib lane), which explains PULSE's lagging/truncated redirected logs until process exit | `xiom/io/io.xi:903`; PULSE `src/server.xi` calls it per log line with no effect | flush happens at process exit; keep servers running until shutdown for full logs | observability of long-running services; **queued (runtime-backed until the newer runtime ships)** |
| Test harness that can execute registered tests (existing `test.dispatch` row) -- forwarded to the compiler lane by stdlib (module-scope fn-pointer reassignment unsupported per `test/harness.xi`) | PULSE suites unroll checks with manual `[PASS]`/`[FAIL]` counters (`tests/test_http.xi`, `tests/test_app.xi`) | unrolled main + failure counter | boilerplate in every suite |
| `hmac_sha256_hex` convenience + documented constant-time compare for JWT HS256 | `xiom/crypto/crypto.xi:1113` (`hmac_sha256`), `xiom/crypto/mac.xi:139,159`; the registry `xiom.jwt` 0.2.0 now uses `constant_time_compare` | PULSE consumes `xiom.jwt` 0.2.0 instead of hand-rolling HMAC | **queued by the stdlib wave** |
| Durable append: `fsync`/`FlushFileBuffers` wrapper for crash-safe stores (`io.sync_file(path)` or `append_line_sync`). No `fsync`/`FlushFileBuffers`/`_commit` exists anywhere in `runtime/*.c` (grep, 2026-10-05), so "durable" appends return after OS write-back and can lose the tail on power loss. | PULSE `src/store.xi` claims crash-safety today only as torn-tail *healing* (newline repair + invalid-line skip), not power-loss durability; `store_compact` uses `io.rename` (which correctly maps to `MoveFileExA(..., MOVEFILE_REPLACE_EXISTING)`, verified `xiom_runtime.c:143`) | newline healing + accept OS write-back for now | honest durability guarantees for Step 3 storage; audit-log integrity claims |

## Positive confirmations (please keep)

- **v0.64.0: runtime + crypto link env-free.** PULSE verified with BOTH
  `XIOM_STDLIB` and `XIOM_RUNTIME_DIR` unset: `probe_hello` and
  `probe_crypto` (NIST SGK KAT `ba7816bf...15ad`) green; `xiom doctor`
  reports the installed `lib\runtime`. The `XIOM_RUNTIME_DIR` workaround is
  retired in PULSE's dev-env.
- **v0.64.0: `TcpStream.read` path works** (compiler C-PULSE-01 fixed):
  PULSE's `probe_read_no_io.xi` and `probe_net_roundtrip.xi` (loopback
  listen/connect/accept/read/write) are green. The queued stdlib loopback
  fixture in `tests/` will lock this permanently.
- **`xiom.string.slice.str_bytes`** adopted by PULSE (see the resolved row
  above).
- **Raw-fd socket path** remains solid: v0.63.1 1h soak PS 7070/7070 +
  WSL 6128, server **13,198/13,198** 200s, handles flat, clean shutdown.
- **`xiom.serialize.json`**, **`xiom.env.var_or`**, contracts: unchanged,
  green on v0.64.0.
- **Submodule pattern note:** root modules do not re-export submodule
  functions (`compare.str_eq_ignore_case`, `convert.parse.parse_int`,
  `slice.str_bytes`) -- works fine with explicit submodule imports; worth a
  doc line in each root module README.

## Notes for the stdlib lane's own coverage

- No stdlib test exercises `TcpStream.read/write` end-to-end (grepped
  `E:\xiom-lang\stdlib\tests` and the packages tree in this session), which
  is why the compiler's `read`-builtin hijack (C-PULSE-01) shipped
  unnoticed. A loopback fixture with `tcp_listen`/`tcp_connect` + read/write
  in `tests/` would lock the fix and the write semantics together.
- `xiom/net/socket.xi` stubs are *documented* Err returns -- good -- but a
  server framework cannot ship without at least the timeout option; the
  runtime already links `setsockopt` on both branches except Windows bind.
