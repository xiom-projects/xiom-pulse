# PULSE feature / test evidence map

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Created:** 2026-11-06. **Scope:** read-only audit of `docs/PARITY-MATRIX.md`
against the current test suites, probes, smoke scripts, and CI/release
workflows. **Not** a replacement for the matrix and **not** a status upgrade:
the matrix stays the single catalog; this file records what actually proves
each row today.

**Snapshot (read-only run of `scripts/parity_score.ps1`, 2026-11-06):**

```
rows: 107 (Beacon applicable 73, Station applicable 107)
Beacon  (package):    60.3%   assessed coverage  89.4%  (66/73)
Station (standalone): 70.9%   assessed coverage  98.8%  (106/107)
```
**Post-audit matrix corrections (2026-11-06):** W-06 Station M->A (Range
reaches `static_serve`; `probe_pkg_static` proves 206), O-09 Station M->A
(N-port workers + reuseport config/smoke), S-08 ?->M (login is user-only; no
password field/hash), O-13 evidence refreshed to 14.5 KB/req (after the
gate cut + HandlerOut assembly). Re-run: **Beacon 60.3% (91.1% assessed),
Station 71.7% (100%)**. The snapshot above is the pre-correction read.

**Post-audit CI wiring (2026-11-07):** `scripts/rss_gate.py` is the 25 KiB
PR retention gate (Linux x64 + Windows); `openapi --check` runs on
Unix+Windows; `rate_smoke`, `crash_test`, `probe_pkg_static`, `probe_pkg_kv`,
`probe_outbound_guard`, `probe_audit_rotate` and the KV 60 s soak run on
Linux; `ws_auth_smoke.py` runs on Unix (the Windows `.ps1` remains);
`scaffold_smoke.py` is in CI. `proxy_e2e` stays manual; strict NUL and the
24 h/1M stay heavy. The rows below are the pre-wiring audit.

**Post-security-corpus re-run (2026-11-07):** the framing/static findings
downgraded P-03/W-05 to `A`; the upload fix restored S-12 Station to `P`.
Re-run **Beacon 58.9% (94.4% assessed), Station 69.5% (100%)** after the
WS/SSE findings (W-08 -> A, W-12 -> M; W-09 Station -> P after the guard).
Framing/WS are fixed upstream (`30bacfa`/`e8ab289`) and the PULSE WS guard is
fixed, awaiting the next verified pin; the static finding remains open. The
memory floor is **13.9 KB/req** after the Date/send cuts. See
`docs/SECURITY-FINDINGS-2026-11-07.md`.

The score is capability parity, not evidence quality. A row can be `P` and
still have no per-PR test; those rows are flagged in section 9.

**Working-tree caveat (2026-11-06):** the scaffold, cookie/auth fuzz and WP4
reuseport slice landed after this snapshot. The counts/O-09 row below were
updated for those gates; re-run the inventory before using exact numbers.
The WP4 supervisor, control-port drain, reload and 1/2-worker curve remain
open.

## 0. Method note

- **Evidence over LOC.** A capability exists only when its observable
  contract is demonstrated. Line count and code presence are not evidence.
- **No status upgrade without a test.** `P`/`E` requires an automated happy
  and failure path (matrix rule); this audit does not raise a row because a
  source file exists.
- **Grade the evidence, not the intention.** `CI` (every PR), `REL`
  (release workflow only), `HVY` (weekly heavy workflow), `MAN` (manual
  probe/script with no workflow reference), `DOC` (documentation only), or
  `NONE`.
- **Mark partial coverage honestly.** A test that exercises the happy path
  but not the failure path does not close the matrix row.
- **Do not infer from green historical runs.** A quoted CI run number is not
  a current gate unless the workflow still runs that step.

---

## 1. Test inventory and where it runs

