<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- upstream repro index

Minimal, runnable evidence for every upstream (compiler/stdlib/runtime)
finding PULSE files. The owner relays the `SESSION.md` findings rows to the
packages/debug lane; these bundles are the payload.

Format: one directory per finding, with `probe.xi` + `README.md`
(run command + matrix + expected vs got).

| Bundle | Purpose | Status on v0.64.0 |
|---|---|---|
| `read-method-builtin-shadow/` | C-PULSE-01: one-arg method named `read` hijacked by the raw-pointer codegen builtin | **RESOLVED in v0.64.0** (matrix exit 0; read probes green) -- kept as historical |
| `mut-int-bare-read/` | C-PULSE-04: bare `&mut Int` read in value position yields the address; explicit `*p` correct | **OPEN** -- exit 5 on v0.64.0 |
| `registry-dep-resolution/` | C-PULSE-02: installed registry packages are not mapped to catalog source roots | **OPEN on v0.64.0** -- 13x T001 without `source-roots` |
| `missing-struct-field/` | C-PULSE-06: struct literal with a missing field compiles; omitted Vec reads garbage | **OPEN on v0.64.0** -- `b.len()` prints 2296606801712; caused a PULSE 0xC0000005 |
| `runtime-link/` | covered upstream (xiom-packages `5b7547b0`) | **RESOLVED in v0.64.0 R65** -- env-free compile+run green |
| `crypto-link/` | stdlib SHA-256 linkability | **RESOLVED in v0.64.0 m195** -- NIST KAT env-free |
| `socket-reuseaddr/` | Windows `xiom_socket_bind` has no `SO_REUSEADDR` | stdlib wishlist row filed (queued wave) |
| `socket-timeout/` | `socket_set_timeout`/`socket_set_nonblocking` are documented stubs | stdlib wishlist row filed (queued wave) |

Bundles are promoted to their own directory only when PULSE has a minimal
reproduction beyond the upstream packet; otherwise the app-context evidence
lives in this README + `SESSION.md`.
