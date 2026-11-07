# PULSE HTTP Memory Floor -- 2026-11-06

Scope: measure and explain the current `GET /health` floor (WP1 / 1.0 blocker).
No source, test, script, or documentation file other than this one was edited.
The 1M and 24 h gates were not run; all reported probes stayed below
2048 MB (one discarded exploratory point is noted in section 7).

- Host: Windows (win32), same host class as the 20.6 -> 16.1 measurement.
- Toolchain: compiler `v0.65.6`, stdlib `6fdde4ee` (`stdlib-tag-v0.65.6`).
- Packages: lane-local `%LOCALAPPDATA%\xiom-pulse-home` (`xiom.pulse` 0.3.2).
- Product commit under test: `8b6b4a5` (HEAD at measurement time).

## 1. Result in one line

The current floor is **~16-17 KB/request** on the stock 60 s `rss_probe`
(16.9 and 17.4 KB/req in two runs; 20.4 and 21.8 KB/req including warmup).
A true single-connection keep-alive run measured **15.77 KB/req** after
warmup. This is consistent with the repo baseline of ~16.1 KB/req after the
router cache. It is not a soak result and not a leak proof.

## 2. Commands and raw results

```powershell
.\scripts\build.ps1 src\server.xi -Name mem_probe_server -TimeoutSec 300
.\scripts\rss_probe.ps1 -ServerExe out\mem_probe_server.exe -Seconds 60 -IntervalMs 200 -Port 18197
.\scripts\rss_probe.ps1 -ServerExe out\mem_probe_server.exe -Seconds 60 -IntervalMs 200 -Port 18199
.\scripts\build.ps1 tests\probes\probe_req_cycle.xi -Name req_cycle -TimeoutSec 300
.\scripts\build.ps1 tests\probes\probe_alloc_aggregate.xi -Name mem_alloc_aggregate -TimeoutSec 300
```

All requested builds succeeded on v0.65.6. The server logs showed
keep-alive on, `PULSE_LOG=0`, and a clean `server_exit: 0` in both 60 s
runs.

### 2.1 Stock 60 s `/health` probe

Run 1 (port 18197):

- requests: 117 ok / 0 fail
- working set: 5,816,320 -> 8,368,128 bytes
- growth: 2,551,808 bytes = **21,810.32 B/req incl. warmup**
- steady (2nd sample onward): 77 requests, 1,339,392 bytes =
  **17,394.7 B/req (16.99 KiB/req)**

Run 2 (port 18199):

- requests: 160 ok / 0 fail
- working set: 5,332,992 -> 8,593,408 bytes
- growth: 3,260,416 bytes = **20,377.6 B/req incl. warmup**
- steady (2nd sample onward): 117 requests, 1,978,368 bytes =
  **16,909.13 B/req (16.51 KiB/req)**

### 2.2 True keep-alive check (single TCP connection)

`rss_probe.ps1` invokes `curl.exe` once per iteration, so each sample is a
fresh process and a fresh TCP connection despite the "keep-alive" label.
To separate connection setup from the per-request floor, I ran an inline
`TcpClient` loop on one connection: 100 warmup requests, then 400 measured
requests, sampling `WorkingSet64` of `out\mem_probe_server.exe` (port 18198).

- working set after 100 warmup: 7,421,952 bytes
- working set after 500 total: 13,729,792 bytes
- delta over the 400 measured requests: 6,307,840 bytes
- **15,769.6 B/req (15.40 KiB/req)**

Connection setup is therefore not the dominant term; the stock probe and
the true keep-alive probe agree within ~1.2-1.6 KB/req.

### 2.3 Pure-in-process cycle probes

`probe_req_cycle` was run with a fixed `PROBE_ITERS` value and external
`WorkingSet64` sampling. Per-iteration cost is the slope between two
iteration counts, which removes startup and warmup:

```powershell
$env:PROBE_ITERS='50000';  out\req_cycle.exe parse
$env:PROBE_ITERS='450000'; out\req_cycle.exe parse
$env:PROBE_ITERS='50000';  out\req_cycle.exe build
$env:PROBE_ITERS='450000'; out\req_cycle.exe build
$env:PROBE_ITERS='50000';  out\req_cycle.exe both
$env:PROBE_ITERS='450000'; out\req_cycle.exe both
```