| Artifact | Approx. checks | Where it runs | Notes |
|---|---:|---|---|
| `tests/test_http.xi` | 95 | CI every leg | parser, chunked, routing primitives, rate buckets, security headers |
| `tests/test_app.xi` | 269 `check()` call sites | CI every leg | app config (incl. reuseport/worker-id), sessions, CSRF, JWT, store, uploads, site, OpenAPI, game, forms |
| `tests/test_stream.xi` | 99 `check()` call sites | CI (Unix + Windows) | SSE/WS pure units, Origin, stream auth |
| `tests/test_smoke.xi` | 4 | CI every leg | version literal + basic string/int |
| `tests/test_migrations.xi` | 19 | CI (Unix only) | SQL migrations runner |
| `tests/test_sql.xi` | 53 | CI (Unix only) | SQL store, paging, transactions, injection |
| `tests/fuzz_parsers.xi` | ~70k iterations | CI every leg | HTTP, multipart, urlenc, HTML, static path, JWT |
| `tests/fuzz_cookie.xi` | 20k iterations | CI every leg | Cookie/Set-Cookie parse+serialize, session-id, CSRF; `known_crlf` contract caveat |
| `scripts/worker_smoke.{sh,ps1}` | 2 workers | CI Unix + Windows | N-port baseline: two workers on 18201/18202, both `/health` 200 |
| `scripts/scaffold_smoke.py` | 5 checks | CI Unix + Windows | temp app from `scaffolds/api`: build, health/hello/root/echo/404 |
| `scripts/http_smoke.{sh,ps1}` | 139 `pulse_check` calls | CI every leg | live server, framing, deadlines, keep-alive, sessions, store, static, gate order |
| `scripts/gate_order.py` | 11 executed (12 call sites) | via `http_smoke` on every leg | CSRF/rate/OPTIONS/quit ordering |
| `scripts/stream_smoke.py` | 20 | CI every leg | live SSE + WS handshake/frames/fragmentation |
| `scripts/ws_auth_smoke.ps1` / `.py` | 11 | CI Windows + Unix | stream auth + log redaction |
| `scripts/site_smoke.{sh,ps1}` | 15 | CI every leg | dynamic site scaffold, form, 404, traversal |
| `scripts/rate_smoke.{sh,ps1}` | pass/fail legs | release + PR CI (Linux) | global + per-route rate policy |
| `scripts/crash_test.{sh,ps1}` | 6 | release + PR CI (Linux) | JSONL crash/torn-tail recovery |
| `scripts/store_soak.{sh,ps1}` | pass/fail legs | release + PR CI KV 60 s (Linux), HVY | JSONL and KV write soak/reopen |
| `scripts/rss_probe.{sh,ps1}` | informational | HVY weekly | reports KB/request; not a pass/fail gate |
| `scripts/rss_gate.py` | 75 s / 200 ms slope | CI Linux x64 + Windows | 25 KiB/req PR retention tripwire (OLS+Theil-Sen) |
| `scripts/soak_bttger.py` | 6,500 req / 60 s | manual / ops | bttger mix at 100 req/s; memory gate harness; 24 h projection gate |
| `scripts/ws_negative_corpus.py` | 14 frames | manual / CI known-gap | RFC 6455 negative frames; **critical MSB-length crash** |
| `scripts/sse_reconnect_probe.py` | 9 checks | manual / CI | SSE id/retry/Last-Event-ID/disconnect |
| `scripts/openapi_drift_probe.py` | 9 checks | manual / CI | bidirectional route/doc drift |
| `scripts/schema_matrix_probe.py` | 17 checks | manual / CI | R-14 input schema matrix |
| `scripts/gap_probe_lib.py` | shared | support | scrubbed server harness |
| `scripts/repro_check.{sh,ps1}` | 1 hash compare | CI Linux x64 | same-host payload only |
| `scripts/sbom.py` | schema/count assertions | CI Linux + release | CycloneDX SBOM |
| `tests/probes/*` | varies | `MAN` unless noted | `probe_sqlite` is built in CI; the rest are manual |

**CI coverage is asymmetric:** the Unix and Windows PR legs run the suites,
HTTP smoke, stream smoke, site smoke, and fuzz; only Windows runs
`ws_auth_smoke`. `rate_smoke`, `crash_test`, and KV `store_soak` are release
legs, not PR gates. `rss_probe` is explicitly informational (`scripts/rss_probe.sh:15`:
"growth is informational"; the exit code only gates server start/stop).

---

## 2. Evidence map — protocol / HTTP core

Legend for **Status**: `B` = Beacon, `S` = Station. `P` parity, `E` exceeds,
`A` partial, `M` missing, `?` unassessed, `N/A` not applicable. **Ev.** grades:
`CI`, `REL`, `HVY`, `MAN`, `DOC`, `NONE`.

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| P-01 | Request line, headers, methods | B=P / S=P | `test_http`: parse ok, method, target, version, header count, header_get; `http_smoke`: health/echo (CI) | none material | port a raw-socket method-matrix (all methods + lowercase/reject) into `http_smoke` |
| P-02 | Chunked decoding | B=P / S=P | `test_http`: chunked parse/multi-chunk/trailer/ext; `test_app`: te chunked accepted; `http_smoke`: chunked (CI) | no chunked extension/trailer abuse assertion at the live layer | add chunk-size overflow + trailer-injection negatives |
| P-03 | TE/CL smuggling rejection | B=A / S=A | `test_app`/`http_smoke`: te+cl 400, te gzip 501; `test_framing` + `security_smoke framing` (known-gap) | stdlib **30bacfa** fixes the framing shapes (pending pin); the v0.65.6 corpus is known-red | verify the strict corpus on the next pin |
| P-04 | `Expect: 100-continue` | B=P / S=P | `test_http`: expects_continue; `http_smoke`: expect 100 (CI) | no test for `Expect` with oversized/invalid body | add 100-continue + cap/malformed tail cases |
| P-05 | Keep-alive + pipelining | B=P / S=P | `http_smoke`: ka first/second, pipelined, HTTP/1.0, idle, garbage (CI) | no half-close/unread-body/early-response case from the design test plan | port the remaining `DESIGN-KEEPALIVE-DEADLINES` Phase B cases to a raw-socket smoke |
| P-06 | Read/write/idle deadlines (slowloris) | B=P / S=P | `http_smoke`: slowloris 408, write-stall dropped, loop alive, idle silent close (CI) | no unit-level timeout test; platform behavior only exercised live | add a deadline matrix (read/write/idle, 0 = disabled warning) |
| P-07 | Header/body caps | B=P / S=P | `test_http`: header_overflow, too many headers; `gate_order` (via `http_smoke`): 413 oversized CL; `test_app`: upload part cap 413 (CI) | no explicit body-cap boundary test at exactly cap/cap+1 | add cap boundary table (headers, body, single header line) |
| P-08 | Malformed request -> 400 and close | B=P / S=P | `test_http`: incomplete/malformed line/header; `http_smoke`: garbage closes 400, loop alive (CI) | bare-LF / NUL-in-head behavior is only fuzzed with `FUZZ_STRICT_NUL=0` | run fuzz with `FUZZ_STRICT_NUL=1` and add NUL/bare-LF status assertions |
| P-09 | HTTP/1.0 close semantics | B=P / S=P | `http_smoke`: http10 close, no keep-alive (CI) | none material | add HTTP/1.0 with `Connection: keep-alive` (must still close) |
| P-10 | Response framing (CL, HEAD/204/304) | B=P / S=P | `test_http`: status 304; `http_smoke`: HEAD CL, assets 304; `test_app`: single Content-Length (CI) | no 204 response assertion | add 204/304/HEAD no-body matrix |
| P-11 | HEAD/OPTIONS/405/Allow | B=P / S=P | `test_http`: route 405; `test_app`: 405 + Allow; `http_smoke`: 405, CORS preflight; `gate_order`: OPTIONS bypass (CI) | none material | add Allow-header correctness for multi-method routes |
| P-12 | HTTP/2 | B=M / S=M | NONE | not implemented | negative: no h2 upgrade/ALPN claim; document non-goal |
| P-13 | HTTP/3 | B=M / S=M | NONE | not implemented | same as P-12 |
| P-14 | In-process TLS | B=M / S=M | `proxy_e2e` edge TLS only (MAN) | no in-process TLS; edge test not in CI | wire `proxy_e2e` into CI or mark manual in the matrix |
| P-15 | Response compression (gzip/br/zstd) | B=M / S=M | NONE | not implemented | negative: no `Content-Encoding` without negotiation |
| P-16 | Connection limits / backpressure | B=A / S=A | `test_http` caps; `http_smoke` deadlines (CI) | no connection cap/backpressure test; matrix says so | accept-loop test: N+1 connections, no starvation, clean close |
| P-17 | HTTP client / reverse proxy | B=M / S=M | `src/outbound.xi` + `outbound_transport.xi`; `probe_outbound_guard` / `probe_outbound_transport` (MAN) | matrix has no outbound/SSRF row; transport is not wired to the server | add a matrix row for outbound SSRF guard; wire `probe_outbound_guard` into CI |

