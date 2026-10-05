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
| Socket option exposure: real `SO_RCVTIMEO` (`socket_set_timeout`), `SO_REUSEADDR` (`socket_reuse_addr`), and non-blocking mode; the Windows `xiom_socket_bind` path does not set `SO_REUSEADDR` while the POSIX branch does | stubs: `xiom/net/socket.xi:287,302,360`; Windows bind `runtime/xiom_runtime.c:4737` (no `setsockopt`), POSIX :4816 (sets it). PULSE: `src/server.xi` accept loop; soak scripts | restart retry/backoff; alternate ports; document the slow-client exposure | production hardening (slow clients, graceful restarts); a half-open request blocks the single-threaded accept loop forever |
| Deadline-capable receive: `socket_recv(fd, max)` is untimed and blocking; `TcpStream.read` is also dead on this pin (compiler C-PULSE-01) | `xiom/net/socket.xi:170`; PULSE `src/server.xi read_request()` | none -- clients must behave; watchdog only in tests | DoS/slowloris resistance |
| Full request-head parser on the server side: `xiom.net.server` parses only the request line (`server_parse_request_line`) and builds responses; header parsing + `Content-Length` framing + body slicing are missing, so every server re-implements them. Suggested shape: `server_parse_request(bytes) -> Result[ServerRequest, Str]` with header list + body span | stdlib: `xiom/net/server.xi:24` (request line only, no header API); PULSE hand-rolled `src/http.xi` (parse_request/header_get/content_length_of, 250 lines) | PULSE-local parser (this session) | every XIOM server/codec duplicates HTTP head parsing |
| `xiom.string.bytes`: `str_bytes(s: Str) -> Vec[UInt8]` (exact inverse of `Str::from_utf8`, no FFI reach-around) | PULSE hand-rolled `str_to_bytes` in `src/http.xi`, `tests/probes/probe_tcp_server2.xi`, `probe_tcp_client2.xi`, `probe_socket_low.xi`, `probe_net_roundtrip.xi`, `probe_crypto.xi` (6 copies) | local 8-line loop per file | every wire responder re-implements Str->bytes |
| `TcpStream.write` guarantees: it returns `Ok(n)` without looping, so a partial `send` is reported as success; a `write_all` equivalent (loop until all bytes sent) is needed for >64 KiB responses | `xiom/net/net.xi:124` (`TcpStream.write` -> `xiom_socket_send`); PULSE responses are small today | keep responses < 64 KiB; check `n` at call sites | large payloads/streaming cannot be served safely |
| Durable `flush_stdout` on abnormal exit (existing row) -- add PULSE as requester | PULSE server/soak logs: redirected stdout arrives only on clean exit; a killed server lost buffered output during Step 0 diagnostics (`src/server.xi` calls `io.flush_stdout()` after every log line to compensate) | flush explicitly per line | observability of long-running services |
| Test harness that can execute registered tests (existing `test.dispatch` row) -- add PULSE as requester | PULSE suites unroll checks with manual `[PASS]`/`[FAIL]` counters (`tests/test_http.xi`, `tests/test_smoke.xi`) because the global registry cannot run tests on this pin (`xiom/test/harness.xi` header notes) | unrolled main + failure counter | boilerplate in every suite |
| `hmac_sha256_hex` convenience + documented constant-time compare for JWT HS256 (verify path exists: `hmac_verify`) | `xiom/crypto/crypto.xi:1113` (`hmac_sha256`), `xiom/crypto/mac.xi:139,159`; PULSE Step 2 will sign/verify tokens | use `hmac_sha256` + `hmac_verify` directly | minor ergonomics; more hand-rolled hex in apps |

## Positive confirmations (please keep)

- **`xiom.crypto.sha256_hex` works on v0.63.1 when
  `XIOM_RUNTIME_DIR` is set** -- NIST KAT `ba7816bf...15ad` for `"abc"`
  (`tests/probes/probe_crypto.xi`). Without the override the historical
  `undefined symbol: xiom_sha256_hash` reproduces. This resolves the
  crypto-link blocker for PULSE; relayed to the packages lane too.
- **Raw-fd socket path is solid**: `socket_tcp/bind/listen/accept/recv/send/
  close` served 145/145 requests over a 60s soak and 64/64 simultaneous
  connections with flat handles (Step 0c/0e evidence).
- **`xiom.serialize.json`** compact `json_stringify` + `json_parse` +
  `json_set` handled all PULSE routes and request bodies (v0.63.1).
- **`xiom.env.var_or`** enabled the `PULSE_PORT` override cleanly.
- **`xiom.string.str_index_of/str_trim/str_slice`** and the
  `xiom.string.compare` submodule (`str_eq_ignore_case`) worked from a
  consumer project (note: submodule import was required -- root
  `xiom.string` does not re-export `str_eq_ignore_case`;
  `xiom.convert.parse.parse_int` likewise lives in the `xiom.convert.parse`
  submodule).
- **Contracts**: the v0.63.1 contract-evaluator fix held on all PULSE code.

## Notes for the stdlib lane's own coverage

- No stdlib test exercises `TcpStream.read/write` end-to-end (grepped
  `E:\xiom-lang\stdlib\tests` and the packages tree in this session), which
  is why the compiler's `read`-builtin hijack (C-PULSE-01) shipped
  unnoticed. A loopback fixture with `tcp_listen`/`tcp_connect` + read/write
  in `tests/` would lock the fix and the write semantics together.
- `xiom/net/socket.xi` stubs are *documented* Err returns -- good -- but a
  server framework cannot ship without at least the timeout option; the
  runtime already links `setsockopt` on both branches except Windows bind.
