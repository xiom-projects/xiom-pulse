<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE benchmark baseline -- bttger six-endpoint contract

**Date:** 2026-10-19 (session 22). **Commit:** `9b97eb7`. **CI:**
`39335266242` (both platforms green, including the benchmark-app build
gate). **Status:** baseline only, not a cross-framework ranking. Raw
autocannon output is committed under `benchmarks/bttger/results/`. The
Linux leg and the 1M-request run are **blocked** on stdlib JSON builder
memory retention (`REL-20261020-1704-pulse`); see section 4.1.

## 1. What was measured

The six-endpoint interface from `E:\repos\web-framework-benchmarks`
(bttger, MIT; `OPEN_API_DEFINITION.yaml`) implemented by
`benchmarks/bttger/main.xi` on the published Beacon core
(`xiom.pulse` 0.3.1, `app.register` + `app.serve`), not the product
Station server. The benchmark app deliberately implements only the
contract:

| Endpoint | Contract work |
|---|---|
| `GET /serialize` | `{"message":"Hello, World!"}` |
| `GET /serialize/big` | nested object + 50 on-demand publication entries |
| `GET /plain/text` | `Hello, World!` as `text/plain; charset=utf-8` |
| `GET /query/300/tools/10?...` | path/query/header validation, JSON response with ISO timestamp |
| `POST /insert` | parse JSON, add `id` + `createdAt`, re-serialize, `201` |
| `GET /calculate` | recursive `fib(27)` (0/1 seed, as in the reference gin app) |

## 2. Method