## 3. Evidence map — routing and requests

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| R-01 | Static + parameterised routes | B=P / S=P | `test_app`: route health/item/params; `test_http`: route tests (CI) | no duplicate-param or trailing-slash route test | add duplicate param + empty param + slash-edge cases |
| R-02 | Route groups / prefix nesting | B=M / S=A | `test_app`: `/v1` path map/health/version/events/link (CI) | only `/v1` normalisation; no generic group/prefix API | add a nested-prefix unit (`/v1/admin/...`) with params + 405 |
| R-03 | Wildcard / catch-all routes | B=A / S=A | NONE for path wildcards; only rate-policy `*` method (`test_http`: route rate wildcard method) | catch-all route behavior untested | `/*path` catch-all: nested path, traversal, 404 fallback |
| R-04 | Per-route middleware/policy | B=P / S=P | `test_http`: route rates; `test_app`: rate; `rate_smoke`: route policy (REL) | route policy smoke is not a PR gate | move `rate_smoke` route leg into CI |
| R-05 | Global middleware chain | B=P / S=P | `test_app`: dispatch; `http_smoke`: gate order; `test_http`: route rates (CI) | no explicit hook-order unit beyond gate order | add a hook order test (before/after, error path) |
| R-06 | Path normalisation / redirects | B=? / S=A | `test_app`: site dir 301, query preservation (CI) | no general `//`, dot-segment, percent-encoded traversal matrix | normalisation table: `//`, `/a/../b`, `%2e%2e`, slash, query |
| R-07 | 404/405 + Allow | B=P / S=P | `test_app`, `http_smoke` (CI) | none material | add 405 for every method on a P0 route |
| R-08 | Query parsing (multi-value) | B=P / S=P | `test_http`: parse_query count/decoded/flag; `test_app`: item query (CI) | no duplicate-key order test at route level | add repeated-key ordering + empty value + `+`/`%00` |
| R-09 | `application/x-www-form-urlencoded` | B=A / S=P | `test_app`: form ct/plus/percent/repeated/first; `site_smoke`: form (CI) | Beacon package-level form test absent | add a package-level urlenc probe to CI |
| R-10 | JSON body parsing + caps | B=P / S=P | `test_app`: login long/invalid; `http_smoke`: echo invalid/longer; `fuzz_parsers` (CI) | no nested-depth/size boundary test | add JSON depth + exact cap boundary test |
| R-11 | Multipart uploads | B=? / S=P | `test_app`: upload happy/traversal/boundary/cap; `http_smoke`: upload; `fuzz_parsers` multipart (CI) | Beacon unassessed; no duplicate field/part-header abuse | wire a package multipart probe; add duplicate field + header caps |
| R-12 | Cookie parse/set | B=P / S=P | `test_app`: cookie parse/absent; `http_smoke`: login/logout cookies (CI) | no malformed-cookie/large-cookie test | add cookie injection (semicolon/comma/NUL) matrix |
| R-13 | Content negotiation (`Accept`) | B=M / S=M | NONE | not implemented | negative: absent `Accept` defaults; unsupported -> documented |
| R-14 | Schema validation of input | B=M / S=A | `test_app` + `schema_matrix_probe`: missing/wrong-type/nested/array/length/malformed -> 400 | extra fields accepted by design; Unicode length byte-based; no enum; number/bool/object/array rules unexercised | add enum/UTF-8 length policy/extra-field mode + route coverage |
| R-15 | Dependency injection | B=N/A / S=M | NONE | not implemented | document as non-goal for 1.0 |
| R-16 | Typed response models | B=M / S=A | `test_app`: envelope/status; `openapi` (CI) | no response-schema validation | validate each route response against the OpenAPI schema |