| Mode | 50k working set | 450k working set | Slope |
|---|---:|---:|---:|
| `parse` | 17,088,512 | 455,819,264 | **1,096.8 B/iter (1.07 KiB)** |
| `build` | 76,058,624 | 653,254,656 | **1,443.0 B/iter (1.41 KiB)** |
| `both` | 132,108,288 | 1,153,703,936 | **2,554.0 B/iter (2.49 KiB)** |

`both` is the pure parse + response-build server cycle. It is additive:
`1,096.8 + 1,443.0 ~= 2,554`.

### 2.4 Route / dispatch decomposition

A temporary measurement harness was built in gitignored `out\` and its
source was removed after the run. It used the product modules directly:

- `route`: `router.route_match("GET", "/health")`
- `defs`: `router.route_defs()`
- `gate`: `route_match` + `route_defs` (the current `gate_request` shape)
- `post`: `http.build_response_full(...)` + `http.with_header_line(Date)`
- `cycle`: `parse_request` + `route_match` + `core.handle_route` +
  `build_response_full`
- `product`: parse + cookie/quit/TE header reads + `v1_path` + `route_match`
  + `route_defs` + a second `route_match` + `handle_route` + `build_response_full`
  + Date insertion + CORS block + `metrics_record` + `metrics_record_duration`
- `metrics`: `metrics_record(200,100)` + `metrics_record_duration(1)`

| Mode | 50k | 150k | 500k | Slope |
|---|---:|---:|---:|---:|
| `route` | 57,102,336 (peak) | 180,428,800 (peak) | 599,404,544 (peak) | **~1,210 B/iter (1.18 KiB)** |
| `defs` | -- | 4,370,432 | 4,366,336 | **~0 retained B/iter** |
| `gate` | 63,033,344 | 184,655,872 | 605,315,072 | **~1,210 B/iter** |
| `post` | 104,222,720 | 300,130,304 | 989,794,304 | **~1,960 B/iter (1.91 KiB)** |
| `cycle` | 394,006,528 | 1,170,182,144 | discarded | **7,761.8 B/iter (7.58 KiB)** |
| `metrics` | 31,354,880 (last) | 136,142,848 (last) | -- | **~1,048-1,151 B/iter (1.02-1.12 KiB)** |
| `product` | 541,024,256 | 1,612,042,240 | -- | **10,710 B/iter (10.46 KiB)** |

`route_defs()` allocates a 25-pair Vec on every call but does not retain it
in this probe; the `gate` slope is essentially the `route_match` slope.
`product` is the in-process product path without sockets, the full gate,
`reqctx`, or the access-log check. It is a lower bound.

### 2.5 Aggregate allocation probe

`probe_alloc_aggregate` was run at 500,000 iterations per safe mode (no 1M),
with a 2048 MB cap; every reported run completed below the cap.

| Mode | Peak working set at 500k | Approx. cost |
|---|---:|---:|
| `map` | 45,895,680 | ~83 B/iter |
| `vec` | 4,333,568 | flat |
| `str` | 10,903,552 | ~13 B/iter |
| `obj` | 12,308,480 | ~16 B/iter |
| `parse` | 12,349,440 | ~16 B/iter |
| `type` | 981,413,888 | ~1.95 KB/op |
| `get` | 954,150,912 | ~1.90 KB/op |

The Map path is not the runaway allocator in isolation. The expensive
JSON accessors are still `json_type`/`json_get` (~2 KB/op, the known
`REL-20261104-1709-pulse` residual).

## 3. Floor breakdown

Contribution to the ~16.1 KB/req floor, from the measured slopes above:

| Component | Bytes/req | Notes |
|---|---:|---|
| Socket read / raw buffer / send + poll copies | ~5.1 KB | Difference between true keep-alive (15,770 B) and in-process product path (10,710 B); also contains the remaining gate/config/reqctx/access-log calls |
| Parser (`http.parse_request`) | ~1.1 KB | Includes the deferred `Option[ServerRequest]` aggregate residual (~0.9 KB per the repo note) |
| Route table `route_match` (two calls) | ~2.4 KB | ~1.2 KB per call; the cached table itself adds ~0 |
| Response builder + `HandlerOut` + Date insertion | ~5.8 KB | `cycle` (7.58 KB) minus parser (1.1) minus route (1.2), plus the ~0.53 KB Date-insert copy |
| Metrics label maps + histogram | ~1.0-1.1 KB | Four label maps per request (three counters + one histogram) plus registry aggregate work |
| Option aggregate | ~0.9 KB | Already inside the parser number; repo estimate, not separately isolated here |

Sanity check: `5.1 + 1.1 + 2.4 + 5.8 + 1.1 ~= 15.5 KB`, close to the
measured 15.77 KB true keep-alive floor. The stock probe adds a little
per-connection noise and reports 16.9-17.4 KB/req.

### 3.1 Active allocations by request stage

- `src/server.xi:1388-1391`: per-connection `buf` and `recv_buf` Vec
  holders. `recv_buf` is reused by `socket_recv_into`; `buf` is reset per
  keep-alive cycle (`src/server.xi:1509`) for pipelined leftovers.
- `src/server.xi:687-773` (`read_request`): a fresh `raw` Vec per request;
  every received byte is pushed into it (`730-733`).
- `src/server.xi:1427` and package `http.xi:158-271`: `PulseRequest`
  aggregate with three Str fields, two header Vecs, and a body Vec. The
  adapter parses through `server.server_parse_request` (`http.xi:197`),
  which returns `Option[ServerRequest]` by value and copies the headers
  into parallel Vecs (`http.xi:212-229`), then copies the body bytes
  (`http.xi:260-267`).
- `src/server.xi:70-73` (`next_rid`): a new `"r-N"` Str per request.
- `src/server.xi:1033-1042` (`gate_request`): `route_match` + `route_defs`
  for the per-route policy check, even when `route_rates` is disabled
  (`src/ratelimit.xi:270-271` returns true immediately).
- `src/server.xi:266` (`dispatch_one`): a second `route_match` for the same
  request.
- `src/router.xi:167-206` (`route_match`): `PulseRoute` with six Vecs
  (param/query names and values), plus `split_target`/`parse_query`.
- `src/server.xi:92-98` (`HandlerOut`): two Vec fields (`headers`,
  `body_bytes`) plus Str `body`; `out_json`/`out_text`/`out_html`
  (`113-123`) construct it with two empty Vecs per response.
- `src/server.xi:272-643` (`handle_route`): JSON object construction and
  stringify for `/health` (`json_ok_field`), plus error-envelope work.
- `src/server.xi:1128-1160` (`build_dispatch_response`): `bytes_to_str`
  for the body, `build_response_full`, then `with_std_headers` and
  `with_cors`.
- `src/server.xi:1061-1068` (`with_std_headers`): copies the whole
  response Vec to insert `Date` (and CSP when set).
- package `http.xi:666-697` (`build_response_full`): one pre-sized Vec and
  `append_str` calls. This path is already flat relative to the old
  concat-chain builder; the remaining cost is the Vec and literals, not a
  retained concat chain.
- `src/server.xi:776-827` (`send_step` / `send_all`): a chunk Vec per send
  and a one-element `Vec[Int]` fd list per poll.
- `src/metrics.xi:28-32`, `44-62`, `66-71`: `metric_labels_new` +
  `metric_counter_inc_labeled` / `metric_histogram_observe_labeled` per
  request; the registry lives in the module-level `m_regs` Vec.

## 4. Router-cache effect

Commit `8e01eb5` changed `route_match` from rebuilding the 25-route table
on every call (`router_new` + 25 `router_add`) to building it once into a
module-level `Vec[Router]` holder (`src/router.xi:145-162`) and matching
the cached table (`src/router.xi:183-204`). The recorded effect was
**20.6 -> 16.1 KB/req** (95 steady requests). This measurement is
consistent: two stock runs now give 16.9 and 17.4 KB/req, and a true
keep-alive run gives 15.77 KB/req.

The cache removed the per-request 25-pair route table plus 25 registrations
(~4.5 KB of the old floor). It did not remove:

- the per-request `PulseRoute`/query-parse allocations (~1.2 KB per match);
- the second `route_match` in `dispatch_one`;
- the `route_defs()` call in `gate_request`, which is now flat in the
  aggregate probe but is still redundant work and is only needed when
  `route_rates` is enabled.

## 5. Metrics Map compiler block

The attempted metrics optimization cached registry entry indices in
`src/metrics.xi` so each request would stop rebuilding label Maps:

- direct nested borrow (`&mut m_regs[0].entries[idx].c`) crashed with
  `0xC0000005`;
- the copy-modify-write pattern (`var h = ...; ...; entries[idx].h = h`)
  hit a v0.65.6 clang codegen error:
  `extractvalue %struct.Vec 0, 0`;
- `src/metrics.xi` was reverted to HEAD (suite GREEN), and
  `tests/probes/probe_nested_struct_copy.xi` was filed with
  `REL-20261106-1840-pulse` (compiler, medium).

Until that compiler fix lands, the per-request metric label Maps remain in
the floor. The measured metrics-only cost is **~1.0-1.1 KB/req** for one
`metrics_record` (which itself creates three label maps) plus one
`metrics_record_duration` (one histogram label map). Re-land and re-measure
on v0.65.7+.

## 6. PULSE-side cuts, ranked

These are proposed only; no code was changed.

| Rank | Cut | Exact location | Expected | Risk | Proposed measurement |
|---:|---|---|---:|---|---|
| 1 | Collapse `HandlerOut` and response assembly into one buffer; stop returning two empty Vecs per response and avoid the extra body/header copies | `src/server.xi:92-98` (`HandlerOut`), `113-123` (`out_json`/`out_text`/`out_html`), `272-643` (`handle_route`), `1128-1160` (`build_dispatch_response`) | 2-4 KB/req | Medium (broad handler/call-site change) | Re-run the in-process `cycle` probe (7.58 KB) and the 60 s `/health` probe; target `cycle` toward the 2.5 KB parse+build floor |
| 2 | Match the route once per request: return the `PulseRoute` in `GateResult` and reuse it in `dispatch_one`; also skip the policy lookup when `route_rates` is disabled | `src/server.xi:908-916` (`GateResult`), `969-1055` (`gate_request`, especially `1033-1042`), `254-268` (`dispatch_one`), `src/ratelimit.xi:221-223` / `270-271` | ~1.2 KB/req | Low | Re-run one 60 s probe; the `route_match` probe should drop from ~1.2 KB to 0 for the duplicate call; target 16.1 -> ~14.9 KB |
| 3 | Insert `Date` (and CSP) directly in the pre-sized response builder, or reserve header space; cache the IMF-fixdate string per second instead of formatting per request | `src/server.xi:1061-1068` (`with_std_headers`); package `http.xi:580-597` (`with_header_line`), `666-697` (`build_response_full`) | 0.5-1.0 KB/req | Low | Compare `post` (1.91 KB) with `build` (1.41 KB); then the 60 s probe |
| 4 | Reuse read/send buffers: avoid rebuilding `raw` byte-by-byte per request, avoid the per-send chunk Vec, and reuse the poll fd list | `src/server.xi:687-773` (`read_request`), `776-788` (`send_step`), `798-827` (`send_all`) | 0.5-2 KB/req | Medium | True single-connection harness (15.77 KB) vs in-process product path (10.46 KB); attribute the gap after cuts 1-3, then re-run the 60 s probe |
| 5 | Cache metric registry entry indices / label Map handles (blocked) | `src/metrics.xi:28-32` (`inc_class`), `44-62` (`metrics_record`), `66-71` (`metrics_record_duration`) | ~1.0-1.1 KB/req | High today (compiler `REL-20261106-1840-pulse`); low after v0.65.7+ | Metrics-only probe (1.02-1.12 KB/req), then the 60 s probe |

Cuts 1 and 2 are the highest-value PULSE-side work that is not blocked:
they are both visible in the same `build_dispatch_response` /
`gate_request` path and can be measured with the existing probes.

## 7. Measurement caveats

- **Short windows.** The stock probes cover 117 and 160 requests. The
  steady numbers exclude the first 20 s, but allocator/GC noise still
  moves the result by ~1-2 KB/req between runs.
- **Warmup.** The stock summary reports both "incl. warmup" (20.4 and 21.8
  KB/req) and steady (16.9 and 17.4 KB/req). The true keep-alive run used
  100 warmup requests before the 400 measured ones.
- **Working set, not private bytes.** `WorkingSet64` includes shared pages
  and allocator high-water. It is a retention indicator, not a leak proof.
- **`rss_probe.ps1` is not actually a keep-alive probe.** It shells out to
  `curl.exe` once per iteration, so every request is a new process and a
  new TCP connection. The true single-connection measurement (15.77 KB/req)
  shows connection setup is not dominant, but the label should be
  corrected in future reports.
- **Pure probes are not the product.** `probe_req_cycle` and the temporary
  route harness have no sockets, full gate, `reqctx`, access log, or
  config reads. Their slopes are lower bounds for the product path.
- **Cap.** One exploratory 450k-iteration route-cycle point exceeded the
  2048 MB cap (3.5 GB working set) and was discarded. All reported points
  are from runs at or below 150k for the product/cycle paths and 500k for
  the aggregate modes; the largest reported working set was 1.61 GB
  (`product`, 150k).
- **Aggregate modes.** `probe_alloc_aggregate` reports peak/end working
  set; the per-iteration cost is a slope, not an exact allocation count.
  Fast modes can finish before the first sample, so the 50k/150k/500k
  pairs are used where possible.
- **No gate.** Neither the 24 h nor the 1M run was executed. The numbers
  here are diagnostic and do not replace the WP1 acceptance gate.

## 8. Post-report cut 2 applied (2026-11-06)

`gate_request` now guards the per-route `route_match`/`route_defs` and the
stream policy lookup with `route_rates.enabled` (the default is disabled);
`dispatch_one` keeps the single match. Two 60 s `/health` probes on the
current build measured steady **15,597.57** and **15,499.64 B/req**
(15.2-15.6 KB/req), down from the report's 16,909/17,394 and the earlier
16.1 baseline. `test_app` and the live `http_smoke` (135 checks, route-rate
gate order) are green. The 24 h/1M gates remain open; cut 1
(HandlerOut/response assembly) is the next unblocked target.

## 9. Post-report cut 1 applied (2026-11-07)

`HandlerOut`/response assembly now builds the wire response in one pre-sized
buffer; `out_json`/`out_text`/`out_html` reuse shared read-only empty Vecs
and the old builder -> CORS -> Date chain plus the HEAD build-then-trim copy
are gone. Three 60 s `/health` probes measured steady **14,755.78, 14,238.48
and 14,070.96 B/req** (14.1-14.8 KB), down from 15.5. `test_app` and the live
`http_smoke` (135 checks) are green; responses are byte-equivalent to the old
builder (Date excluded). Cut #3 (Date/CSP insertion) and cut #4 (read/send
buffers) remain; the metrics Map is compiler-blocked; 24 h/1M are open.

## 10. Post-report cuts 3 and 4 applied (2026-11-07)

The Date formatter is cached per epoch second (`http_date_cached`); the
request buffer is pre-sized once; the per-send chunk Vec was removed with a
whole-buffer `socket_send` fast path; the poll fd list is built once per send.
Three 60 s `/health` probes measured **13,811.51, 13,546.41 and 14,306.74
B/req** (13.5-14.3 KB; allocator noise is ±1-2 KB) versus 14.5. `test_app`
GREEN; live `http_smoke` 135/135 (date, 50 MB asset, slowloris, write-stall,
gate order) and a second-rollover spot check. Cut #4 is partial: the stdlib
send API exposes no offset/length, so `socket_send` still copies internally;
the nested-aggregate codegen class was not touched. The big remaining residual
is the socket/Option path plus the compiler-blocked metrics Map; 24 h/1M are
open.

## 11. Bttger-mix harness (2026-11-07)

`scripts/soak_bttger.py` (+ `.ps1`/`.sh`) drives the six-endpoint bttger
contract over persistent HTTP/1.1 keep-alive at a fixed rate, samples
RSS/fds and gates on errors, rate shortfall and the RSS cap. A 60 s run at
**100 req/s** (one connection; 6,500 measured + 500 warmup) sustained
100.00 req/s with **0 errors/non-2xx**, p50 0.82 ms / p95 3.18 / p99 3.44;
the steady slope was **14,330.58 B/req (~14.0 KiB)**, wire 1,141 B/req;
RSS 4.6 -> 94.7 MB. The 24 h projection is ~123.8 GB (115.33 GiB); the
256 MB cap is reached in **~178 s**. 100 req/s is sustainable, but the WP1
24 h RSS gate is **not met**. Use `--fail-on-projection` for short wiring
checks; the 24 h command is `soak_bttger.ps1 -Seconds 86400 -Rate 100
-Port 18800 -MaxRssMb 256 -Rebuild` (or the `.sh` twin).
