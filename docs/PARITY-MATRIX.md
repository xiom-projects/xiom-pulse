# PULSE parity matrix

**Living catalog. Seeded 2026-10-30 from PULSE's docs/tests; `?` means
unassessed and counts as zero in the score.** See `PARITY-VISION.md` for the
rules. Reference codes:

`F` fasthttp, `H11` h11, `CH` chi, `G` gin, `FF` fastify, `FA` fastapi,
`H` helmet, `J` jose, `K` knex, `B` bbolt, `BM` bullmq, `WB` web-framework
benchmarks / xlcaptain, `--` production practice (no single clone).

Status: `M` missing, `A` partial, `P` parity, `E` exceeds, `?` unassessed,
`N/A` not applicable to that tier.

## Protocol / HTTP core

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| P-01 | HTTP/1.1 request line, headers, methods | P0 | P | P | F,H11 | http parser; smoke |
| P-02 | Chunked transfer decoding | P0 | P | P | F,H11 | smoke chunked |
| P-03 | TE/CL smuggling rejection | P0 | E | E | F,H11 | stricter rules; smoke |
| P-04 | `Expect: 100-continue` | P0 | P | P | F,H11 | smoke |
| P-05 | Keep-alive + pipelining | P0 | P | P | F,H11 | smoke |
| P-06 | Read/write/idle deadlines (slowloris) | P0 | P | P | F | smoke |
| P-07 | Header/body caps | P0 | P | P | F | config + smoke 413 |
| P-08 | Malformed request -> 400 and close | P0 | P | P | H11 | smoke |
| P-09 | HTTP/1.0 close semantics | P0 | P | P | F | smoke |
| P-10 | Response framing (CL, HEAD/204/304) | P0 | P | P | F | smoke |
| P-11 | HEAD/OPTIONS/405/Allow | P0 | P | P | G,FF | smoke |
| P-12 | HTTP/2 | P1 | M | M | G,FF | not implemented |
| P-13 | HTTP/3 | P2 | M | M | FF | not implemented |
| P-14 | In-process TLS | P1 | M | M | -- | edge-only by design |
| P-15 | Response compression (gzip/br/zstd) | P1 | M | M | F,FF | not implemented |
| P-16 | Connection limits / backpressure | P0 | A | A | F | timeouts+caps; no conn cap |
| P-17 | HTTP client / reverse proxy | P1 | M | M | F | server-only |

## Routing and requests

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| R-01 | Static and parameterised routes | P0 | P | P | CH,G,FF | router; tests |
| R-02 | Route groups / prefix nesting | P1 | M | A | G,FF | only `/v1` normalisation |
| R-03 | Wildcard / catch-all routes | P1 | A | A | CH,G | partial |
| R-04 | Per-route middleware/policy | P0 | P | P | CH,G | chain + rate routes |
| R-05 | Global middleware chain | P0 | P | P | CH,G | dispatch |
| R-06 | Path normalisation / redirects | P2 | ? | A | G,FF | slash handling |
| R-07 | 404/405 + Allow | P0 | P | P | G | smoke |
| R-08 | Query parsing (multi-value) | P0 | P | P | F,G | tests |
| R-09 | `application/x-www-form-urlencoded` | P1 | ? | A | G,FF | verify |
| R-10 | JSON body parsing + caps | P0 | P | P | G,FF | smoke |
| R-11 | Multipart uploads | P0 | ? | P | G,FF | smoke 415/caps |
| R-12 | Cookie parse/set | P0 | P | P | G,FF | tests |
| R-13 | Content negotiation (`Accept`) | P2 | M | M | FF,G | not implemented |
| R-14 | Schema validation of input | P1 | M | A | FF,FA | manual; OpenAPI only |
| R-15 | Dependency injection | P2 | N/A | M | FA,FF | not implemented |
| R-16 | Typed response models | P2 | M | A | FA,FF | envelope only |