## 4. Evidence map — responses, static, streams

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| W-01 | JSON/text/bytes responses | B=P / S=P | `test_app`, `http_smoke` (CI) | none material | add binary response + non-UTF8 bytes case |
| W-02 | Structured error envelope | B=P / S=P | `test_app`: envelope code/message; `http_smoke`: 404 status (CI) | no schema assertion for every error code | error-code envelope contract test |
| W-03 | Request IDs | B=P / S=P | `test_app`: rid present/omitted; `http_smoke`: 404 rid (CI) | no uniqueness/collision test | rid uniqueness + propagation into log/audit |
| W-04 | Static files + ETag/304 | B=? / S=P | `test_app`: site assets/304; `http_smoke`: assets 304; `site_smoke`; `probe_pkg_static` (MAN) | Beacon unassessed; no package-level CI | wire `probe_pkg_static` (200/304/206/404) into CI |
| W-05 | Traversal guard | B=A / S=A | `test_app`/`site_smoke`/`http_smoke`/`fuzz_parsers`: encoded/dot-dot/backslash/NUL blocked; `security_smoke static` | **junction/symlink inside the root escapes** (2026-11-07; `REL-20261107-1032-pulse-2`) | canonical/realpath check + symlink/junction tests |
| W-06 | Range requests | B=M / S=M | Station `src/server.xi:136` passes `Range` to `static_serve`; `probe_pkg_static` (the `xiom.static` package): 206/range parse (MAN) | **matrix says M but Station code and the package probe support it**; no route-level live test | live Range test: single, open-ended, unsatisfiable, malformed; update Station to A |
| W-07 | Efficient file streaming (sendfile) | B=M / S=A | `http_smoke` 50 MB write-stall only (CI) | no sendfile/throughput/RSS assertion; file is copied | 50 MB static transfer: RSS ceiling + time; prove no full-file buffer |
| W-08 | SSE | B=A / S=P | `test_stream`/`stream_smoke` + `sse_reconnect_probe` strict 11/11: ids, retry, resume, 8 disconnects, fds 61->61, exactly-once log | Beacon A; the general non-derivable replay needs a ring | keep the strict SSE probe; add the ring if a payload feed needs replay |
| W-09 | WebSocket handshake/frames/fragmentation | B=A / S=P | `test_stream` + `ws_negative_corpus` strict **14/14**; PULSE guard in `src/stream.xi` | Beacon still depends on the stdlib parser; `e8ab289` pending the next pin; reserved opcodes 3-7/11-15 close 1003 not 1002 | Beacon pin verification; opcode cleanup |
| W-10 | WS permessage-deflate | B=M / S=M | NONE | not implemented | negative: no extension negotiated |
| W-11 | WS subprotocol negotiation | B=M / S=M | NONE | not implemented | negative: requested subprotocol not echoed |
| W-12 | SSE event IDs + reconnect semantics | B=M / S=P | `sse_reconnect_probe` strict 11/11: `id:` monotonic, `retry: 3000`, `Last-Event-ID: 2` -> resume at 3 | Beacon M; non-derivable payload replay needs a bounded ring | add the ring only if a persisted/opaque feed needs true replay |
| W-13 | Templating / SSR | B=N/A / S=A | `test_app`: site mode; `site_smoke` (CI); `examples/site` | no template caching/compression/i18n | template escaping matrix + custom 404 (escaping partly covered) |
| W-14 | OpenAPI generation | B=M / S=A | `test_app`/`http_smoke`; `openapi_drift_probe`: all 25 router routes present, `--check` failure path works | `GET /assets/{path}` documented but special-cased; `GET /api/sse`/`ws` in `routes` but not the doc | add the missing paths + bidirectional gate |
| W-15 | CORS responses + preflight | B=? / S=P | `test_app`: cors list/star/off; `http_smoke`: preflight 204 (CI) | Beacon unassessed; no wildcard+credentials negative | package CORS probe + credentials/wildcard rejection |