- Tool: `autocannon` 7.15.0 (the bttger suite's tool), Node v23.10.0.
- Server: Windows native `out/bench_bttger.exe` built from
  `benchmarks/bttger/main.xi` with the pinned XIOM **v0.64.8** + stdlib
  `112c5b6`; `PULSE_PORT=18088`, keep-alive on, read/write deadlines
  30000 ms, idle deadline 120000 ms (the higher idle value stops the
  harness's waiting connections from being closed by the server between
  cycles; it does not add concurrency).
- Host: Windows 11 (10.0.26200), 32 logical CPUs; same host for server
  and load generator; no containers, no TLS, no database.
- Load: **5,000 requests per endpoint** (`/calculate` uses 50 = amount/100,
  matching the reference driver), **5 s warmup** on `/serialize`,
  sequential endpoints. Two connection modes were captured: **1** and
  the reference suite's **10**.
- Why not the reference 1,000,000 amount: at the measured single-
  connection rates (78-455 req/s) the standard run would take several
  hours per endpoint on this host. The reduced run is long enough for a
  stable baseline (5,000 samples, p50/p97.5/p99) and is labelled as such;
  the standard run is a separate, longer experiment.
- PULSE sends its default security headers on every response; they are
  included in the numbers. No response compression is enabled.

## 3. Results -- single connection (clean baseline)

`BENCH_CONNECTIONS=1`, 5,000 samples per endpoint (50 for `/calculate`).
All responses were 2xx; zero errors/timeouts.

| Endpoint | req/s | p50 ms | p97.5 ms | p99 ms | 2xx | non-2xx | errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| `getSerialized` | 454.6 | 1 | 3 | 3 | 5000 | 0 | 0 |
| `getSerializedBig` | 78.1 | 11 | 17 | 18 | 5000 | 0 | 0 |
| `getPlainText` | 384.6 | 2 | 3 | 3 | 5000 | 0 | 0 |
| `getQueryResult` | 142.9 | 6 | 8 | 8 | 5000 | 0 | 0 |
| `insertObject` | 172.4 | 5 | 7 | 7 | 5000 | 0 | 0 |
| `getCalculated` | 50.0 | 5 | 6 | 7 | 50 | 0 | 0 |

## 4. Results -- ten connections (reference-suite shape)

`BENCH_CONNECTIONS=10`, same amounts. Throughput is essentially unchanged
from the single-connection run, so the extra connections add queuing, not
concurrency. The `errors` column equals `timeouts`: the connections that
the sequential-accept loop is not currently serving wait until
autocannon's socket timeout.

| Endpoint | req/s | p50 ms | p97.5 ms | p99 ms | 2xx | non-2xx | errors/timeouts |
|---|---:|---:|---:|---:|---:|---:|---:|
| `getSerialized` | 384.5 | 2 | 3 | 3 | 4999 | 0 | 1 |
| `getSerializedBig` | 76.6 | 12 | 17 | 19 | 4976 | 0 | 24 |
| `getPlainText` | 416.6 | 2 | 3 | 3 | 4999 | 0 | 1 |
| `getQueryResult` | 151.2 | 6 | 8 | 9 | 4989 | 0 | 11 |
| `insertObject` | 192.0 | 5 | 6 | 7 | 4992 | 0 | 8 |
| `getCalculated` | 50.0 | 5 | 217 | 245 | 50 | 0 | 0 |

## 4.1 Linux attempt (2026-10-20) -- blocked by a stdlib leak

The capped Linux leg (same binary built for WSL, `PULSE_MAX_RSS_MB=2048`,
5,000 requests) was stopped by the RSS watchdog during
`getSerializedBig`: **1,624 of 5,000** requests completed, then RSS reached
**2,102,528 KB** and the watchdog killed the process. Every later
endpoint failed with the server gone; no valid Linux result is published.

A pure repro without HTTP (`tests/probes/probe_json_leak.xi`) builds the
same 50-publication object in a loop and is killed by a **512 MB** cap
after ~500 iterations (RSS **530,944 KB**). The leak is in the stdlib JSON
builder path (`json_set` / `json_array_push` copy-on-write), not the HTTP
loop. Filed on the relay as **`REL-20261020-1704-pulse`** (pulse ->
stdlib, high). The 1M-request benchmark and the Linux leg stay blocked
until the stdlib fix lands.

The Windows baseline above is unaffected: it completed all 5,000 requests
per endpoint before the cap policy; see section 7 for the caveat.

## 5. Findings

1. **The sequential-accept loop is the ceiling.** The Beacon core serves
   one accepted connection through all of its keep-alive cycles; the
   other connections wait. Going from 1 to 10 connections produced no
   throughput gain and turned the waiting connections into timeouts.
   That is the known W1 scale-out gap, not a benchmark artifact: the fix
   is the worker supervisor / multi-process or multi-fd service loop
   (`SO_REUSEPORT` + `poll` primitives are delivered upstream).
2. **Per-request cost is visible.** `/serialize/big` (3.8 KB body, 50
   entries built per request) is ~6x slower than the tiny `/serialize`;
   `/insert` (JSON parse + rebuild) and `/query` (path/query/header
   validation) sit in between.
3. **`/calculate` blocks the loop.** One `fib(27)` request is ~20 ms of
   CPU; the server answers ~50/s. The ten-connection p99 (245 ms) is the
   queue in front of that block. This is the workload's purpose -- it
   shows why a compute endpoint needs a worker/thread boundary.
4. **All clean-path responses were 2xx.** No non-2xx was observed in any
   leg; the only errors are the ten-connection timeout class above.

## 6. Reproduction

```powershell
# build the contract app (Beacon only; no SQLite C source)
.\scripts\build.ps1 benchmarks\bttger\main.xi -Name bench_bttger

# start it under the workstation RSS cap (owner directive 2026-10-20);
# the benchmark driver defaults to port 8080, 18088 avoids the local
# Docker listener on this host
$env:PULSE_PORT = "18088"
$env:PULSE_IDLE_TIMEOUT = "120000"
$env:PULSE_MAX_RSS_MB = "2048"
.\scripts\capped_app.ps1 -Exe .\out\bench_bttger.exe

# in benchmarks\bttger (autocannon installed from package.json)
$env:BENCH_PORT = "18088"
$env:BENCH_AMOUNT = "5000"
$env:BENCH_CONNECTIONS = "1"
$env:BENCH_WARMUP = "5"
node benchmark.js xiom-pulse-windows-2026-10-19-c1
```

Repeat with `BENCH_CONNECTIONS=10` and a different result title for the
reference-suite shape. Raw files:

- `results/xiom-pulse-windows-2026-10-19-c1.json`
- `results/xiom-pulse-windows-2026-10-19-c10.json`

## 7. Caveats

- Single host, single run per mode; host background load is not
  controlled beyond keeping the workload local.
- Windows native baseline; a Linux run and the full 1,000,000-request
  reference amount remain queued. Do not compare these numbers with
  published results from other machines or with other frameworks; that
  requires running the same suite on the same host.
- The contract app is intentionally minimal (Beacon core, no Station
  middleware beyond the package's security headers). Product-server
  numbers will differ.
- **Blocked:** the Linux leg and the full 1M amount cannot run until the
  stdlib JSON builder leak is fixed; the Linux attempt was killed by the
  2 GB workstation cap after 1,624 `/serialize/big` requests. The pure
  probe reproduces it without HTTP.
