<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- upstream repro index

Minimal, runnable evidence for every upstream (compiler/stdlib/runtime)
finding PULSE files. The owner relays the `SESSION.md` findings rows to the
packages/debug lane; these bundles are the payload.

Format: one directory per finding, with `probe.xi` + `README.md`
(run command + matrix + expected vs got).

| Bundle | Purpose | Status on pin v0.63.1 |
|---|---|---|
| `read-method-builtin-shadow/` | C-PULSE-01: one-arg method named `read` hijacked by the raw-pointer codegen builtin (`call.rs:3177`); kills `xiom.net.TcpStream.read` | **OPEN** -- matrix exit 5; IR call-site dropped |
| `mut-int-bare-read/` | C-PULSE-04: bare `&mut Int` read in value position yields the address; explicit `*p` correct | **OPEN** -- exit 5 (bits 0\|2); stack addresses printed |
| `registry-dep-resolution/` | C-PULSE-02: installed registry packages are not mapped to catalog source roots; `[dependencies]` ignored for resolution | **OPEN** -- workaround `xiom.toml` `source-roots` documented |
| `runtime-link/` | covered upstream (xiom-packages `5b7547b0`); PULSE A/B harness is `tests\probes\probe_crypto.xi -NoRuntimeDir` | OPEN upstream; PULSE uses the `XIOM_RUNTIME_DIR` override |
| `crypto-link/` | stdlib `xiom.crypto` SHA-256 linkability **with `XIOM_RUNTIME_DIR` set** -- PULSE Step 0d: KAT PASSES under the override; without it `undefined symbol: xiom_sha256_hash` | RESOLVED via override (relay: same class as runtime-link) |
| `socket-reuseaddr/` | Windows `xiom_socket_bind` has no `SO_REUSEADDR`; rapid server restarts can hit `WSAEADDRINUSE` | stdlib wishlist row filed (with socket timeout stubs) |
| `socket-timeout/` | `socket_set_timeout`/`socket_set_nonblocking` are documented stubs -> no slow-client guard | stdlib wishlist row filed |

Bundles are promoted to their own directory only when PULSE has a minimal
reproduction beyond the upstream packet; otherwise the app-context evidence
lives in this README + `SESSION.md`.