## 5. Evidence map — security and auth

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| S-01 | Security headers (helmet set) | B=P / S=P | `test_http`: nosniff/frame/referrer/coop/corp/coep/hsts/dns/xss/csp (CI) | no per-status production check | assert headers on 200/404/500 and static |
| S-02 | CSRF tokens | B=A / S=P | `test_app`: csrf match/mismatch/absent; `http_smoke`: logout 403 without CSRF; `gate_order`: CSRF order (CI) | no Origin/Referer check, token rotation, double-submit | CSRF negative matrix: missing/mismatch/replayed/rotated + Origin |
| S-03 | Sessions (cookie + store) | B=A / S=P | `test_app`: create/get/drop/cookie; `http_smoke`: login/me/logout (CI) | in-process `Vec` store (`src/session.xi:28`); no expiry/restart/fixation test | expiry, session fixation, restart semantics (documented in-memory) |
| S-04 | JWT HS256 issue/verify | B=P / S=P | `test_app`: sign/verify/wrong-secret/tamper/exp; `fuzz_parsers`: JWT; `ws_auth_smoke` (CI/Windows) | no `nbf`/`iss`/`aud`/alg-confusion tests | JWT claims matrix (nbf/iss/aud/alg=none/HS vs other) |
| S-05 | JWT asymmetric algs (RS/ES/EdDSA) | B=M / S=M | NONE | not implemented | negative: only HS256 accepted |
| S-06 | JWE / JWK key sets | B=M / S=M | NONE | not implemented | negative: compact JWE rejected |
| S-07 | OAuth/OIDC client | B=N/A / S=M | NONE | not implemented | document non-goal/post-1.0 |
| S-08 | Password hashing | B=M / S=M | `src/users.xi` + `tests/test_users.xi` (82 PASS): strict PBKDF2 record, salt, constant-time verify, rehash, JSONL store. Design: `docs/DESIGN-PASSWORD-AUTH.md`. | **routes not wired; 600k = 1.9-2.0 s vs 250/500 ms**; native-hash ask `REL-20261107-1337-pulse` | wire login/token + rate limit/lockout; run the 600k performance gate |
| S-09 | Rate limiting (global + route) | B=P / S=P | `test_http`: bucket/route rates; `test_app`: rate; `rate_smoke` (REL) | `rate_smoke` is not a PR gate; no distributed/multi-worker test | move `rate_smoke` to PR CI; add per-IP vs global semantics |
| S-10 | CORS allowlist | B=P / S=P | `test_app`: cors; `http_smoke`: allow origin/preflight (CI) | no credentials/wildcard interaction | add `Access-Control-Allow-Credentials` matrix |
| S-11 | Stream Origin/auth policy | B=P / S=P | `test_stream`: origin/auth; `stream_smoke`: Origin; `ws_auth_smoke`: 11 checks (CI **Windows only**) | Unix CI never runs `ws_auth_smoke` | run `ws_auth_smoke` on Unix too |
| S-12 | Upload size/type caps | B=A / S=P | `test_app`/`http_smoke`: part/total/header caps; `security_smoke upload` strict 29/29 | **fixed 2026-11-07:** default-safe ext/MIME allowlist, 8 KiB part-header cap, duplicate disposition reject; `.txt` still 200 | keep the strict corpus in the release gate |
| S-13 | Secret redaction in logs | B=P / S=P | `test_stream`: redact token/access_token; `ws_auth_smoke`: log redacts token (CI/Windows) | no audit-file redaction assertion in CI | assert both access log and audit file redact query tokens |
| S-14 | Audit log + rotation | B=P / S=P | `probe_audit_rotate` (MAN); `test_app`: audit_sync config; `crash_test` (REL); `test_stream`: redaction | **rotation is not automated in CI**; only a manual probe | wire `probe_audit_rotate` into CI; assert line content + `.1` rotation |
| S-15 | TLS termination guidance/automation | B=N/A / S=A | `docs/DEPLOYMENT.md` + `proxy_e2e` (MAN) | edge TLS e2e is not in CI | wire `proxy_e2e` into CI or mark manual-only |
| S-16 | mTLS / client certificates | B=M / S=M | NONE | not implemented | document as edge/non-goal |
| S-17 | External audit + fuzzing | B=A / S=A | `fuzz_parsers` + `scripts/fuzz_parsers.*` (CI) | no external audit; no session/OpenAPI/release-input fuzz; strict NUL off | add session/OpenAPI fuzz targets; enable `FUZZ_STRICT_NUL=1` |

## 6. Evidence map — data and state

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| D-01 | Embedded KV with transactions/durability | B=N/A / S=P | `test_app`: JSONL store; `probe_pkg_kv` (MAN); `store_soak` KV (REL/HVY) | **KV backend has no PR-CI suite**; KV transactions not exercised | KV suite in PR CI: open/put/get/reopen/compact/duplicate-key |
| D-02 | Crash recovery / torn-write healing | B=N/A / S=P | `test_app`: torn append/heal; `crash_test` (REL); `probe_*` (MAN) | crash test is release-only; KV crash not covered | crash/restart in PR CI for JSONL **and** KV |
| D-03 | SQL driver | B=N/A / S=P | `test_sql` + `probe_sqlite` (CI); SQL serving opt-in | stock app is SQL-free by design | run the served SQL path only if/when enabled |
| D-04 | Migrations | B=N/A / S=P | `test_migrations` (CI) | no two-runner lock race / first-run race test | two concurrent runners: one wins, one learns live lock |
| D-05 | Transactions | B=N/A / S=P | `test_sql`: begin/rollback/commit (CI) | no nested/savepoint test | savepoint/nested behavior (documented unsupported) |
| D-06 | Repository/CRUD + paging | B=N/A / S=P | `test_sql`: find/list/page/limit (CI) | no concurrent paging test | page boundary under concurrent writes |
| D-07 | Query builder | B=N/A / S=M | NONE | raw SQL only | document non-goal |
| D-08 | ORM / models | B=N/A / S=M | NONE | not implemented | document non-goal |
| D-09 | Connection pooling | B=N/A / S=A | NONE; `DESIGN-SQL-STORE` lists pooling out of scope | **matrix says A but there is no pool and no test** | mark M/N/A (post-worker) or add single-connection concurrency test |
| D-10 | Caching layer | B=N/A / S=M | NONE | not implemented | document post-1.0 |
| D-11 | Background jobs / queues | B=N/A / S=M | `DESIGN-MIDDLEWARE-JOBS` (DOC) | design only | jobs core test when landed |
| D-12 | Job retries / scheduling | B=N/A / S=M | `DESIGN-MIDDLEWARE-JOBS` (DOC) | design only | retry/backoff/schedule test |
| D-13 | Pub/sub | B=N/A / S=M | NONE | not implemented | document non-goal |
| D-15 | Multi-tenancy | B=N/A / S=M | NONE | not implemented | document non-goal |

