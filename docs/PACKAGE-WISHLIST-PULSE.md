<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> packages lane: wishlist + consumer findings

**Relay:** hand this file to the packages-lane session. PULSE consumes
packages from the registry only (never vendored, never edited). Evidence
paths are from `E:\xiom-projects\xiom-pulse`.

**Pin:** compiler v0.63.1, stdlib `15cb889`, registry
`https://registry.xiom-lang.org` (install flow verified: sha256 + ed25519
signature checks pass; trust fingerprint `4f:3b:47:f3:ae:17:b1:3c`).

## Consumer-visible defects

| Date | Package | Finding | Evidence | Impact |
|---|---|---|---|---|
| 2026-10-05 | `xiom.http` v0.1.0 | (a) `src/parser.xi` references `HttpRequest`/`HttpMethod`/`HttpHeaders`/`method_from_str` from `xiom.http.types` **without `use xiom.http.types;`** -- a consumer importing only `xiom.http.parser` gets 19 T001s; (b) the request cursor is a `&mut Int` used bare (`pos_ref = pos_ref + str_len + 1`) which is broken on v0.63.1 (compiler C-PULSE-04: bare `&mut Int` read yields the address), so `http_parse_request` on a valid request returns `Unexpected end of request line pos=372324169712`; (c) `tests/test_conformance.xi` never calls `http_parse_request`/`http_parse_response`, so (a)/(b) ship green. | `tests/probes/probe_pkg_http.xi` after `xiom pkg install xiom.http` (sha256 `f8b59d9e...`); with `use xiom.http.types;` added, compile succeeds and the parser returns the error above. | any consumer of `xiom.http`'s parser is blocked until a re-ship; the fix is mechanical (`*pos_ref` + explicit import) plus parser KATs |
| 2026-10-05 | `xiom.http` v0.1.0 | `src/server.xi` is a ~36-line shell (`server_new`/`server_listen`/`server_handle`/`server_close`) with no accept loop or routing; consumers must build their own server (PULSE did). If the package intends to own HTTP serving, this is the gap; otherwise document it as a stub. | installed package `src/server.xi:1-36`; PULSE `src/server.xi` | unclear package contract; a consumer expecting `server_listen` to serve is misled |

**Positive:** `xiom.cookie` v0.1.1 (8/8 in `probe_pkg_step2.xi`: jar
parse/get/serialize) and `xiom.jwt` v0.1.1 (8/8: shape/alg/claim/exp) are
clean consumer packages on v0.63.1. Thank you.

**Adoption blocker to track (compiler-side):** installed packages are not
mapped into the compiler's module catalog (C-PULSE-02 in
`docs/COMPILER-FINDINGS-PULSE.md`); PULSE must list each installed
package's `src/` in `xiom.toml` `source-roots`. Registry adoption will stay
manual until that lands.

## Proposed packages (PULSE needs; reusable by any XIOM service)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence from PULSE |
|---|---|---|---|---|
| `xiom.router` | Route table for HTTP servers: exact + path-parameter routes (`/api/items/:id`), method matching, aggregated 404/405, deterministic first-match order | framework/app concern; will grow (groups, wildcards) and should not sit in the zero-dep core | xiom.std | PULSE `src/server.xi handle_route` is an if/else chain with hand-rolled 404/405; Step 2 needs params/middleware hooks |
| `xiom.session` | Server-side session store: id generation (crypto), TTL/expiry, memory backend, cookie binding, rotate-on-login | app policy (storage, lifetime, security posture), not language core | xiom.std, xiom.cookie, xiom.crypto | S9 lists auth/session; PULSE Step 2 cookie+session; currently would be PULSE-local |
| `xiom.jwt` v0.2 (or `xiom.jwt.hs256`) | HS256 sign + verify on top of `xiom.jwt`'s structural decode: alg allowlist, `exp`/`nbf` enforcement, constant-time MAC compare, claim validation helpers | crypto policy + token grammar; `xiom.jwt` already owns decode; signing belongs beside it, not in stdlib | xiom.std, xiom.jwt, xiom.crypto (SHA-256/HMAC now link under `XIOM_RUNTIME_DIR`) | `xiom.jwt` v0.1.1 description: "no signature verification"; PULSE Step 2 JWT is blocked on it |
| `xiom.ratelimit` | Keyed rate limiting (per-IP/route/user): token bucket + fixed window, explicit clock injection, 429 envelope, deterministic tests | middleware/policy, not core | xiom.std | S9 lists rate; PULSE Step 2+ hardening; no-registry equivalent today |
| `xiom.metrics` | Service metrics: counters/gauges/histograms with labels + Prometheus text exposition + scrape endpoint helper | infra/ops concern | xiom.std | S9 metrics; PULSE Step 2 metrics + Step 3 soak observability |
| `xiom.static` | Static file serving: MIME mapping, ETag/Last-Modified, Range, path-traversal guard, `Cache-Control` policy | app-level policy; filesystem + HTTP semantics | xiom.std (stdlib has `xiom.net.mime` to reuse) | S9 static; PULSE later slices |
| `xiom.kv` | Embedded, pure-XIOM log-structured KV store: append-only segment write, crash-safe reopen, tombstones, compaction, optional snapshot. PULSE Step 3 storage needs a durable local store; `xiom.bolt` v0.1.2 is a read-only bbolt page parser, and `xiom.sql` is not in the registry (checked 2026-10-05) | storage engine = package domain; must not drag FFI into stdlib | xiom.std | PULSE Step 3 ("most-tested option first"): without it, PULSE ships a JSONL append store locally and the ecosystem lacks an embedded store for any service |
| `xiom.http.middleware` | Composable middleware chain over request/response envelopes with built-ins: request-id, structured access log, recover-to-500, CORS, CSRF token helpers | app framework concern; needs router/envelope types first | xiom.std (+ router types if shared) | S9 lists middleware/cors/csrf/xss; PULSE Step 2 audit/log envelope |

## Suggested order for the packages lane

1. `xiom.http` 0.1.1 (fix parser import + `*pos_ref` + add parser KATs) --
   unblocks registry consumers immediately.
2. `xiom.jwt` HS256 (PULSE Step 2 JWT; stdlib crypto is now linkable).
3. `xiom.router` + `xiom.http.middleware` (PULSE Step 2 skeleton).
4. `xiom.kv` (embedded store; PULSE Step 3), then
   `xiom.session`, `xiom.ratelimit`, `xiom.metrics`, `xiom.static`
   (Step 2-4 hardening).

**Registry notes (checked 2026-10-05):** `xiom.sql` is not published
(`xiom pkg info xiom.sql` -> empty); `xiom.bolt` v0.1.2 is pure-XIOM but
read-only (bbolt page parser); no embedded writable KV/storage package is
available. PULSE Step 3 therefore starts with a zero-dependency JSONL
append store and files `xiom.kv` above.

## Contract notes for the packages lane

- PULSE consumes from the registry only. If a package is incubating that
  is fine; publish it and PULSE will test it as a consumer and file rows
  here.
- Please include a 3-line consumer snippet in README (the exact `use`
  lines) -- (a)/(b) above were only visible from a consumer project, not
  from the package's own suite.
- New packages should stay stdlib-only or declare deps explicitly; PULSE's
  `xiom.toml` currently wires each installed package `src/` manually
  (C-PULSE-02).
