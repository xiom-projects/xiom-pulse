# PULSE parity program -- vision, metric, and rules

**Status:** living document. **Created:** 2026-10-30.
**Purpose:** replace "how many lines do we have?" with a measurable answer to
"how much of what the best projects do, do we do -- at both tiers?"

Reference clones live on the shelf (`E:\repos`). The metric is **capability
parity with evidence**, not LOC. A project can be top-tier in a narrow class
with 20k lines and mediocre in a broad class with 200k; we are deciding what
class we compete in, and then matching it completely.

## 1. The two tiers are compared separately

PULSE ships twice, and each tier has its own contestants and its own parity
score:

| Tier | What it is | Compared against (clones) | Parity means |
|---|---|---|---|
| **Package** | `xiom.pulse` (Beacon) -- embeddable HTTP core: server loop, parser, router, middleware, request/response, static, streams | **fasthttp**, **h11**, **chi** (core/library class) | A library a competent team can build a server on, with the primitives those cores provide |
| **Standalone** | `pulse_app` (Station) -- the full web backend product | **gin**, **fastify**, **fastapi** (framework class), with **helmet**, **jose**, **knex**, **bbolt**, **bullmq** as capability sources | A batteries-included backend a team can deploy without writing another framework |

Supporting references and what they define:

- **helmet** -- HTTP security headers and defaults.
- **jose** -- JWT/JWS/JWE/JWK, algorithms, key handling.
- **knex** -- query builder, schema/migrations, transactions.
- **bbolt** -- embedded KV store, transactions, durability.
- **bullmq** -- background jobs, retries, scheduling, queues.
- **web-framework-benchmarks**, **web-framework-bench-xlcaptain** -- benchmark
  methodology and the numbers that make performance claims comparable.

Rule: a capability can be **applicable to one tier and N/A to the other**
(e.g. sessions are Station, not the core). Scores are computed only over
applicable cells. "We have it in Station" never counts as package parity.

## 2. The unit of parity is a capability, not a feature bullet

Every reference project is decomposed into the same normalized catalog
(`docs/PARITY-MATRIX.md`). Each row has:

- **ID** (e.g. `P-01` protocol, `R-03` routing, `S-02` security, `D-04` data,
  `O-05` ops, `E-02` ecosystem).
- **Capability** stated as observable behavior.
- **Priority:** `P0` = a competent production backend must have it; `P1` =
  production polish; `P2` = ecosystem breadth.
- **Tier applicability:** Beacon / Station / both / N/A.
- **Status:** `M` missing, `A` partial, `P` parity, `E` exceeds, `?`
  unassessed.
- **References:** which clone defines it (F, H11, CH, G, FF, FA, H, J, K, B,
  BM, WB).
- **Evidence:** code path, test/smoke, doc, benchmark or soak that proves the
  status.

A capability counts as **P (parity)** only when all four exist:

1. it behaves like the reference on the observable contract;
2. an automated test (suite/smoke) covers the happy and the failure path;
3. it is documented for users;
4. if it is performance- or memory-relevant, a benchmark/soak number exists.

Anything else is `A` (partial) or `M`. `E` (exceeds) requires a concrete
advantage (e.g. stricter smuggling rules, verifiable supply chain) and the
same evidence. **`?` is honest, not a placeholder to leave forever**: the
catalog owner must either assess it or schedule it.

## 3. Scoring

Weighted by priority: `P0 = 3`, `P1 = 2`, `P2 = 1`.
Status points: `M/? = 0`, `A = 0.5`, `P = 1`, `E = 1` (capped -- no gaming by
padding "exceeds").

```
tier_score = sum(weight * points) / sum(weight)   over applicable rows
```

`scripts/parity_score.ps1` parses the matrix and prints:

- **Beacon %**, **Station %**, and the combined view;
- **assessed coverage** (share of applicable rows that are not `?`);
- the biggest weighted gaps (the rows that would move the score most).

Targets:

- **M1 -- core parity (Beacon ≥ 85% P0):** package is a credible embeddable
  core. No missing P0 in protocol, routing, request/response, static,
  multipart, streams.
- **M2 -- production parity (Station ≥ 85% P0+P1):** a team can deploy
  without inventing auth, sessions, data, observability, ops.
- **M3 -- ecosystem parity (Station ≥ 75% all, including P2):** jobs,
  caching, templating/rendering, OAuth/OIDC, query builder/ORM, plugins.
- **Top-tier claim** requires M1+M2+M3 **plus** flat memory under a 1M soak,
  a real concurrency/scale story, an external audit, and published
  cross-framework numbers. Parity alone is not performance or trust.

## 4. Capability parity is only one axis -- the maturity gates decide "top tier"

`parity_score.ps1` seeded baseline (2026-10-30, lower bound; 107 rows):

| View | Now | Note |
|---|---:|---|
| **Beacon (package)** capability parity | **58.4%** | 88.3% of applicable rows assessed; `?` counts 0 |
| **Station (standalone)** capability parity | **69.1%** | 98.8% assessed |
| **Maturity gates** (below) | **~8%** | 0.5 of 6 gates |
| **Top-tier readiness** (40% capability + 60% maturity) | **~33-37%** | the honest "comparable to the best" number |
| **Production-capable with documented limits** | **~60-65%** | features + operability, excluding top-tier perf/audit/adoption |

The maturity gates are deliberately separate from feature rows, because a
project can tick every feature and still not be top tier:

| Gate | State | Points | Why |
|---|---|---:|---|
| Flat memory under a 1M soak | **missing** | 0 | 22 KB/req residual; 1M blocked |
| Real concurrency / scale-out | **missing** | 0 | c10 adds no throughput (sequential accept) |
| TLS + HTTP/2 (or a productised edge story with numbers) | **missing** | 0 | edge-only TLS, no H2 |
| External audit + fuzzing | **missing** | 0 | none |
| Cross-framework benchmark (harness + peers) | **partial** | 0.5 | c1 published, no peers/1M |
| Production adoption / users | **missing** | 0 | none yet |

Weights are a policy choice, not physics: the current 40/60 split is
deliberate -- performance, stability, assurance and adoption are what the
market means by "top tier", and they are exactly where the LOC gap is not.
Adjust the split in this file if the owner wants a different emphasis; the
matrix score itself must not be adjusted to taste.

The first run is a **lower bound** because unassessed rows are zero. Filling
`?` rows with evidence will raise the capability numbers honestly; only the
gates can raise the top-tier number.

## 5. Governance

- **One catalog:** `docs/PARITY-MATRIX.md`. No second list.
- **Owners per group:** protocol/core -> PULSE; package-derived rows ->
  packages lane; benchmark rows -> benchmark lane; security rows -> security
  review. Disagreements are resolved with evidence, not opinion.
- **Review cadence:** update the matrix in the same commit as the feature;
  re-run `parity_score.ps1` at every wrap and record the number in
  `docs/PROGRESS.md`.
- **Anti-gaming rules:** no parity by importing a dependency we do not ship;
  no "documented" without a user-facing doc; no benchmark claim without the
  run and the harness; no `E` without a named advantage.
- **Reference extraction:** each clone gets a short inventory (its feature
  docs -> catalog rows -> where in its source the behavior lives). That is
  the "X things it does" list; the matrix is the union, deduplicated.

## 6. What this changes in practice

We stop asking "are we big?" and start asking "which P0 rows are still `M`,
and which of the remaining rows are `?` because nobody looked?" The answer is
the roadmap: every `M`/`?` row is either implemented, explicitly N/A for the
tier, or a **documented non-goal**. Top-tier is then a claim about a defined
class with evidence -- which is the only version of the claim that is honest.