## 7. Evidence map — operations and observability

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| O-01 | Health endpoint | B=N/A / S=P | `http_smoke`: health 200/json (CI) | none material | add health under load + during drain |
| O-02 | Prometheus metrics | B=N/A / S=P | `test_app`: counters/histogram/render; `http_smoke`: metrics (CI) | no cardinality/label test | metrics label/cardinality contract |
| O-03 | Structured access logs | B=A / S=P | `src/server.xi:845` access_log; `ws_auth_smoke`: redaction (CI/Windows) | **no test asserts JSON line shape/one-line-per-request** | access-log schema + exactly-once + rid test |
| O-04 | Audit log + rotation | B=N/A / S=P | same as S-14 (MAN + REL) | rotation not in CI | wire `probe_audit_rotate` into CI |
| O-05 | Tracing / OpenTelemetry | B=M / S=M | NONE | not implemented | document post-1.0 |
| O-06 | Graceful shutdown / drain | B=A / S=A | `http_smoke`: QUIT clean exit (CI) | quit flag only; no in-flight drain test | drain: stop accept, finish in-flight, exit 0, no new accepts |
| O-07 | Config validation + `--check-config` | B=N/A / S=P | `test_app`: cfg warnings; `http_smoke`: CLI (CI) | no config-overlay fuzz | config precedence + invalid-value matrix |
| O-08 | CLI (routes/openapi/version) | B=N/A / S=P | `http_smoke`: version/routes/openapi/check-config (CI) | `openapi --check` not tested | add `openapi --check` success + drift failure |
| O-09 | Cluster / scale-out | B=M / S=M | `DESIGN-WORKERS` + checklist (DOC); `worker_smoke` (CI Unix+Windows); `N-PORT-EDGE` (DOC); `PULSE_REUSEPORT`/worker-id config | no supervisor, control-port drain, reload or 1/2-worker curve; sequential accept is still the measured ceiling | single-accept ceiling test; then drain/reload and the 1/2-worker curve |
| O-10 | Hot reload | B=M / S=M | NONE; Phase B blocked | not implemented | after WP4: zero-failed-request reload |
| O-11 | Container/systemd guidance | B=N/A / S=A | docs only (DOC) | no container/systemd smoke | container smoke: build, run, health, shutdown |
| O-12 | Reproducible release + attestations | B=N/A / S=E | `repro_check` (CI Linux x64), `sbom.py` (CI), provenance/checksums/tag guard (REL) | **same-host payload only; cross-host/zip open; release artifact not executed** | unzip artifact, run `--version`, verify tag/checksum; cross-host repro |
| O-13 | Flat memory under soak | B=M / S=M | `rss_gate` (CI, 25 KiB); `soak_bttger` (100 req/s, 14.0 KiB/req); `rss_probe`/`soak_http` (HVY) | 24 h projection ~124 GB, cap ~178 s; the 24 h/1M gate is not met | 24 h @ 100 req/s on the bttger mix after the floor is flat |
| O-14 | Published c1/c10 benchmark | B=N/A / S=A | `benchmarks/bttger/results/*.json` (MAN) | no harness rerun gate, no peer comparison | rerun harness in CI/nightly; publish methodology |
| O-15 | Published 1M soak | B=N/A / S=M | NONE; blocked by O-13 | not run | after O-13: capped 1M soak |
| O-16 | Fuzzing harness | B=A / S=A | `fuzz_parsers` + `fuzz_cookie` (CI) | OpenAPI/stream fuzz, strict NUL, cookie package fix | OpenAPI/stream fuzz + strict NUL + cookie package fix |

## 8. Evidence map — ecosystem and developer experience

| ID | Capability | Status | Evidence (grade) | Gap | Proposed highest-value test |
|---|---|---|---|---|---|
| E-01 | Concept/reference/deployment docs | B=A / S=P | docs set (~6k lines) (DOC) | no link/claim validation | docs link + version-literal check in CI |
| E-02 | Tutorials and examples | B=A / S=A | `examples/site` + `site_smoke` (CI); `scaffolds/api` + `scaffold_smoke.py` (MAN) | scaffold smoke not in CI; minimal example not smoke-tested | wire `scaffold_smoke.py` + `examples/minimal` into CI |
| E-03 | Third-party middleware/plugins | B=M / S=M | NONE | none | document plugin model |
| E-04 | Package registry + supply-chain verification | B=N/A / S=E | `sbom.py` (CI), provenance + checksums (REL), SHA-pinned toolchain | registry signing/verification not exercised end-to-end in a test | verify a downloaded artifact against SBOM/provenance in CI |
| E-05 | Test harness + multi-OS CI | B=E / S=E | `ci.yml` 5 legs, suites x2, smoke, stream, site, fuzz (CI) | Unix lacks `ws_auth_smoke`; release fleet is narrower | mirror the full CI fleet in the release dry-run |
| E-06 | Versioning, release cadence, LTS | B=A / S=A | `test_smoke`: version literal; release guard (CI/REL) | no LTS/cadence test | grep old version literal before tag (release checklist step) |
| E-07 | Admin panel | B=N/A / S=M | NONE | not implemented | document non-goal |
| E-08 | i18n | B=N/A / S=M | NONE | not implemented | document post-1.0 |
| E-09 | Email | B=N/A / S=M | NONE | not implemented | document post-1.0 |
| E-10 | GraphQL | B=N/A / S=M | NONE | not implemented | document non-goal |
| E-11 | gRPC | B=N/A / S=M | NONE | not implemented | document non-goal |
| E-12 | Benchmark comparison vs peers | B=N/A / S=M | bttger results only (MAN) | no cross-framework run | add peer harness + published comparison |

---

## 9. Rows marked P/E/A with no automated evidence (or only manual/release evidence)

These rows are the honest gaps. "Automated" means a suite or smoke on a CI
leg; release-only and manual probes are called out separately.