## Responses, static, streams

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| W-01 | JSON/text/bytes responses | P0 | P | P | all | builders |
| W-02 | Structured error envelope | P0 | P | P | FF,G | envelope tests |
| W-03 | Request IDs | P0 | P | P | FF | rid in logs/404 |
| W-04 | Static files + ETag/304 | P0 | ? | P | G,FF | smoke 304 |
| W-05 | Traversal guard | P0 | ? | P | G,FF | smoke traversal |
| W-06 | Range requests | P1 | M | M | G,FF | not implemented |
| W-07 | Efficient file streaming (sendfile) | P1 | M | A | G,FF | 50 MB works, copied |
| W-08 | SSE | P0 | P | P | FF,G | live 20/20 |
| W-09 | WebSocket handshake/frames/fragmentation | P0 | P | P | FF,G | live 20/20 |
| W-10 | WS permessage-deflate | P1 | M | M | FF | not implemented |
| W-11 | WS subprotocol negotiation | P2 | M | M | FF | not implemented |
| W-12 | SSE event IDs + reconnect semantics | P1 | A | A | FF | verify |
| W-13 | Templating / server-side rendering | P1 | N/A | M | G,FA | not implemented |
| W-14 | OpenAPI generation | P1 | M | A | FA,FF | document only, not schema-driven |
| W-15 | CORS responses + preflight | P0 | ? | P | G,FF | smoke preflight |

## Security and auth

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| S-01 | Security headers (helmet set) | P0 | P | P | H | head literal; smoke |
| S-02 | CSRF tokens | P0 | A | P | -- | session requests |
| S-03 | Sessions (cookie + store) | P0 | A | P | -- | test_app |
| S-04 | JWT HS256 issue/verify | P0 | P | P | J | test_app |
| S-05 | JWT asymmetric algs (RS/ES/EdDSA) | P1 | M | M | J | not implemented |
| S-06 | JWE / JWK key sets | P2 | M | M | J | not implemented |
| S-07 | OAuth/OIDC client | P2 | N/A | M | -- | not implemented |
| S-08 | Password hashing | P0 | ? | ? | -- | verify app login |
| S-09 | Rate limiting (global + route) | P0 | P | P | FF | rate smoke |
| S-10 | CORS allowlist | P0 | P | P | FF | smoke |
| S-11 | Stream Origin/auth policy | P0 | P | P | -- | ws-auth 11/11 |
| S-12 | Upload size/type caps | P0 | ? | P | FF | smoke 415 |
| S-13 | Secret redaction in logs | P0 | P | P | -- | token=REDACTED |
| S-14 | Audit log + rotation | P1 | P | P | -- | crash/audit tests |
| S-15 | TLS termination guidance/automation | P1 | N/A | A | -- | docs only |
| S-16 | mTLS / client certificates | P2 | M | M | -- | not implemented |
| S-17 | External audit + fuzzing | P0 | M | M | -- | none yet |

## Data and state

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| D-01 | Embedded KV with transactions/durability | P0 | N/A | P | B | kv backend; tests |
| D-02 | Crash recovery / torn-write healing | P0 | N/A | P | B | crash 6/6 |
| D-03 | SQL driver | P1 | N/A | P | -- | sqlite opt-in |
| D-04 | Migrations | P1 | N/A | P | K | 21/21 |
| D-05 | Transactions | P1 | N/A | P | K | test_sql |
| D-06 | Repository/CRUD + paging | P1 | N/A | P | K | test_sql |
| D-07 | Query builder | P1 | N/A | M | K | raw SQL only |
| D-08 | ORM / models | P2 | N/A | M | K | not implemented |
| D-09 | Connection pooling | P1 | N/A | A | K | verify sqlite driver |
| D-10 | Caching layer | P1 | N/A | M | -- | not implemented |
| D-11 | Background jobs / queues | P1 | N/A | M | BM | not implemented |
| D-12 | Job retries / scheduling | P1 | N/A | M | BM | not implemented |
| D-13 | Pub/sub | P2 | N/A | M | -- | not implemented |
| D-15 | Multi-tenancy | P2 | N/A | M | -- | not implemented |

