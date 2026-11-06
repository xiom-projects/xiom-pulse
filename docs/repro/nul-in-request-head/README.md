<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# NUL in the request head truncates the parsed request (stdlib)

**Status:** OPEN upstream, filed as `REL-20261106-1716-pulse` (to stdlib).
**Pin:** compiler v0.65.6 + stdlib `6fdde4ee` + `xiom.pulse` 0.3.2.
**Probe:** `tests/probes/probe_fuzz_repro.xi` (canonical; not duplicated
here).

## Run

```powershell
.\scripts\build.ps1 tests\probes\probe_fuzz_repro.xi -Name probe_fuzz_repro
.\out\probe_fuzz_repro.exe
```

## Expected vs observed

A strict parser rejects a NUL in the request line or field lines (RFC 9112
request-line/field-line are CTL-free except HTAB where allowed). Observed on
the pin above:

| Input shape | Observed |
|---|---|
| `PO\0ST /x HTTP/1.1` | `ok=true`, method `PO`, target `/x` |
| `\0OST /x HTTP/1.1` | `ok=true`, method ``, target `/x` |
| `GET /x\0 HTTP/1.1` | `ok=true`, method `GET`, target `/x` |
| `X: a\0b` header value | `ok=true`, header truncated |
| `Ho\0st: t` header name | `ok=true`, header truncated |

## Why it matters

A front proxy and PULSE can disagree about the method/target/header bytes.
That is the parser-differential class request smuggling relies on, even when
the empty shape only yields a 404.

## PULSE-side state

The Station dispatcher rejects a parsed request with an empty method or
target (`src/server.xi`, `tests/test_app.xi`), as defense in depth. The
Beacon package still depends on the parser fix.

The fuzz gate (`tests/fuzz_parsers.xi`) tracks this as `known_nul` until the
upstream fix; run `scripts/fuzz_parsers.ps1 -StrictNul` (or the `.sh
--strict-nul`) to turn it into a hard failure and verify the fix.