| ID | Status | What is automated today | Why it is flagged | Action |
|---|---|---|---|---|
| R-03 | B=A / S=A | nothing for path wildcards (only rate-policy `*` method) | a partial claim with no test | add catch-all route test |
| W-12 | B=M / S=P | `sse_reconnect_probe` strict 11/11: IDs/retry/Last-Event-ID continuation | Beacon M; opaque-feed replay needs a ring | add the ring if required |
| S-14 / O-04 | S-14: B=P / S=P; O-04: S=P | config flag + redaction; rotation only `probe_audit_rotate` (MAN) | rotation is a manual probe, not a gate | wire probe into CI |
| D-01 | S=P (B=N/A) | JSONL suite; KV only `store_soak` (REL/HVY) + `probe_pkg_kv` (MAN) | KV has no PR-CI suite | add KV suite to CI |
| D-02 | S=P (B=N/A) | JSONL torn-tail in `test_app`; crash in `crash_test` (REL) | crash recovery is release-only; KV crash absent | move crash test to PR CI |
| D-09 | S=A (B=N/A) | nothing | matrix says "verify sqlite driver"; no pool exists | mark M/N/A or test single connection |
| O-03 | B=A / S=P | source path + redaction test | no structured-log format assertion | add log schema test |
| O-11 | S=A (B=N/A) | docs only | no deploy artifact test | container/systemd smoke |
| O-12 | S=E (B=N/A) | same-host repro + provenance + SBOM | cross-host/zip explicitly open; artifact not executed | add artifact acceptance + cross-host |
| O-14 | S=A (B=N/A) | result JSON files | no rerun in CI; not a test | nightly harness run |
| R-16 | B=M / S=A | envelope tests | no typed response model validation | schema-validate responses |

**Matrix/code contradictions found:**

- **W-06 Range requests is `M`, but Station passes `Range` to
  `static_serve` (`src/server.xi:136`) and `probe_pkg_static` proves
  `206`/range parsing in the `xiom.static` package.** Station should be at
  least `A`; there is no route-level live test. Beacon applicability
  depends on whether `xiom.static` is counted in the package tier.
- **S-08 Password hashing is `?` with "verify app login", but the login
  route creates a session from `user` only** (`src/server.xi`, route 4).
  There is no password field, hash, or compare. This is `M`, not `?`.
- **P-17 HTTP client says "server-only", but `src/outbound.xi` and
  `src/outbound_transport.xi` exist** (SSRF guard + libcurl transport,
  unwired; probes are manual). The matrix has no outbound/SSRF row.
- **W-04/W-05/R-11/S-12/W-15 are `?` on Beacon, but
  `tests/probes/probe_pkg_static.xi` and the Station suites exercise
  them.** They are manual/release evidence, so `?` is defensible today,
  but the package lane has more evidence than the matrix records.
- **S-03 Sessions is `P`, but the store is a process-local `Vec`**
  (`src/session.xi:28`). No restart/expiry/fixation test; multi-node
  sessions are explicitly unsolved in the game backlog. The row is
  arguably `A` for a production session claim.

---

## 10. Claim inconsistencies in STATUS / ROADMAP / CI

1. **STATUS check counts are stale against current sources.**
   STATUS says `95 / 239 / 4`; `test_http` still has 95 check calls,
   `test_smoke` 4, but `test_app.xi` now has **262** `check()` call sites
   (not 239). Similarly STATUS says Streams **83/83** while
   `test_stream.xi` has **99** call sites, and Migrations **21/21** while
   `test_migrations.xi` has **19**. Re-baseline the published numbers or
   stop publishing exact counts.
2. **HTTP smoke count drifted.** STATUS says **135/135**; current
   `http_smoke.sh` has **139** `pulse_check` call lines. `ci.yml` still
   says "**78-check HTTP smoke**" in its header comment. All three should
   agree or the comment should be removed.
3. **`gate-order 11/11` is accurate.** `gate_order.py` has 12 `check()`
   call sites but two are the pass/fail branches of one check; 11 execute.
4. **"Crash/durability 6/6, twice" is not a PR gate.** `crash_test` is
   only invoked by `release.yml` (Linux), not `ci.yml`. It is release
   evidence, not per-change evidence.
5. **"Rate-limiter smoke green" is release-only.** `rate_smoke` is in
   `release.yml`, not `ci.yml`. Unit coverage exists in `test_http`/
   `test_app`, but the end-to-end route policy is not a PR gate.
6. **ROADMAP WP1 claims a "CI retention gate" that does not exist.**
   `ci.yml` has no RSS/retention step. `heavy.yml` runs `rss_probe`
   weekly, and `scripts/rss_probe.sh:15` says growth is informational and
   the exit code only gates server start/stop. This is the largest
   claim/evidence mismatch.
7. **"All five platforms build, test and package" needs a qualifier.**
   `ci.yml` runs the full fleet on all five legs. `release.yml` runs the
   full fleet only on Linux; Windows and macOS release jobs run suites x2
   + HTTP smoke only (no stream/site/fuzz/ws-auth). The CI claim is true;
   the release-dry-run claim should say which checks ran.
8. **`ws_auth` is Windows-only in CI.** `ci.yml` invokes
   `ws_auth_smoke.ps1` only in the Windows leg; Unix relies on
   `test_stream` + `stream_smoke`. The 11/11 auth result is not proven on
   Unix in CI.
9. **Matrix W-06 and S-08 contradict the code** (section 5).
10. **Matrix O-13 still says "22 KB/req residual"** while STATUS and
    PROGRESS say **13.9 KB/req** after the router cache + gate cut + HandlerOut