## Operations and observability

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| O-01 | Health endpoint | P0 | N/A | P | -- | smoke |
| O-02 | Prometheus metrics | P0 | N/A | P | FF | smoke metrics |
| O-03 | Structured access logs | P0 | A | P | FF | JSON lines |
| O-04 | Audit log + rotation | P1 | N/A | P | -- | tests |
| O-05 | Tracing / OpenTelemetry | P2 | M | M | FF | not implemented |
| O-06 | Graceful shutdown / drain | P1 | A | A | F,FF | quit flag, no drain |
| O-07 | Config validation + `--check-config` | P0 | N/A | P | -- | smoke |
| O-08 | CLI (routes/openapi/version) | P1 | N/A | P | -- | smoke |
| O-09 | Cluster / scale-out | P1 | M | M | -- | sequential accept |
| O-10 | Hot reload | P2 | M | M | -- | Phase B blocked |
| O-11 | Container/systemd guidance | P1 | N/A | A | -- | partial docs |
| O-12 | Reproducible release + attestations | P0 | N/A | E | -- | SHA pins, dry-run |
| O-13 | Flat memory under soak | P0 | M | M | WB | 22 KB/req residual |
| O-14 | Published c1/c10 benchmark | P1 | N/A | A | WB | bttger c1; c10 ceiling |
| O-15 | Published 1M soak | P1 | N/A | M | WB | blocked |
| O-16 | Fuzzing harness | P1 | M | M | -- | none |

## Ecosystem and developer experience

| ID | Capability | Pri | Beacon | Station | Refs | Evidence / gap |
|---|---|---|---|---|---|---|
| E-01 | Concept/reference/deployment docs | P0 | A | P | all | ~6k docs lines |
| E-02 | Tutorials and examples | P1 | A | A | G,FF,FA | partial |
| E-03 | Third-party middleware/plugins | P2 | M | M | FF,FA | none |
| E-04 | Package registry + supply-chain verification | P0 | N/A | E | -- | signed, pinned, attested |
| E-05 | Test harness + multi-OS CI | P0 | E | E | -- | suites/smokes/CI fleet |
| E-06 | Versioning, release cadence, LTS | P1 | A | A | all | 0.2.2, no LTS |
| E-07 | Admin panel | P2 | N/A | M | -- | not implemented |
| E-08 | i18n | P2 | N/A | M | -- | not implemented |
| E-09 | Email | P2 | N/A | M | -- | not implemented |
| E-10 | GraphQL | P2 | N/A | M | -- | not implemented |
| E-11 | gRPC | P2 | N/A | M | -- | not implemented |
| E-12 | Benchmark comparison vs peers | P1 | N/A | M | WB | no cross-framework run |

## Reference extraction (the "X things" lists)

For each clone, walk its docs/examples and add rows above; cite where the
behavior lives. Seed notes:

- **fasthttp** (`E:\repos\fasthttp`): server loop/workerpool, compression,
  streaming, client, timeouts, `Server` limits. Look at `server.go`,
  `http.go`, `compress.go`, `client.go`.
- **h11** (`E:\repos\h11`): the HTTP/1.1 state machine -- request/response
  framing, EOF/chunked rules, connection states. `h11/_connection.py`,
  `_events.py`, `_readers.py`, `_writers.py`.
- **chi** (`E:\repos\chi`): router trees, groups, middleware, URL params.
- **gin** (`E:\repos\gin`): groups, binding/validation, rendering, recovery,
  middleware, context.
- **fastify** (`E:\repos\fastify`): schema validation/serialisation, hooks,
  plugins, logging (pino), encapsulation, decorators.
- **fastapi** (`E:\repos\fastapi`): Pydantic validation, DI, OpenAPI,
  async, security utilities.
- **helmet** (`E:\repos\helmet`): the header set and defaults.
- **jose** (`E:\repos\jose`): JWS/JWE/JWK algorithms and key management.
- **knex** (`E:\repos\knex`): query builder, schema builder, migrations,
  transactions, pooling.
- **bbolt** (`E:\repos\bbolt`): B+tree KV, transactions, mmap, durability.
- **bullmq** (`E:\repos\bullmq`): queues, workers, retries, backoff,
  scheduling, events.
- **web-framework-benchmarks**, **web-framework-bench-xlcaptain**:
  harness/methodology for cross-framework comparison; adopt its endpoints
  and reporting so numbers are comparable.