assembly + Date/send cuts. The matrix
    evidence text is stale even though the status (`M`) is unchanged.
11. **PARITY-VISION's baseline is stale.** It records 58.4% / 69.1%
    (2026-10-30); the current script prints 60.3% / 70.9%. The vision
    document labels it a seeded baseline, but readers will read it as
    current.
12. **"Sessions (cookie + store)" is process-local.** STATUS and matrix
    `P` should say the store is in-memory, not durable or shared.

---

## 11. Top 10 missing tests, ranked by production risk

| # | Risk area | Why it matters | Missing test | Rows |
|---:|---|---|---|---|
| 1 | **Memory / sustained load** | The 13.9 KB/req (/health) and 14.0 KiB/req (bttger mix) floors are the production blocker; the 24 h projection is ~124 GB and the 256 MB cap trips in ~3 min. A 25 KiB/req PR gate and the bttger-mix harness exist. | Run the 24 h @ 100 req/s and 1M after the floor is flat; keep the PR gate as the tripwire. | O-13, WP1 |
| 2 | **Auth / session** | Login is username-only; no password hash; sessions are in-process; JWT only checks `exp`. | Password-auth test (wrong password, hash-at-rest, timing-safe compare) + session expiry/fixation/restart + JWT `nbf`/`iss`/`aud`/alg matrix. | S-08, S-03, S-04 |
| 3 | **Parser / framing** | Stdlib **30bacfa** fixes duplicate/conflicting CL, overflow, whitespace-colon and TE.TE; awaiting the next verified pin. The v0.65.6 corpus is still known-gap. | Verify the strict corpus on the next pin and run `FRAMING_STRICT_NUL=1`. | P-03, P-07, P-08 |
| 4 | **Static / traversal** | **Confirmed high:** a Windows junction/symlink inside the root escapes (`REL-20261107-1032-pulse-2`); encoded/dot-dot/backslash/NUL cases are blocked. | Fix `xiom.static` canonical/realpath; keep the corpus strict on Windows junctions and Unix symlinks. | W-05 |
| 5 | ~~**Uploads**~~ **Fixed 2026-11-07** | Strict corpus 29/29; default-safe extension/MIME allowlist, 8 KiB part-header cap and duplicate-disposition reject; `.txt` still 200. | Keep the strict upload corpus in the release gate. | S-12, R-11 |
| 6 | **Streaming / SSE / WS** | WS is strict 14/14 with the PULSE guard; SSE IDs/retry/Last-Event-ID continuation is strict 11/11. Only opaque-feed replay (ring) and Beacon pin remain. | Keep both corpora blocking; add the ring only if a payload feed needs true replay. | W-08, W-09, W-12, S-11 |
| 7 | **Durability / store** | KV crash/restart is only release/manual; crash recovery is not a PR gate. | PR CI: JSONL and KV crash/torn-tail/restart; assert count/seq/reopen/compact. | D-01, D-02 |
| 8 | **Validation + OpenAPI drift** | Schema validation is string-only; OpenAPI drift is one-way and `--check` is untested. | Schema matrix (missing/extra/type/nested/enum) -> 400; bidirectional OpenAPI drift gate + CLI `--check` failure case. | R-14, W-14 |
| 9 | **Scale-out / drain** | Single-accept loop is the measured ceiling; the N-port smoke exists, but there is no drain/supervisor test and no 1/2-worker curve. | Keep the N-port smoke; add the single-accept ceiling assertion, then supervisor/drain and 2-worker drain/reload with zero failed requests. | O-09, O-06 |
| 10 | **Release integrity** | Checksums/provenance exist, but the shipped artifact is never executed and repro is same-host only. | Release acceptance: unzip, run `--version` and health, verify tag/version/checksum/SBOM, then cross-host double-build. | O-12, E-04, E-06 |

---

## 12. Highest-value quick wins (wire existing evidence first)

These do not require new features; they convert manual/release evidence into
gates.

1. **Wire `probe_audit_rotate.xi` into CI** (S-14/O-04).
2. **Add a KV suite to CI** (D-01/D-02) using `probe_pkg_kv` plus
   `store_soak` in KV mode; include reopen/compact.
3. **Run `crash_test` in PR CI** (D-02), not only release.
4. **Run `rate_smoke` in PR CI** (S-09/R-04).
5. **Run `ws_auth_smoke` on Unix** (S-11), not only Windows.
6. **Run `probe_pkg_static` in CI** (W-04/W-05/W-06) and use it to
   reassess the Beacon rows.
7. **Run `probe_outbound_guard` in CI** and add an outbound/SSRF row to
   the matrix (P-17 adjacent).
8. ~~**Wire `scaffold_smoke.py` into CI** (E-02).~~ **Done 2026-11-06.**
9. **Run `openapi --check` in CI** and add the reverse drift check
   (W-14/O-08).
10. **Run `proxy_e2e` in CI or mark it manual** (S-15/P-14).
11. **Enable `FUZZ_STRICT_NUL=1`** and add session/OpenAPI fuzz targets
    (S-17/O-16).

---

## 13. Method (short)

This map treats a capability as proven only when an automated test covers
its happy and failure paths on a CI leg. Release-only and manual probes are
recorded as `REL`/`MAN` rather than silently counted. LOC, source-file
presence, design documents, and historical green run numbers are not
evidence of current behavior. Where a row is partly covered, the table says
which half is missing; no row should be upgraded on the strength of a
manual probe alone. The matrix remains the catalog; this file is the audit
trail behind it.
