<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -- Progress Tracker

**Last updated:** 2026-10-15 (v0.2.1 released on the v0.64.5 + `092dfa0c` pairing; wave-2 + SQL artifact co-verify green on both platforms)

_Delta 2026-10-08 (v0.64.1 sweep): toolchain updated in place to
**v0.64.1**; **C-PULSE-08 CLOSED** (m212 dash+dot gates green, no
source-roots), **C-PULSE-10 CLOSED** (`probe_pkg_kv` green -- kv_get
returns stored text), C-PULSE-11 alias fix noted; full regression green
on v0.64.1 (suites x2, smoke 73/73, crash 6/6, rate). NEW ecosystem
breakage filed: v0.64.1 extern-unsafe enforcement rejects the published
`xiom.http` 0.1.1 (67 T001s); PULSE pruned the already-unused package
(`probe_pkg_http` = known-red republish gate, packages lane owns it).
Score holds (toolchain adoption, no new capability)._

_Delta 2026-10-08 (Linux sweep + kv decision): toolchain now **v0.64.1 on
Linux/WSL too** (archive sha256 `6f6787a3...` verified, installed tree
byte-identical to the verified extract). **Linux sweep fully GREEN**:
probe fleet 11/11 (incl. `probe_adopt_smoke` run twice -- **C-PULSE-09
does not reproduce on Linux**; narrowed to Windows), m212 dash+dot gate
green (after bridging the new **C-PULSE-13** Unix pkg-home mismatch,
filed), suites x2, smoke **73/73** (jsonl + kv), crash 6/6, rate, and a
**20m kv store-soak** (756 writes / 0 fail; compact + hard-kill reopen
counts intact). **kv-default decision: stays `jsonl` default / kv
opt-in** -- flip is gated on kv-aware Dockerfile + backup tooling +
crash test + a longer soak (prerequisites recorded in
`docs/PACKAGE-WISHLIST-PULSE.md`). Storage 65% -> 68% for the
cross-platform verified kv backend. 55.6% -> ~55.9%._

_Delta 2026-10-08 (wrap 3): **`xiom.http` 0.1.2 republish verified and the
package re-added** (probe green on Windows + Linux; suites x2 + smoke
73/73 with it back in the catalog) -- the last known-red package gate is
closed. The PS twin scripts' stale exe defaults
(`pulse_server.exe`/`pulse_app_v6/v8/v9.exe`) were aligned to
`out\pulse_app.exe` (one hung the smoke run -- fixed; smoke + rate
re-verified green). Website-lane brief filed
(`docs/WEBSITE-RELAY-PULSE.md`); owner decisions recorded in
`docs/OPS-REQUEST.md` section E (pulse. subdomain live, Phase 1 pages by
the website lane, release sequence on greenlight). Score holds (~55.9%)._

_Delta 2026-10-08 (wrap 4): **chunked request decoding landed** (TE:
chunked decoded with caps + trailers; TE+CL -> 400; other codings ->
501; smoke 73 -> **76**, test_http +11 parse cases, route cases in
test_app). **C-PULSE-02 fully closed:** the absolute-path `source-roots`
workaround is removed from `xiom.toml`; build + suites x2 + smoke 76/76
verified on Windows and Linux with `[dependencies]` alone resolving all
ten packages. **NEW C-PULSE-14 (Linux-only):** the 30m HTTP soak grows
RSS ~48 KB per request linearly (2.5 -> 146 MB; Windows flat, HEAD A/B
identical, pure Vec churn flat) -- filed with a runtime repro;
release-gating for the Linux demo, not for Phase-1 website work. HTTP
core 80 -> 84 (+0.5); Reliability 45 -> 40 (-0.5, Linux soak caveat).
Total ~55.9% -> ~55.8%._

_Delta 2026-10-08 (wrap 5): **config-value validation warnings** landed --
invalid `PULSE_PORT`/rate/TTL/audit-size values, non-0/1 booleans and
unknown store backends now warn at startup and in `--check-config`
instead of silently falling back (test_app +8 checks, smoke 76 -> **78**
on both platforms). Configuration 80 -> 85. Total ~55.8% -> ~56.1%._

_Delta 2026-10-08 (wrap 5b): **kv-default ops surface prepped** --
`deploy/Dockerfile` exports `PULSE_KV_DIR=/data/pulse-kv`; the backup
twins are kv-aware (`--kv-dir`/`-KvDir`, env-driven default with
`PULSE_STORE_BACKEND=kv`, whole-dir snapshot at `kv-store/` with
per-file sizes+sha256; verified on Windows + Linux); `DEPLOYMENT.md`
documents the kv store, snapshots and restore, and the Linux systemd
section now reflects the real Linux support + C-PULSE-14 mitigation.
Remaining flip gate: a longer kv soak (crash/reopen already covered by
`store_soak`). Score holds (~56.1%)._

_Delta 2026-10-09 (wrap 6): **C-PULSE-14 corrected -- cross-platform.**
The Windows soak's memory sampler measured the `cmd.exe` wrapper, not the
server: every historical "flat memory" Windows number is invalid. Fixed
(`soak_http.ps1`/`concurrent.ps1` resolve the real child); the corrected
5m soak shows **~32 KB/request** growth (Linux ~48 KB/req); the new
`rss_probe` twins reproduce it in ~2 minutes on either OS. Candidate lane
fix spotted: m235 (loop-body static allocas) -- retest on the next
archive. Reliability 40 -> 35, Testing 82 -> 80. Total ~56.1% -> ~55.5%._

_Delta 2026-10-09 (wraps 7-8): **CI + release pipeline landed** (setup
action, PR gates, tag releases that cut pulse-v0.1.0 end-to-end with
provenance, weekly heavy soaks; macOS x64/arm64 legs prepared for the
next release with the portability fixes: lsof wait_listen fallback,
timeout/gtimeout watchdog fallback, sha256sum/shasum helper,
`pulse-<ver>-macos-<arch>.zip`); the first macOS dry run hit upstream
darwin blockers (runtime C `_SC_AVPHYS_PAGES`, arm64 x86 asm, a codegen
intrinsic; filed), so the macOS legs are gated behind
`RELEASE_BUILD_MACOS` and the next release is not blocked. **C-PULSE-16
filed:** the ops-verified
`PULSE_BIND` gap (stdlib `socket_bind` wildcard-only; repro LISTEN
`0.0.0.0`); address-aware bind filed upstream, firewall mitigation
verified on the demo; fix + LISTEN-address smoke check ship with the
next release. Security 46 -> 42 (-0.5); Testing 80 -> 88 (+0.4) now that
CI exists and cut a release. Total ~55.5% -> ~55.4%._

_Delta 2026-10-09 (wrap 9, v0.64.2 adoption): **both platforms on
v0.64.2** (dl live; SHAs pinned in all workflows; the CI setup action no
longer creates the C-PULSE-13 bridge). **C-PULSE-09 CLOSED** -- probe
fleet 11/11 on Windows AND Linux, `probe_adopt_smoke` steps 1..10, exit
0. **C-PULSE-13 CLOSED** (m232: `xiom pkg` resolves the compiler home;
verified installs + doctor). Suites x2 + smoke 78/78 on both platforms.
**C-PULSE-14: Windows FIXED on v0.64.2 (flat over 206 req); Linux still
grows ~87 KB/req steady -- worse than v0.64.1's ~48** (retest on the
next archive; m235 not in v0.64.2). Incident: a concurrent toolchain
re-extract wiped the WSL packages store mid-sweep (reinstalled via
`xiom pkg install`; green after). Score holds (~55.4%)._

_Delta 2026-10-09 (wrap 11, 0.1.1 cut): **session-store swap DONE** --
`src/session.xi` is now a wrapper over the registry `xiom.session` 0.1.0
store (128-bit hex ids, explicit-clock expiry, pruning; user as the
"user" entry) behind the identical HTTP contract; module renamed
`xiom.pulse.sessions` to dodge the C-PULSE-12 alias shadowing. Verified:
build + `probe_adopt_smoke` + suites x2 + smoke 78/78 on BOTH platforms.
Version bumped to **0.1.1** (rebuilt on v0.64.2 -- Windows memory flat /
BIND validation / docs), CHANGELOG + public set updated. Score holds
(~55.4%)._

_Delta 2026-10-09 (wrap 12): the 0.1.1 tag's CI gate failed on a stale
version literal in our own test suite (nothing published); tags are
immutable, so the fixed cut is **0.1.2** -- every expected-version
literal updated (pulse.xi, server APP_VERSION, http Server header x2,
test_smoke, test_http, smoke twins), re-verified with the pinned stdlib
before tagging. Also filed: the `@llvm.memset.p0i8.i64` IR warning
reproduces on Linux CI (llvm-16), not just darwin._

_Delta 2026-10-09 (wrap 13, 0.2 first unit): **OpenAPI contract live** --
`GET /openapi.json` serves the repo document with the running version
substituted at request time; the first CLI subcommands (`openapi`,
`routes`); config `PULSE_OPENAPI_PATH`; test_app +7 checks; smoke
**84/84** on both platforms (Linux pinned-stdlib). Roadmap 0.2 items 1/2
partially done -- problem+json, pagination, idempotency, `/v1`, flag
promotions next. Score holds (~55.4%)._

_Delta 2026-10-09 (wrap 13c): **error envelopes mirror the HTTP status
additively** (`{"error":{"status":N,...}}`; shared helper also covers the
405 Allow path) and the **CLI set is complete** (`version` +
`check-config` subcommands). test_app +3 checks; smoke **89/89** on both
platforms (Linux pinned-stdlib). Roadmap 0.2: item 2 done, item 1
partially -- pagination `Link`, idempotency keys, `/v1`, the
SSRF-guarded HTTP client and multipart next. Score holds (~55.4%)._

_Delta 2026-10-10 (0.2 pagination): **`Link` pagination on
`GET /api/events`** -- cursor decision: **seq-in-record**. Every event
written by 0.2+ carries a durable `seq`; pre-0.2 records fall back to
their 1-based ordinal among valid records (stable under compaction,
which only drops invalid lines). Responses gain `next_cursor` and, while
an older page exists, an RFC 8288
`Link: </api/events?limit=N&before=K>; rel="next"` header (kind filter
preserved, percent-encoded); `?before=K` walks backwards; malformed
cursors get `400 invalid_cursor`. One `store_page` API serves both
backends (`store_last`/`store_last_kind` are thin wrappers now).
test_app +16 checks; smoke 89 -> **100/100** on both platforms (Linux
with the pinned stdlib `4dd8844`). Harness fixes found while extending
the smoke: the PS twin now file-redirects server output (a full ~4 KiB
pipe deadlocked the single-threaded server mid-suite) and reads exit
codes through a cmd wrapper (`Start-Process -PassThru` leaves `ExitCode`
empty with redirection); `check` needles are wildcard-escaped.
Roadmap 0.2 item 1: pagination done -- idempotency keys and `/v1` next.
Score holds (~55.4%)._

_Delta 2026-10-10 (0.2 idempotency): **idempotency keys on event
writes** -- `POST /api/events` accepts `Idempotency-Key` (1-200 visible
bytes, else `400 invalid_idempotency_key`). A known key replays the
stored `seq` with `"deduplicated":true` and appends nothing; the marker
lives inside the event record (`idem`, JSON-escaped), so the guarantee
is durable and backend-agnostic (scan-based lookup, O(n) like the other
store reads). Responses carry `seq` now; keyed events list like any
other event. test_app +11 checks; smoke 100 -> **107/107** on both
platforms (Linux pinned-stdlib). Roadmap 0.2 item 1: idempotency done --
`/v1`, the SSRF-guarded HTTP client and multipart remain. Score holds
(~55.4%)._

_Delta 2026-10-10 (0.2 `/v1` alias): **`/v1` versioned namespace** --
`router.v1_path` strips the alias before matching, so every route
resolves under both forms (`/v1/api/events` === `/api/events`, query
preserved; `/v1/health`, `/v1/favicon.ico`, `/v1/assets/...` included).
New surfaces are introduced under `/v1` first; pagination `Link` headers
now preserve the client's prefix instead of hardcoding `/api/events`.
test_app +9 checks; smoke 107 -> **113/113** on both platforms (Linux
pinned-stdlib). Roadmap 0.2 item 1 complete -- the SSRF-guarded HTTP
client and multipart uploads remain. Score holds (~55.4%)._

_Delta 2026-10-10 (0.2 outbound): **outbound HTTP client base** --
`xiom.http` pin bumped to **0.1.4** (manifest + CI action; installed on
both platforms). The **SSRF guard** lives in the new dependency-free
`xiom.pulse.outbound` module: http/https only, userinfo refused,
localhost/.local/.internal/.home.arpa families refused, every numeric
IPv4 inet_aton form (dotted/short/octal/hex/decimal) refused when
loopback/private/CGNAT/link-local/multicast/reserved, IPv6
loopback/ULA/link-local/v4-mapped refused; `PULSE_HTTP_ALLOWLIST` flips
to a strict allowlist (private opt-in) and `PULSE_HTTP_MAX_BYTES` caps
responses. `probe_outbound_guard` joins the fleet (**12/12** green,
42 checks, both platforms; suites x2 + smoke 113/113 re-verified on
0.1.4). Transport finding: importing `xiom.http` links clean, but
calling the client fails at link (`curl_easy_*` + `xiom_read_byte`)
until the `--c-source` build hook -- so the libcurl half is isolated in
`src/outbound_transport.xi` (not imported by the server) and the ask is
refreshed in the package wishlist. Roadmap 0.2: multipart uploads
remain. Score holds (~55.4%)._

_Delta 2026-10-10 (0.2 multipart): **multipart uploads** -- new
`POST /api/uploads` surface (reachable at `/v1/api/uploads`) parses
`multipart/form-data` in the new `xiom.pulse.multipart` module (caps:
`PULSE_UPLOAD_MAX_BYTES` default 1 MiB per part, `PULSE_UPLOAD_MAX_PARTS`
default 8; the HTTP core's decoded-body cap still bounds the whole
request). Files land in `PULSE_UPLOAD_DIR` under generated names --
client filenames are never path components, only a sanitized extension
survives -- and the response lists name/original/bytes/content_type.
Stable errors: 415 `unsupported_media_type`, 400 `boundary_not_found` /
`malformed`, 413 `part_too_large` / `too_many_parts`. Found + filed
**C-PULSE-17** while testing: `io.list_dir` returns dangling names on
v0.64.2 (right `len`, corrupted bytes; cleanup deletes silently fail) --
repro `docs/repro/io-list-dir-dangling/`, workaround = no list_dir in
PULSE code (generated names from the response; `file_exists` probes).
test_app +12 checks; smoke 113 -> **119/119** on both platforms (Linux
pinned-stdlib). **Roadmap 0.2 PULSE-side slate complete** (API contract,
CLI, HTTP client base, uploads) -- remaining are upstream gates
(C-PULSE-14/16, darwin runtime-C) and the release cut. Score holds
(~55.4%)._

_Delta 2026-10-10 (0.3 interop start): **first ORBITDB/XVector consumer
conformance probes built and GREEN on both platforms** (Linux pinned
stdlib). `tests/interop/orbitdb/probe_pkg_orbitdb.xi` **39/39**
(roundtrip+reopen x2 at 1k keys, query edges, open/order/stale-handle
error paths, txn commit/abort, delete persistence) and
`tests/interop/xvector/probe_pkg_xvector.xi` **30/30** (exact Flat
roundtrip, top-k edges, dimension limits, delete/re-add, duplicate-id
overwrite, `wal_persist`/`wal_load`/`engine_recover` reopen, torn-tail
prefix). Both use the lanes' source-level composition pattern (nested
`xiom.toml` + relative `source-roots`), run where the sibling checkouts
exist, and are excluded from the CI fleet until the packages publish.
Trap note filed in the relays: `search(k=0)` / `create_collection(dim=0)`
are contract traps, not Err. Relay responses with probe results + the
§6 answers appended to both relay docs. Hard-kill / filter / hybrid
scenarios are the next tranche. Score holds (~55.4%)._

_Delta 2026-10-10 (0.2 docs refresh + release prep): **docs/public-set
refresh done** -- `index.md` lists the 0.2 surfaces; `configuration.md`
documents the five new knobs (`PULSE_UPLOAD_*`, `PULSE_HTTP_*`) and the
JSON overlay now actually applies the documented keys
(`store_backend`/`kv_dir`/`kv_prefix` were doc-only before; the five new
ones join them -- test_app +2 checks); `operations.md` covers the upload
dir in the env file and the backup policy; `http-api.md`/`security.md`
were refreshed with their units. Manifest drift fixed: `package.xi`
version 0.1.0 -> 0.1.2, `xiom.http` dep 0.1.2 -> 0.1.4, module list
completed (audit/openapi/schema/multipart/outbound + `sessions`
spelling). New `docs/RELEASE-CHECKLIST.md` encodes the mechanical cut
(every version literal incl. the twin `Server:` header occurrences,
preconditions, verify, tag/CI/ops steps, and the 0.2.0 content list).
Suites x2 + smoke **119/119** on both platforms after the config change
(Linux pinned-stdlib). Score holds (~55.4%)._

_Delta 2026-10-10 (wrap 14 follow-up 2: remaining interop + release
prep): **XVector filters (scenario 2) and the ORBITDB hard-kill harness
(scenarios 2/3) landed.** `probe_pkg_xvector` +12 checks (Eq / Range /
In / And / Or / Not / Exists vs the unfiltered scan, no-payload
semantics) -> **42/42**. The ORBITDB probe gains writer/verify modes
(`ORBITDB_PROBE_MODE`) driven by new twin runners
`scripts/interop_orbitdb_crash.{ps1,sh}`: 999 committed puts + one
uncommitted txn -> marker file -> SIGKILL of the whole tree -> verify
(`prefix_ok=true uncommitted_absent=1 append=true reopen=true`)
**GREEN on both platforms**. Found + filed **C-PULSE-18** while building
it: `time.sleep_ms` is a NO-OP on v0.64.2 (both platforms; repro
`docs/repro/time-sleep-noop/`; the writer busy-waits on a monotonic
deadline). The hybrid join stays with the ORBITDB lane's `probe_hybrid`
(green x2 on their side) until the 0.3 drivers compose it. Release prep:
`releases.md` gained the missing **0.1.2** entry, `install.md` examples
moved to 0.1.2, and the website relay gained **§14 -- the 0.2.0 cut
plan** (content deltas, four-leg artifacts, macOS button auto, ops
actions) for the website lane to relay to ops. The release pipeline was
**validated GREEN on main** by a manual dry run (run 38062166534:
guard + linux-x64 + windows-x64 package legs; macOS job skipped as
gated; publish skipped as expected for a dry run). Score holds
(~55.4%)._

_Delta 2026-10-10 (xiom.http 0.1.5 adoption -- outbound client REAL):
package-lane relay arrived: **0.1.5 (eco-v0.1.125) ships the curl-free
`bridge/xiom_http_shims.c` + the verified consumer recipe and closes the
link finding**. PULSE bumped the pin everywhere (xiom.toml,
package.xi, CI setup-action), installed both platforms, and built the
evidence-only runner `scripts/outbound_transport_probe.{ps1,sh}` +
`tests/probes/probe_outbound_transport.xi`: the probe compiles through
the recipe (`--c-source <installed>\bridge\xiom_http_shims.c --link curl
--link-path <scratch>`, curl-for-win 8.22.0 copy as `curl.lib`, kit DLL
beside the exe) and proves **guard blocks loopback -> allowlist opt-in
-> real GET 200** from a live PULSE server -- **GREEN on Windows and
Linux**. Harness lessons folded in: cmd `/c` first-token quoting trap
(generated `.cmd` files), `Start-Process -PassThru` empty `ExitCode`
(file-presence gate + `%errorlevel%` file). The wishlist entry is
RESOLVED; only the general C-consumption hook (auto `port.args.json`)
stays upstream. Score holds (~55.4%)._

_Delta 2026-10-10 (0.2.0 SHIPPED): **`pulse-v0.2.0` published** (tag on
`e31d396`, release run 38067869734 green; linux-x64 + windows-x64 zips +
sha256 + SHA256SUMS + provenance). Owner's call: macOS artifacts defer
to the next release, gated on two active bus items (arm64 memset codegen
-> compiler; Darwin x64 fp128 tf shims -> stdlib; four-leg dry run
38066169081 is the evidence). Content: the full 0.2 contract slate --
pagination `Link` + seq cursor, idempotency keys, `/v1` alias, OpenAPI
3.1 + CLI, multipart uploads, `xiom.http` 0.1.5 with the real SSRF-guarded
outbound client; smoke 119/119, suites x2 both platforms post-bump;
docs/public refreshed at the cut (releases.md 0.2.0, install.md
examples). Cut ping on the bus (`REL-20261010-1633-pulse` website,
`-2` owner). Score: API-contract row moves to shipped. (~56.0%.)_

_Delta 2026-10-10 (site mode, 0.3 fast-lane): **static site mode** --
`PULSE_SITE_DIR` serves a whole pre-built tree for unmatched GET/HEAD and
`/assets/*`: clean URLs, directory indexes, custom `404.html` (status
404), `application/wasm`, cache via `PULSE_SITE_MAX_AGE` (env + JSON
keys). API routes always win; traversal rejected by the engine. Verified
with a compact probe on the CI pairing (v0.64.3 + stdlib `48850df`):
`/` 200, `/about` 200, `/assets/*.wasm` 200 `application/wasm`, 404
page, `/health` wins; test_app +9 checks added (full-suite verification
delegated to clean CI runners -- the local box's clang crashes under
lane memory pressure). Local-env note: another lane upgraded the local
toolchain to v0.64.3 mid-session; the re-extract wiped the package
store (re-added all 10 pkgs) and the lane-HEAD stdlib now traps on
`read_file_bytes` ensures (`io.xi:947`) -- local builds should pin
`%LOCALAPPDATA%\xiom-pins\stdlib-48850df`. Unblocks the website
cutover and the playground static bundle (per the playground lane's
architecture item). Score holds (~55.4%; site mode row lands with the
cut)._

_Delta 2026-10-11 (post-wrap-15 checkpoint): **fresh regression baseline
on `496b568` is GREEN on both platforms with the pinned stdlib
`dd352f6`** -- probe fleet 12/12 (`probe_outbound_guard` +
`probe_stdlib_server_parse` included), m212 dash+dot gate (check AND
run), suites x2, smoke **119/119** (jsonl + kv), all on v0.64.3;
evidence `probe-logs/regress-20261011/` (win exe sha256 `928d2e1b...`,
linux `19c0384b...`; delta vs `regress-20261010` is shape-identical,
with the Linux legs now on the `dd352f6` pin). Bus: reporter
verification closed `REL-20261011-0317-pulse-3` (server_parse_request)
and `-4` (TcpStream.write_all loop) -- both already present in the pin
via `ec64dec`; locked by `probe_stdlib_server_parse` (11/11 both
platforms) and the stdlib `p_pulse_shapes` probe (exit 0 win+linux,
100000-byte loopback). Next: the framework backlog (security headers
first). Score holds (~55.4%)._

_Delta 2026-10-11 (security headers unit -- helmet adopt, backlog order
1): **every response now carries the reviewed security-header set** --
`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: no-referrer`, COOP/CORP `same-origin`,
`Origin-Agent-Cluster: ?1`, HSTS
(`max-age=15552000; includeSubDomains`), `X-DNS-Prefetch-Control: off`,
`X-Permitted-Cross-Domain-Policies: none`, `X-XSS-Protection: 0` --
emitted by both response builders via `http.security_head_lines()` at a
single assembly point (`with_std_headers`). `Content-Security-Policy` is
opt-in via `PULSE_CSP` / the `csp` JSON key (default off: site mode
serves pre-built trees whose inline scripts a strict default would
break). Evidence: test_http +12 checks (74 green, both builders incl.
CSP-absent default), full sweep FAILED=0 both platforms + smoke 119/119
(probe-logs/security-headers-20261011), csp-check integration run (env
wired end to end), CI dry run `38135447649` green (both package jobs).
Info to website `REL-20261011-1124-pulse`. Next backlog item:
keep-alive/deadlines design doc (h11 + fasthttp three-timeout model).
Score holds (~55.4%)._

_Delta 2026-10-11 (keep-alive/deadlines design doc, backlog order 2):
**`docs/DESIGN-KEEPALIVE-DEADLINES.md` landed** -- adopts fasthttp's
named three-timeout model (`PULSE_READ_TIMEOUT` / `PULSE_WRITE_TIMEOUT`
/ `PULSE_IDLE_TIMEOUT`; 408 on read expiry, silent close on idle expiry,
write-expiry drop) and the h11 keep-alive state rules (decision table,
start_next_cycle gating, MUST_CLOSE, trailing-buffer pipelining,
half-close coupling, per-request framing, bounded incomplete head).
Two-phase plan: A = deadlines (blocked on the stdlib runtime wave --
`REL-20261011-0317-pulse`/-pulse-2, plus the filed interface notes);
B = keep-alive on top of A (12 mapped tests, incl. the idle-expiry
silent close). Doc-only unit; no server change, no CI dry run needed.
Next backlog item: store durability design (bbolt). Score holds
(~55.4%)._

_Delta 2026-10-11 (store durability design -- bbolt ordering, backlog
order 3): **`docs/DESIGN-STORE-DURABILITY.md` landed** -- bbolt's
data-before-pointer discipline mapped to the store seam: sync-before-ack
commit points for event appends and audit lines
(`PULSE_STORE_SYNC`/`PULSE_AUDIT_SYNC`), compaction/rotation rename
ordering with a new `fsync_dir` ask to stdlib, seq-in-record as the
commit marker (monotonic, newest-valid-wins analog), backup fence
manifests (`fence_seq` + live-heal vs compacted-fence mode), and an
explicit claim table for what PULSE may assert when. Doc-only unit; no
server change, no CI dry run. Next backlog item: SQL migrations design
(knex). Score holds (~55.4%)._

_Delta 2026-10-11 (SQL migrations design -- knex discipline, backlog
order 4): **`docs/DESIGN-SQL-MIGRATIONS.md` landed** -- the knex model
(lock table + applied tracking + batches + UTC-lexicographic names +
strict up/down) plus PULSE corrections for its known weaknesses
(lock heartbeat + stale detection instead of the destructive unlock,
idempotent first-run DDL, strict applied-but-missing validation,
per-migration transaction rule incl. sqlite/MySQL caveats); runner
contract `pulse_app migrate status|up|down|create|break-lock`
(explicit CLI step, `PULSE_SQL_DSN`, backup-fence gate). Gated on a SQL
driver package (packages lane pinged). Next backlog item: OpenAPI
generation from route metadata. Score holds (~55.4%)._

_Delta 2026-10-11 (OpenAPI route-drift guard + single route table,
backlog order 5 -- partial): **the route table is now single-source**
(`router.route_defs()`; `route_match`, `routes_list` and the new guard
all derive from it -- the two hand-synced literal blocks are gone) and
**a structural drift guard fails the suite when a route never reaches
the contract** (`openapi.openapi_missing_routes()`: parses the served
document, walks every route, requires the templated path key + method
verb; test_app asserts zero drift). The undeclared `uploads` tag is
fixed; CHANGELOG notes the guard. Remaining for the item: emit the
`paths` object from the table (static overlay for prose/refs),
`openapi --check` CLI mode, retire the hand-written paths block. Next
backlog item: 0.4 middleware chain + jobs design. Score holds
(~55.4%)._

_Delta 2026-10-11 (middleware chain + jobs design -- backlog order 6,
ordered backlog complete): **`docs/DESIGN-MIDDLEWARE-JOBS.md` landed** --
nine named stages (request / parse / validate / beforeHandler / handler /
beforeSerialize / beforeSend / afterResponse / error) mapped onto the
current accept-loop ladder with the gate order preserved and the error
stage reachable from every stage; gin + fastify mechanics (precomputed
static tables, sent-guard short-circuit, reset contract, per-route
precompute escape hatch); bullmq portable core (attempts + fixed/
exponential backoff, due-time delayed heap, lock/heartbeat ownership,
two-phase stalled sweep, ownership-checked terminal writes) on a bounded
loop-boundary runner that never blocks accept. **Ordered framework
backlog now fully landed**: security headers shipped (c1b3618); designs
for keep-alive, store durability, SQL migrations, middleware and jobs
all in docs/, gated on the stdlib runtime wave / SQL driver package.
Next work when gates open: implement keep-alive Phase A (deadlines),
durability Phase A (sync points), and the middleware refactor (order
tests first). Score holds (~55.4%)._

_Delta 2026-10-11 (batch-5 witness ready): `docs/repro/handlerout-helper/`
landed -- witness.patch (the exact `&HandlerOut` ref-param Str-return
helper + one suite call, from REL-20261010-2122) and the re-verify
protocol. Re-run today on v0.64.3: suite exits -1073741819 (0xC0000005)
after compiling -- red confirmed in suite context (helper alone still
passes). Post-fix expectation: GREEN + `batch5 witness helper` PASS,
then re-land the helper permanently as the positive lock. Witness-ready
note filed to compiler. Score holds (~55.4%)._

_Delta 2026-10-11 (OpenAPI `--check` CLI): `pulse_app openapi --check`
landed -- runs the route-drift guard (`openapi_missing_routes`) against
the served document: exit 0 + OK; exit 1 + the missing list on drift.
Wired into the RELEASE-CHECKLIST verify step and documented in
http-api.md; verified locally green (rc 0) and drift-red (renamed
`/health` key -> `missing GET /health`, rc 1). Part of the openapi
generation remainder; the paths-emission generator stays open. Full
sweep both platforms + smoke 119/119 (probe-logs/openapi-check-20261011);
CI dry run dispatched with the push. Score holds (~55.4%)._

_Delta 2026-10-11 (doorbell: compiler batch 5 + v0.64.4 side-checks):
**batch-5 items closed** -- the frozen `&HandlerOut` witness runs GREEN
on m271/v0.64.4 (suite exit 0, incl. the helper check;
`probe-logs/witness5-m271-reverify.log`); `REL-20261010-1854/2122` moved
fixed->verified->closed (relay `6ce8946`). Permanent helper re-land
deferred until the CI toolchain pin moves to >= v0.64.4 (v0.64.3 still
red; patch frozen). **SIGILL 1615 negative side-check:** its repro still
dies 0xC000001D on m271 and v0.64.3 (A/B, isolated workdirs,
`probe-logs/sigill-check/`) -- the six batches do not cover it; **0.2.1
stays gated** on that fix; evidence filed to compiler
(`REL-20261011-1904-pulse`, high). `openapi --check` dry run
`38157843890` green (unit fully closed). Compiler cutting v0.64.4
(m271; all six batches). Also closed `REL-20261011-0317-pulse-7`
(module-scope fn-ptr, m265): witness `docs/repro/fnptr-harness/` exits 0
on m271, v0.64.3 control fails `error[C001]`. Score holds (~55.4%)._

_Delta 2026-10-12 (v0.64.4 wave: pin adopted, toolchain held): v0.64.4
installed + sha256-verified on Windows and WSL (WSL binary byte-identical
to the archive); the shared package store was found EMPTY during the
wave and the 10 pinned registry deps reinstalled
(`REL-20261012-1418-pulse-2`). **`STDLIB_VERSION` -> `3df0843`
(stdlib-v0.64.4) ADOPTED** (suites + smoke green under v0.64.3; CI dry
run `38261983177` green).
**Toolchain v0.64.4 adoption HELD**: a v0.64.4-built binary exits 0 at
startup with `PULSE_STORE_BACKEND=kv` (jsonl fine; v0.64.3 control serves
200; reproduced on both pins; standalone kv-API witness green; CLI paths
fine) -- repro `docs/repro/kv-hang-0644/`, filed to compiler
(`REL-20261012-1418-pulse`, high); CI pins stay v0.64.3 and the
`&HandlerOut` helper re-land rides the unblock. SIGILL `1615` still red on
the released v0.64.4 archive (0xC000001D); 0.2.1 remains gated. Wave sweep
evidence `probe-logs/toolchain-0644/` (FAILED=1 solely smoke-kv on the
v0.64.4 combo). Score holds (~55.4%)._

_Delta 2026-10-12 (production-grade relay, owner request):
**`docs/PRODUCTION-GAPS.md` landed** -- PULSE benchmarked against the
reference shelf (fastify/gin/fasthttp/h11/helmet/bbolt/knex/bullmq;
nginx at the TLS edge) with a 30-row parity matrix (12/30 fully green,
10 designed-and-gated on lanes, 8 missing), a definition-of-done for
production readiness, and lane ask tables. Filed to the bus: stdlib
wave 2 `REL-20261012-1946-pulse` (SIGTERM drain, poll/accept-deadline,
SO_REUSEPORT, chunked stream writer (SSE), websocket primitives,
gzip/deflate, linear-time json_parse, shutdown confirmation), packages
`-pulse-2` (SQL driver priority / vendored sqlite, HTML templates +
escaping), broadcast `-pulse-3` (all lanes). Internal backlog rows
added to PRODUCTION-REFERENCES (conditional/Range static, per-route
rate policy, fn-ptr test harness, SSE/WS units, tracing decision).
Score holds (~55.4%)._

_Delta 2026-10-12 (m276 + wave-115 verified): **kv empty-store
regression verified fixed** -- PULSE rebuilt with the fresh compiler
(m277 incl. m276 `0268c7d9`) serves kv mode on an empty dir
(`/health` 200 + `evt-seg-0000000001.kv`); toolchain re-adoption waits
for the next archive. **Durability primitives verified**:
`p_wave115_shapes.xi` exit 0 against stdlib `c65acb5` (wave 115) --
`io.fsync` + `sync_io.sync_fd` + real `io.flush_stdout`; durability
Phase A is cleared to implement once the re-vendored pin reaches
consumers (same caveat). Both closed on the bus (`d98e2f3`). Production
relay items acked by stdlib + packages; xvector/engine filed their own
gap relays. Score holds (~55.4%)._

_Delta 2026-10-13 (wave-119 landing -- keep-alive + durability
source-side unblocked): `0317-pulse` (socket options; Windows
SO_REUSEADDR root cause fixed), `-2` (deadline recv; 250 ms loopback
lock) and `1134-pulse` (fsync_dir; file-sync-before-rename /
dir-sync-after) all verified via the wave probes (`p_wave119_shapes`,
`p_wave115_shapes`, `p_wave60_shapes` -- rc=0 on stdlib
`a9b21b2`/`c65acb5` + wave runtime) and closed on the bus (`b413b0e`).
With `-5`/`-6` closed earlier, **every critical-path stdlib ask is now
fixed**: the next compiler pin that re-vendors stdlib/runtime (same
archive as m276+) unlocks toolchain re-adoption + keep-alive Phase A/B
+ durability Phase A/B implementation. Remaining gates: SIGILL `1615`
(0.2.1), macOS pair; production wave-2 asks acked. Score holds
(~55.4%)._

_Delta 2026-10-13 (game-backend positioning, owner question):
**`docs/GAME-BACKEND-POSITIONING.md` landed** -- PULSE is the game
HTTP/WS backend + control plane (accounts/sessions/JWT, matchmaking
queues + lobby metadata, leaderboards, inventory, telemetry ingest,
webhooks with idempotency, server register/heartbeat/allocate/drain),
while XIOM Engine owns the realtime plane (tick netcode,
UDP/QUIC/WebTransport, prediction, relays) -- the Nakama/PlayFab/
GameLift-control-plane split. Games raise WS/SSE, jobs/matchmaking
and multi-worker/sticky priorities. Engine lane informed with a
reuse offer for in-engine HTTP and a `/api/game/*` control-route
offer (`REL-20261013-1313-pulse`). Score holds (~55.4%)._

_Delta 2026-10-13 (owner endorsed the game-backend split): the owner
explicitly agreed with `docs/GAME-BACKEND-POSITIONING.md`; the engine
lane was told the split is the agreed architecture and asked to reply
with its in-engine HTTP stance plus the exact `/api/game/*` control
routes (`REL-20261013-1316-pulse`). Score holds (~55.4%)._

_Delta 2026-10-13 (wave-2 near-complete): stdlib wave 121 landed the
WebSocket helpers + chunked/stream writers + `send_all`, wave 122 landed
`socket_poll_read/write` + `SO_REUSEPORT` (POSIX double-bind locked);
probes `p_wave121_shapes`/`p_wave122_shapes` pre-verified rc=0
(`probe-logs/wave121-122/`). **Only signal delivery remains** from the
wave-2 ask; gzip (`xiom.compress`) and linear `json_parse` (wave 111)
were already resolved upstream -- PRODUCTION-GAPS corrected accordingly.
Score holds (~55.4%)._

_Delta 2026-10-13 (wave-2 CLOSED + engine contract): all wave-2 rows
delivered (waves 119-123); locks re-verified (p_wave121/122/123_shapes;
signals green on release v0.64.4 + stdlib main + XIOM_RUNTIME_DIR) --
`REL-20261012-1946-pulse` verified + closed. The production wave-2 ask
is source-complete (deadlines, drain signals, poll/select,
SO_REUSEPORT, chunked/stream writers, WebSocket helpers). The engine
lane replied with the **`/api/game/*` control-plane contract**
(`REL-20261013-1455-engine`, acked): register / heartbeat(+command
piggyback) / config(ETag) / compat / match-report / telemetry with
per-server bearer tokens + idempotency; engine reuses PULSE modules for
in-engine HTTP, never in the tick path. Queued as the next
PULSE-internal unit (not gated on the compiler pin). Score holds
(~55.4%)._

_Delta 2026-10-13 (game control plane SHIPPED): the P8 `/api/game/*`
contract is implemented -- register (per-server bearer token),
heartbeat (command piggyback), config (revision/ETag/304/409),
compat, match-report + telemetry (Idempotency-Key dedup), admin command
(ops token). Append-only kind-tagged records at `PULSE_GAME_PATH`;
config at `PULSE_GAME_CONFIG_PATH`; `PULSE_GAME_HEARTBEAT_SECS`
cadence; overlay keys added. 28 test_app checks + test_http GREEN on
the CI combo; openapi paths + `game` tag added (drift guard satisfied);
http-api docs + CHANGELOG; static conditional/Range row struck
(already shipped via xiom.static). Full sweep + CI dry run with the
push. Score holds (~55.4%)._

_Delta 2026-10-13 (SQL driver co-verify): `xiom.sqlite` 0.4.0 shipped by
packages; consumer co-verification result: **driver surface GREEN 24/24
on v0.64.4 and v0.64.3** (in-tree vendored sources + `--c-source`;
`docs/repro/sql-coverify/`). **Blocking packaging finding filed**
(`REL-20261013-1715-pulse`): published package.xi lacks the `modules:`
list -> `use xiom.sqlite;` unresolved for every external consumer
(control: xiom.kv imports fine); fix = modules list + consumer-import
smoke in the publish gate. Result posted (`REL-20261013-1718-pulse`);
artifact-level rerun on the fixed republish. Game-CP dry run
`38435178845` green. Score holds (~55.4%)._

_Delta 2026-10-13 (SQL artifact rerun): packages shipped 0.4.1 with the
modules list restored (eco-v0.1.175; install checksum+signature OK) --
`REL-20261013-1715-pulse` verified + closed. Artifact rerun on 0.4.1:
import accepted but dep symbols undefined (T001 cascades, both syntax
forms) -- residual blocker is the compiler multi-module
consumer-discovery bug (packages' kv-controlled A/B; their
1731-packages -> compiler; PULSE `--run` datapoint filed
`REL-20261013-1901-pulse`). In-tree control 24/24 green; artifact rerun
on the next compiler candidate. Score holds (~55.4%)._

_Delta 2026-10-14 (**SIGILL gate cleared at source**): compiler m297
(6797197d) fixed the Path.is_dir implicit-self recursion. PULSE
verification on the post-fix compiler (m305 range): witness
`p_path_println_context_crash` rc 0 (was 0xC000001D); server builds +
serves /health 200 in jsonl AND kv modes. Bonus: m303 resolved the
sqlite registry-artifact consumer blocker -- xiom.sqlite 0.4.1 probe
24/24 GREEN via `--run` (unqualified type-statics; README `driver.`
form nuance sent to packages). Ops HOLD the demo until the next archive
+ 0.2.1 redeploy ping (`REL-20261014-1305-pulse/-2/-3`). Sequence:
archive -> toolchain wave-2 (re-pin + helper re-land + sweep) -> cut
0.2.1 -> redeploy. Score: release gate progression counted; overall
holds (~55.4%) pending the cut._

_Delta 2026-10-14 (v0.64.5 candidate held): stdlib's release-gate
battery flagged candidate regressions (corpus 953/955; probe compilefails
`zext float` + duplicate `LinkedList.invariant_check`; crypto pair
lengths -1/AV; controls green on v0.64.4 -> wave suspects m314-m319) and
HELD the `stdlib-v0.64.5` tag (`REL-20261014-2123-stdlib`). The archive
now waits on a compiler fix wave + battery re-run; the SIGILL fix (m297)
is already in the candidate. PULSE wave-2 stays staged; no ops change
(demo hold until the release + our ping). Score holds (~55.4%)._

_Delta 2026-10-15 (**v0.64.5 RELEASED -- wrap 16**): the archive is
live (GH 19:18Z; windows `bd71e2d3...` / linux `246e5e82...`; paired
stdlib pin `092dfa0c` = the moved stdlib-v0.64.5; dl mirror at the next
:17). The release train held three times (m323-m327 regression wave, a
pin-era m296 smoke fix with the tag move, and pin-PR CI rounds) and each
time the gates caught it pre-publish. Next session: toolchain wave-2
(install, deps, pin cache, helper re-land, sweeps, CI pins, dry run)
then cut 0.2.1 per RELEASE-CHECKLIST + the ops redeploy ping -- full
recipe in SESSION.md §3 (wrap 16). Score holds (~55.4%)._

_Delta 2026-10-15 (wrap-16 addendum -- new release risk): xvector filed
`REL-20261015-2142-xvector` (high, compiler acked): **v0.64.5 linux-x64
miscompiles their HTTP service routing** (/search -> 404/400; 6 gates
red on WSL; v0.64.4-linux and v0.64.5-windows green; bundled-stdlib
repro). Since PULSE is an HTTP server and the demo is Linux, the wave-2
Linux legs and the 0.2.1 cut now carry an explicit routing-anomaly
stop-and-file gate (SESSION digest + §3 step 8 updated); if our Linux
legs are green, ops still validates routing before switching traffic
with 0.1.0 rollback armed. Score holds (~55.4%)._

_Delta 2026-10-15 (**v0.2.1 RELEASED -- wrap 17**): wave-2 adopted the
released **v0.64.5 + stdlib pin `092dfa0c`** (fleet 12/12, suites x2,
smoke 119/119 jsonl+kv, both platforms; dry runs `38802546194` +
`38808053663` green; the batch-5 `&HandlerOut` helper re-landed as a
permanent lock; SQL registry-artifact co-verify 24/24 on both
platforms). **`pulse-v0.2.1` is out** (GH published 21:23Z; linux
`81cce634...`, windows `df96da7c...`; release body carries the
highlights; dl mirror at the next :17 sweep) -- the v0.64.5 rebuild
with the SIGILL fix; ops pinged (`REL-20261015-2125-pulse`) to move the
demo 0.1.0 -> 0.2.1. Bus: SQL co-verify items closed (1718/1901);
bindings reply + compiler/stdlib INFOs filed. NEXT: the post-release
queue in SESSION.md §3 (keep-alive -> durability -> middleware/jobs ->
SQL runner -> bench -> SSE/WS -> macOS v0.64.6). Score holds (~55.4%)._

_Delta 2026-10-15 (top-tier directive): owner escalated the goal to
#1-class (multipurpose: static/apps/realtime, balancer scale-out,
safe/fast/secure, modern + legacy); `docs/ROADMAP-TOP-TIER.md` maps
the acceptance criteria T1-T9, the capability truth table (headline:
no TLS anywhere in-tree), workstreams W1-W10, and the 0.3/0.4/1.0
milestones; per-lane roadblock asks filed on the bus
(`REL-20261015-2202-pulse..-5`). No score change -- the directive
re-frames the plan; strict evidence-scoring still applies._

_Delta 2026-10-15 (site-mode 301 -- doorbell unit): the website lane's
full-tree pass on 0.2.1 found slash-less directory paths serving 200
with broken relative assets; fixed (`74cd0f9`): 301 to the canonical
slash form (prefix + query preserved), dir-before-file resolution so
POSIX directories no longer take the exact-file branch, three new suite
checks, `run.sh` log cap 200->400. Both platforms FAILED=0 (suites x2 +
smoke 119/119 jsonl+kv). Score holds -- correctness polish, no new
capability._

_Delta 2026-10-16 (keep-alive A+B): connection handling is production-
complete for the single-worker model -- per-request read deadlines
(408 from IDLE), non-blocking poll-gated write deadline (stalled
readers dropped; the Linux 50 MB stream check caught the blocking-send
bypass), and HTTP/1.1 keep-alive with the h11-adopted reuse rules:
comma-token `Connection: close`, HTTP/1.0 never reuses, in-order
pipelining via the trailing buffer with no data loss, silent idle
expiry, EOF-mid-message closes with no answer. `PULSE_KEEPALIVE=0`
restores close-per-request. Smoke 119->134; both platforms 134/134 x2.
Score: connection-handling row moves from partial to complete. The
Beacon freeze is GREEN (`56eb9f8`; milestone `REL-20261016-1401-pulse`
filed) -- next: the `xiom.pulse` extraction + the benchmark baseline
(pre/post keep-alive numbers)._

_Delta 2026-10-16 (consumer-verify `xiom.template` 0.2.0 -- top-tier
item 1c): the registry artifact (eco-v0.1.186; sha256 `bedd03a9...`)
renders **15/15 x2 on both platforms** on the v0.64.5 pin -- the block
surface (loops/inverted/dotted + auto-escaping `& < > " '`) verified
against realistic pages (a 404 error page + a docs nav page) plus the
exact strict-error texts; the v0.1 surface is unchanged. Consumer
recipe pins the dependency (undeclared imports bind to the stdlib
`xiom.string.template` Map surface -- documented in
`docs/repro/template-verify/`). W8 templates wrapper unblocked; score
holds (verification unit). The `xiom.pulse` (Beacon) extraction is IN
FLIGHT packages-side (porter carving `56eb9f8` ->
`packages/xiom-pulse`; `REL-20261016-1429-packages`)._

_Delta 2026-10-16 (packages evening wave): the top-tier packages path is
COMPLETE -- `xiom.ssl 0.1.0` (TLS headline) + `xiom.brotli 0.1.0` LIVE in
eco-v0.1.189 (template/otel/zstd already delivered); and the `xiom.pulse`
(Beacon) extraction is **GREEN + IN-TREE** (`053cab87`; 125/125 x2 on the
pin; ops scope asked). PULSE co-verify: all PROVENANCE source hashes
re-checked from our side at `56eb9f8` -- 14/14 match, the four verbatim
pairs byte-identical (`cmp`), the keep-alive A/B markers confirmed in the
carved loop, SPEC section 5 deviations reviewed and accepted; no surface
changes requested. Next: publish at LIVE -> consumer-verify the installed
artifact + prepare the Station-consumes refactor. Score holds (delivery +
verification units)._

_Delta 2026-10-16 (consumer-verify `xiom.ssl` + `xiom.brotli` -- top-tier
items 2 + 4): both registry artifacts (eco-v0.1.189) verified against the
INSTALLED package on the v0.64.5 pin -- **ssl: 14/14 live x2 (Windows)**:
a real TLS 1.3 handshake entirely over memory BIOs (no socket), app data
both ways, ALPN negotiated-read, clean shutdown, untrusted-cert rejection
with verify_result != 0; **4/4 SKIP leg x2 (WSL)**: the documented
no-libssl contract. **brotli: 11/11 x2 both platforms**: quality sweeps,
streaming both ways byte-exact, typed corrupt/truncated errors. Consumer
DX note: dependency builds auto-apply the package's port.args.json. The
top-tier package-path asks are now all consumer-verified except the
Beacon publish itself. Score holds._

_Delta 2026-10-16 (durability Phase A): **sync-before-ack landed** --
`store_append` fsyncs the append before acknowledging
(`io.append_line_sync`; `PULSE_STORE_SYNC`, default 1; `0` = documented
healing-only) and `audit_event` syncs before returning on the mutating
path (`PULSE_AUDIT_SYNC`, default 1); torn-tail healing preserved
(append_line_sync terminates the tail itself); `--check-config` prints
both + startup warnings when disabled; the claim table now allows
"writes acknowledged only after fsync" (DESIGN-STORE-DURABILITY P5).
test_app +11 checks (config surface + durable append); crash harness
re-run x2 both platforms; suites x2 + smoke both platforms green
(evidence: `probe-logs/toolchain-v0645/*-SWEEP-SUMMARY*.txt`; the first
linux pass was red on a stale runner pin -- `dd352f6` hardcode corrected
to `092dfa0c`, red summary preserved). CI dry run `38947560303` green on
both platforms. Storage 68 -> 72.
Total ~55.4% -> ~55.8%._

**Purpose:** one page the owner can read to see what a full
production-grade XIOM web backend consists of, what already works, and
what is still missing. Updated by the PULSE session at every step wrap.

**How to read the score:** each area has a weight (share of a
production-grade framework) and a completion %. The overall score is the
weighted sum. Scores are intentionally strict: "works in the soak" counts
only with evidence attached, and an area is not 100% until it survives
load, failure, and restart, not just the happy path.

---

## 1. Overall score: **~55.4% of production grade**

_Delta 2026-10-08 (kv backend): 54.6% -> ~55.6% -- **`xiom.kv` adopted as
the opt-in event-store backend** (`PULSE_STORE_BACKEND=kv`,
`PULSE_KV_DIR`/`PULSE_KV_PREFIX`; same store API, sequence-keyed records,
native compact; JSONL stays the default and documented fallback). Verified
on v0.64.1: smoke 73/73 through kv, store-soak 20s kv (89 writes, 0 fail,
compact + reopen counts intact), plus the default-backend smoke 73/73 and
test_app green as regression. Cross-module session-store swap still open
(C-PULSE-09); the kv path uses the single-module holder pattern._

_Delta 2026-10-08 (protocol round): 54.1% -> ~54.6% -- **`Expect:
100-continue`** handled (interim answered before the body read; raw-socket
proof: first line `HTTP/1.1 100 Continue`, final 200 logged; curls large
POSTs no longer stall 1s) and the missing **`Date`** response header
(spliced after the status line via `http.with_header_line`, RFC 1123
formatter reused from `xiom.static`). test_http +4 checks, smoke 73/73 on
both platforms._

_Delta 2026-10-08 (showcase round): 53.4% -> ~54.1% -- **general asset
serving** (`/assets/<path>` from `PULSE_ASSETS_DIR`, same
ETag/304/Range/traversal machinery; smoke 71/71 on both platforms) and
**per-site landing content** (`PULSE_LANDING_PATH`); **`PULSE_BIND`**
(default `127.0.0.1` -- **correction, wrap 8: not enforced in 0.1.x; see
C-PULSE-16** -- containers set `0.0.0.0`) and **`deploy/Dockerfile`** (ubuntu:24.04, verified: build +
container E2E health/version/assets). These are the prerequisites for the
`pulse.xiom-lang.org` / `orbit.` / `xvector.` showcase sites and the
offline benchmark harness (post-release)._

_Delta 2026-10-08 (pre-flight round): 53.2% -> ~53.4% -- **`--check-config`
CLI** (effective config dump, exits 1 only on an unreadable configured
file, never prints the secret; flags the dev-default JWT secret) and the
smoke twins invoke `--version`/`--check-config` before starting the server
(66 checks). Design note added: **integration seams for the new bindings
lane** (`E:\xiom-packages\bindings`; PULSE's storage/session/outbound
replacements plug behind single modules)._

_Delta 2026-10-08 (packaging round): 52.6% -> ~53.2% -- **Transfer-Encoding
smuggling guard** (any TE gets 501; CL.TE desync closed; test_app +
smoke 62/62), **status table completed** (206/304/501... were rendering
"Unknown"), **`scripts/release.{ps1,sh}`** (dist artifacts per the ops
naming, zip + sha256 verified on both platforms) and
**`scripts/backup.{ps1,sh}`** (timestamped store+audit snapshots, sha256
manifest, prune; both tested; restore runbook in DEPLOYMENT). Compiler
check: dl still v0.64.0; the lane-side m215/m216/m217 fixes (C-PULSE-08/
10/11) are the next adoption gate when v0.64.1 ships._

_Delta 2026-10-08 (schema round): 51.8% -> ~52.6% -- **JSON schema helper**
(`src/schema.xi`: typed rule list, required/optional, length + numeric
bounds, first-failure `code`/`field`/`message`) wired into the login and
token routes with field-specific 400s (probe 14/14); **flaky JWT tamper
check fixed** (append instead of replacing the last base64url char -- one
Windows run flaked on trailing-bit equivalence). Remaining M4 items
(keep-alive, recv timeouts, signals) are all gated on stdlib capabilities
already filed._

_Delta 2026-10-08 (ops items): 51.5% -> ~51.8% -- **audit rotation**
(`PULSE_AUDIT_MAX_BYTES`, single generation, probe + app E2E), **CLI
`--version`/`--help`** and **build-info fields in `/api/version`**
(commit/build from runtime env; compile-time define filed as a toolchain
ask). Signal handling checked: no stdlib handler-install API -> SIGTERM
graceful stop stays blocked; keep-alive stays gated on recv timeouts
(`socket_set_timeout` stub) because one idle keep-alive client would
stall the single-threaded loop._

_Delta 2026-10-08 (continuation): 51.2% -> ~51.5% -- **Windows
re-verify of the registry wave GREEN** (pkg installs + suites x2 + smoke
61/61 + crash 6/6 + rate); **stdlib adoption**: `TcpStream.write_all`
replaces the hand-rolled send loop, and `server_parse_request` now backs
PULSE's HTTP parser behind the same caps with invalid-Content-Length
hardening (differential probe pins parity on both platforms). Module
renamed `xiom.pulse.server` -> `xiom.pulse.app` (C-PULSE-12 alias
collision). Ops answered `docs/OPS-REQUEST.md`: staging parked by owner,
Linux toolchain source pinned on dl (v0.64.0 archive), CI mechanics ready
for greenlight._

_Delta 2026-10-07 (Linux/registry wave): 46.9% -> ~51.2% -- the **Linux
target verified end-to-end** (native ELF from the same v0.64.0 source:
suites x2 with 0 failures, smoke 61/61, crash 6/6, store-soak 20s,
proxy E2E 11/11 through Linux nginx 1.24 TLS on the extracted-package
path; crypto KAT env-free), **12 `.sh` twins** written and verified from
WSL, and the **registry wave**: `xiom.metrics` 0.2.0 (labeled counters +
latency preset), `xiom.static` 0.1.0 (ETag/Cache-Control/Range/304 +
traversal guard) and `xiom.http.middleware` 0.1.0 (CSRF/CORS) adopted
green. `xiom.session` store-integration and `xiom.kv` are filed as
C-PULSE-09/10 with repros; local store + JSONL remain the documented
fallbacks._

| # | Area | Weight | Done | Weighted | Status |
|---|---|---:|---:|---:|---|
| 1 | HTTP core (parse/build/limits) | 12% | 84% | 10.1 | query strings, header caps, HEAD, shared stdlib parser + invalid-CL reject, **chunked request decode** + TE/CL smuggling guard, Expect: 100-continue, Date header; **keep-alive + deadlines landed (A+B)**; chunked responses missing |
| 2 | Routing | 8% | 78% | 6.2 | registry `xiom.router` adopted (multi-`:param`, 404/405 + Allow); no wildcards/groups |
| 3 | Middleware framework | 8% | 30% | 2.4 | registry CSRF/CORS/error helpers adopted; still no composable chain |
| 4 | Configuration | 5% | 85% | 4.3 | env + JSON file (env-wins) incl. `PULSE_STATIC_DIR`; `--check-config` pre-flight with effective dump; **value validation warnings** (bad port/uint/TTL/bool/enum -> startup + check-config warnings); no schema library |
| 5 | Observability (log/metrics/audit) | 8% | 80% | 6.4 | registry metrics (labeled counters, latency-bounds histogram, exposition) + JSON log + audit with **rotation** + rid + gauges; flush real (wave 115); **audit sync (Phase A)** |
| 6 | AuthN/AuthZ | 10% | 35% | 3.5 | sessions + JWT HS256 + CSRF (constant-time via registry); no credentials, RBAC, rotation |
| 7 | Storage | 10% | 72% | 7.2 | JSONL store (default) + **xiom.kv backend** (opt-in, v0.64.2+, verified on both platforms incl. a **45m kv soak** -- 977/0, compact + hard-kill reopen intact), crash-safe append + **sync-before-ack (durability Phase A)**, `?limit`/`?kind`, compaction; no update/delete/index || 8 | Security hardening | 12% | 42% | 5.0 | rate limit + CSRF + opt-in CORS + security headers + caps + static traversal guard + schema helper + TE/CL.TE smuggling guard; **C-PULSE-16: `PULSE_BIND` advisory (wildcard bind below the app; host firewall mitigates) -- fix queued with the next release**; no RBAC |
| 9 | Static / assets | 4% | 70% | 2.8 | registry `xiom.static`: mime/ETag/Cache-Control/304/Range + favicon + `/assets/*` showcase route (`PULSE_ASSETS_DIR`) + `PULSE_LANDING_PATH`; no directory index/listing |
| 10 | Protocol extras (SSE/WS/REST/GraphQL/templates) | 8% | 0% | 0.0 | none started |
| 11 | Reliability & concurrency | 10% | 35% | 3.5 | **C-PULSE-14: Windows FIXED on v0.64.2 (flat); Linux still grows ~87 KB/req steady (worse than v0.64.1's ~48)**; single-thread, no signals; **read/write/idle deadlines landed (keep-alive A)** |
| 12 | Testing / CI / release | 5% | 88% | 4.4 | suites+smoke (78) on **Windows and Linux**; twins everywhere; **CI live (wrap 7): PR gates + SHA-pinned release workflow cut 0.1.0 end-to-end + weekly heavy soaks; macOS legs prepared, gated on upstream darwin fixes**; soak sampler fix + rss_probe twins; release packager + backup tooling; Dockerfile verified |
| | **Total** | **100%** | | **55.8** | |

**Framework roadmap:** `docs/FRAMEWORK-ROADMAP-PULSE.md` -- the 0.2-1.0
production-grade contract (driver seam, auth core, OpenAPI, CLI
subcommands, integrations, security gates) plus the all-OS 0.1.1
candidate plan (macOS x64/arm64 gated on the darwin blockers).

Two lenses to keep separate:

- **PULSE's own work:** ~80% of the Step 0-4 plan (Steps 0-3 core, the M4
  hardening wave, proxy E2E green on Windows and Linux, the Linux port +
  `.sh` twins, and the registry adoption wave except the two blocked
  packages).
- **Production-grade framework:** **~46%**. The gap is mostly *hardening*
  and *ecosystem maturity*, not basic function.

---

## 2. What works today (evidence-backed)

Run `out/` (Linux) or `out\pulse_app_v9.exe` (Windows); smoke 76/76 and
suites x2 on both platforms, these work end-to-end:

| Method | Path | What it does |
|---|---|---|
| GET | `/health` | liveness JSON |
| GET | `/api/version` | name + version |
| POST | `/api/echo` | echoes request JSON (400 on invalid) |
| GET | `/api/items/:id` | path-parameter demo |
| POST | `/api/session/login` | creates session, `Set-Cookie: sid` (HttpOnly, SameSite=Lax) |
| GET | `/api/me` | session lookup (401 without/expired) |
| POST | `/api/session/logout` | drops session, clears cookie |
| POST | `/api/token` | issues JWT HS256 (registry `xiom.jwt` 0.2.0) |
| POST | `/api/token/verify` | verifies signature + `exp`, returns payload |
| POST | `/api/events` | appends JSONL event (crash-safe) |
| GET | `/api/events` | last 10 events + count |
| GET | `/api/events/count` | event count |
| GET | `/metrics` | Prometheus text counters |
| GET | `/favicon.ico` | official app icon (187,396 bytes; also embedded in the Windows exe) |
| GET | `/` | landing page linking the icon |

Cross-cutting, working: router with 404/405+`Allow`, uniform error
envelope, env config, JSON access log with request ids and `dur_ms`,
structured metrics (counters + duration histogram), audit trail, cookie
sessions, JWT, crash-safe JSONL store, binary responses, request body
framing, global rate limiting (429 + `Retry-After`), graceful test
shutdown (`X-Pulse-Quit`).

**Load evidence:** 1h soak: PS driver 7,070/7,070 + WSL client 6,128,
server served **13,198/13,198** requests, 0 errors, clean shutdown; 64
simultaneous connections served, 64/64. **Memory caveat (wrap 6
correction):** the Windows "flat memory" figures from that era are
invalid -- `soak_http.ps1` sampled the `cmd.exe` wrapper, not the server
(fixed). Corrected: the request path grows RSS on **both platforms**
(~32 KB/req Windows over 587 requests; ~48 KB/req Linux over 3,097;
handles flat; pure Vec churn flat). Filed as C-PULSE-14 with repros
(`tests/probes/probe_alloc_loop.xi`, `scripts/rss_probe.{sh,ps1}`).

**Module inventory** (`src/`, all green in `tests/test_app.xi` x2):

| Module | Lines (rough) | Purpose |
|---|---:|---|
| `server.xi` | ~330 | accept loop, dispatch, send_all, log/audit wiring |
| `http.xi` | ~250 | request parse, response build (text/json/bytes) |
| `store.xi` | ~120 | JSONL append store, torn-line healing |
| `router.xi` | ~200 | app route table wrapper over registry `xiom.router`; query parsing + decoding |
| `session.xi` | ~100 | in-memory sessions, cookie bindings |
| `config.xi` | ~80 | env config with defaults |
| `metrics.xi` | ~120 | counters + request-duration histogram, Prometheus render |
| `ratelimit.xi` | ~50 | global token bucket wrapper over registry `xiom.rate` |
| `envelope.xi` | ~40 | error envelope |
| `pulse.xi` | ~15 | version |

---

## 3. What is missing, area by area (the honest list)

**HTTP core (84%)**
- No `keep-alive` (always `Connection: close`) -- the biggest perf item.
- Chunked REQUEST decoding landed (2026-10-08): caps, extensions ignored,
  trailers validated; TE+CL -> 400, other codings -> 501. Chunked
  RESPONSES still missing (they arrive with keep-alive/streaming).
- `HEAD` supported (GET semantics, body omitted); `Expect: 100-continue`
  handled; path not percent-decoded (query values are decoded).
- Head caps landed (16 KiB head, 100 headers, 1 MiB body); no per-route or
  per-connection byte-rate limits.
- Status is far from 100% even if all of the above land: response
  streaming, compression, HTTP/2 (proxy's job).

**Routing (78%)**
- Registry `xiom.router` 0.1.0 adopted: `src/router.xi` is a thin app
  wrapper (route ids + query parsing); consumer probe 8/8.
- Still missing: wildcards, optional segments, route groups, per-route
  middleware hooks, path percent-decoding.

**Middleware (30%)**
- Request-id/logging/audit are still wired inline in the loop.
- Registry `xiom.http.middleware` 0.1.0 adopted for CSRF token/validate and
  CORS header building; no composable chain, no recover-to-500.

**Configuration (85%)**
- Env-based with a JSON file (`PULSE_CONFIG`) for all eleven settings;
  environment variables win over file values.
- **Value validation warnings landed (2026-10-08):** invalid
  `PULSE_PORT`/rate/TTL/audit-size values, non-0/1 booleans and unknown
  store backends are reported once at startup (`pulse: warning: ...`) and
  in `--check-config` (`warning: ...`) instead of silently falling back.
- No general schema library beyond these per-setting checks.

**Observability (78%)**
- On registry `xiom.metrics` 0.2.0: labeled status-class counters, the
  11-bound latency-preset histogram, Prometheus exposition; JSON access
  log with `rid`/status/bytes/`dur_ms`; audit trail; request ids embedded
  in error envelopes; gauges (`pulse_app_info`, `pulse_store_records`,
  `pulse_uptime_seconds`).
- `io.flush_stdout()` is an empty body in the current stdlib -> logs can
  lag until process exit (stdlib wave queued).

**AuthN/AuthZ (35%)**
- Login trusts any username (no credential store/verification).
- Sessions are memory-only (lost on restart), no rotation on login.
- JWT: HS256 only, single static secret (dev default), no key rotation,
  no scopes/roles, no refresh tokens.
- No RBAC/authorization layer at all.

**Storage (68%)**
- Append + read last N (`?limit=1..100`) + `?kind=` field filter + count +
  compaction (temp file + atomic replace; drops torn lines); **10m soak:
  841 writes, 0 fail, compact/reopen counts intact, 0 mismatches**
  (`scripts\store_soak.ps1`); **kv soaks on Linux 20m + 45m** (756/0 and
  977/0, hard-kill reopen + native compact intact; single 90 KB segment).
  No update/delete, migrations framework,
  or indexes (fine at small scale).
- No `fsync` in the runtime: durability today = torn-tail healing, not
  power-loss safety (stdlib wishlist row added).
- `xiom.kv` 0.1.0 is the **verified opt-in backend** on both platforms
  (smoke 76/76 in wrap 4; default stays JSONL per the decision in
  `docs/PACKAGE-WISHLIST-PULSE.md`, which lists the flip prerequisites).

**Security hardening (42%)**
- TLS: front-proxy by design (Caddy/nginx); `docs/DEPLOYMENT.md` published
  with configs, supervision and a through-proxy verification checklist;
  the actual proxy E2E run is pending a proxy install.
- **C-PULSE-16 (wrap 8):** `PULSE_BIND` is advisory -- the stdlib
  `socket_bind` binds the wildcard (its address parameter is documented
  as ignored); repro: `PULSE_BIND=127.0.0.1` -> LISTEN `0.0.0.0`.
  Ops firewalled the demo (verified safe). Address-aware bind is filed
  with the compiler/stdlib lane; PULSE then enforces loopback and adds a
  smoke check on the LISTEN address.
- Global rate limiting landed (`xiom.rate` 0.2.0, `PULSE_RATE_LIMIT`,
  429 + Retry-After, `scripts/rate_smoke.ps1` green); per-client keys wait
  on `socket_peer_addr` (stdlib stub).
- CSRF double-submit on session-authenticated mutations (403 without the
  token; smoke-verified); opt-in CORS with preflight (204).
- Field length validation for `user`/`token`; no general schema library.
- Header size/count caps landed (16 KiB / 100); no recv timeouts yet
  (stdlib queued) -- a half-open request can still hold the loop.

**Static/assets (55%)**
- Favicon served through registry `xiom.static` 0.1.0: MIME map, ETag,
  Last-Modified, Cache-Control, `If-None-Match` 304, `Range` 206/416,
  traversal guard; landing page dynamic. No directory serving yet.

**Protocol extras (0%)**
- Templates, SSE, WebSocket, REST helpers, GraphQL: not started.
  Registry has `xiom.websocket`/`xiom.realtime`; GraphQL stays behind an
  interface (compiler-gated item).

**Reliability & concurrency (35%)**
- Single-threaded sequential accept (pin has no threads/select); 64
  concurrent works only because requests are short and queued by the OS.
- **C-PULSE-14 (cross-platform, corrected in wrap 6):** the request path
  retains ~32 KB/req (Windows) / ~48 KB/req (Linux) RSS linearly; the
  earlier "Windows flat" was a soak sampling bug (`cmd.exe` wrapper; now
  fixed). Handles/fds flat; pure Vec churn flat. Candidate lane fix:
  m235 "hoist loop-body static allocas" -- retest on the next archive.
  Until then: memory limit + restart cadence for any unattended instance.
- No transport timeouts; one stalled client blocks everyone.
- No signal handling / graceful in-flight drain (test-only QUIT).
- A trap anywhere kills the process (no supervisor/restart policy).

**Testing/CI/release (88%)**
- Local, both platforms: 3 suites (x2), smoke (78), crash/reopen (6),
  soak drivers (PS + shell), rate/store soaks, 20+ probes, byte-level
  lint greps. Every script ships as `.ps1` + `.sh` (LF enforced).
- **CI live (wrap 7):** `.github/actions/setup-xiom` (SHA-pinned
  toolchain + stdlib pin + store bridge + pinned deps), `ci.yml` PR
  gates (suites x2 + smoke, ubuntu/windows), `release.yml` (guard ->
  fleet -> packages -> GitHub Release on `pulse-v*`, provenance
  attested; cut 0.1.0 end-to-end), `heavy.yml` weekly 30m + kv soaks.
- **macOS legs prepared (wrap 8):** macos-x64 / macos-arm64 (suites +
  smoke + packaging); ship with the next release.
- No coverage number, no fuzzing; DCO + the suites are the PR gates.

---

## 4. Ecosystem blockers affecting PULSE (not PULSE's own code)

| Blocker | State (2026-10-08) | PULSE impact |
|---|---|---|
| C-PULSE-04 bare `&mut Int` read -> address | OPEN | keeps `*p` discipline; blocks cursor-style parsing in lane code |
| C-PULSE-05 const-receiver `.to_str()` W005 -> abort | OPEN (worse: 0x80000003) | `convert.int_to_string` workaround stays |
| C-PULSE-06 missing struct field -> garbage | OPEN | every struct literal must list all fields |
| C-PULSE-07 module-scope package ctor -> undefined call/crash | OPEN | package aggregates stay caller-owned (Vec-holder pattern pinned by `probe_pkg_state_holder`) |
| C-PULSE-08 m212 dotted-key roots | **CLOSED on v0.64.1** (m215) | gate dash+dot green on Windows and Linux (Linux after the C-PULSE-13 home bridge); `source-roots` kept only as belt-and-braces |
| C-PULSE-09 xiom.session store integration crash via wrapper modules | **CLOSED + SWAP DONE (2026-10-09)** | `src/session.xi` now wraps the registry `xiom.session` 0.1.0 store behind the same HTTP contract (module renamed `xiom.pulse.sessions` for C-PULSE-12); `probe_adopt_smoke` + suites x2 + smoke 78/78 green on BOTH platforms; ships in 0.1.1 |
| C-PULSE-10 xiom.kv kv_get Str corruption + bytes truncation | **CLOSED on v0.64.1** (m217) | `probe_pkg_kv` green; kv backend verified incl. the 20m soak |
| C-PULSE-11 package type alias invisible cross-module (defaults to i64) | **fixed in v0.64.1** (m216) | alias design compiles; swap re-tries on the C-PULSE-09 schedule |
| C-PULSE-12 module last-segment shadows an imported alias | OPEN (design around) | PULSE renamed the app module; import-alias syntax filed in the stdlib wishlist |
| C-PULSE-13 Unix pkg-home mismatch | **CLOSED on v0.64.2 (m232)** | `xiom pkg` resolves the compiler home; bridge removed from the WSL box AND the CI setup action; verified: installs land in `<home>/packages`, doctor OK |
| C-PULSE-14 request-path RSS growth | **Windows FIXED on v0.64.2 (flat, -240 B/req over 206 req); Linux OPEN and worse (~87 KB/req steady vs ~48 on v0.64.1)** | repros `rss_probe` twins + `probe_alloc_loop`; retest on the next archive (m235 was not in v0.64.2); the Linux demo keeps `MemoryMax` + restart |
| C-PULSE-16 `PULSE_BIND` not enforced (stdlib `socket_bind` wildcard-only) | **NEW, all platforms** | ops mitigated with the host firewall (demo verified); address-aware bind filed upstream; fix + LISTEN-address smoke check with the next release |
| C-PULSE-02 deps not mapped to catalog roots | **CLOSED on v0.64.1** (gate green; m212/m215) | dotted `[dependencies]` resolve to installed stores; PULSE keeps `source-roots` until a no-source-roots app build is verified |
| No toolchain exe icon (`xiom --icon`) | gap, workaround shipped | pinned rcedit in `build.ps1` + CI; new official icon art; exe icon verified locally |
| stdlib deadlines/timeouts, write_all, request parser, real flush | queued wave | slow-client guard, streaming, HTTP parse duplication, log lag |
| `xiom.router` 0.1.0 | **LIVE and adopted by PULSE** (probe 8/8, suites x2) | routing hardened; wildcards/groups remain package roadmap |
| `xiom.session`/`static`/`http.middleware` | static + middleware **adopted**; session single-module green, store integration gated | module replacement + middleware framework |
| Concurrency primitives (threads/select) | absent on the pin | caps throughput; single-threaded design |

Resolved on v0.64.0: C-PULSE-01, runtime-link (R65), crypto-link (m195).
Resolved on v0.64.1: C-PULSE-08, C-PULSE-10, C-PULSE-11, C-PULSE-02
(dependency-root gate green; no-source-roots app build pending).
`xiom.http` 0.1.2 republished and re-added (probe green on both
platforms) -- no known-red package gates remain; C-PULSE-13 is routed to
the compiler/installer lane.

---

## 5. Milestones (what "done" means next)

| Milestone | Criteria | State |
|---|---|---|
| **M1 -- Thin slice** | plaintext HTTP/1.1, routes, JSON, 404/405, curl + 64 concurrent + soak | **DONE** (2026-10-05) |
| **M2 -- App skeleton** | router, envelope, config, log, metrics, audit, sessions, JWT | **DONE** (core; hardening items above) |
| **M3 -- Storage** | durable store, schema, crash/reopen, soak | **DONE core** (JSONL; query/migrations pending) |
| **M4 -- Hardening** | timeouts, limits, keep-alive, rate limit, CORS/CSRF, validation, graceful shutdown, latency metrics | ~74% (registry metrics latency preset, static ETag/Range/304, CSRF via registry, caps, histogram, HEAD, stdlib write_all + parser, audit rotation, CLI surfaces, schema helper, TE smuggling guard; recv timeouts + signal handling blocked on stdlib) |
| **M5 -- Production ops** | TLS (proxy integrated + tested), CI pipeline, packaging, config files, runbooks, backup/restore | ~38% (TLS E2E on Windows **and** Linux; `.sh` twins; deployment runbook + ops answers; `--version`/`--check-config`/build-info; release packager + backup/restore tooling; `deploy/Dockerfile` + `PULSE_BIND`; CI pending greenlight) |
| **M6 -- Public release** | self-host compiler + mature stdlib/packages, full security review, versioned API, docs site | not started (owner gate) |

---

## 6. Production gates checklist (what 100% requires)

- [x] HTTP/1.1 plaintext service with parse+response builder
- [x] Routing with params, 404/405
- [x] Uniform JSON errors
- [x] Cookie sessions + JWT HS256
- [x] Durable append store with crash-safe reopen
- [x] Structured logs, metrics endpoint, audit trail
- [x] 1h load soak with flat memory/handles (Windows; Linux RSS growth
      open -- C-PULSE-14)
- [x] Request/header caps + query-string parsing
- [x] Rate limiting (global token bucket; per-client blocked on `socket_peer_addr`)
- [x] CSRF double-submit + opt-in CORS
- [ ] Keep-alive + chunked responses (Expect: 100-continue + request-chunked decode done)
- [ ] Schema validation library (field length caps landed)
- [ ] Real timeouts (recv deadline) and slow-client shedding
- [ ] Rate limiting + CORS + CSRF + security headers
- [ ] Schema validation for all inputs
- [ ] Credentials + RBAC; session persistence/rotation
- [ ] Graceful shutdown/signal handling + supervisor story
- [x] TLS end-to-end test through the proxy (Windows nginx + Linux nginx 1.24, 11/11 both)
- [ ] CI (suites+soak on push) + release packaging
- [ ] Static/templates/SSE/WS/REST extras (framework surface)
- [ ] Crash/chaos suite (kill -9 matrix, disk-full, corrupt store)
- [ ] Stable self-hosted toolchain (ecosystem gate)

---

## 6b. Integration seams for future bindings (design note, 2026-10-08)

PULSE keeps every external-system touch behind exactly one module so a
future **bindings-lane** package (`E:\xiom-packages\bindings`, worktree of
the packages lane) can replace the implementation without route changes:

| Seam | Module | Current impl | Binding replacement path |
|---|---|---|---|
| Event store | `src/store.xi` | JSONL append/compact (crash-safe) | same 6-fn API backed by a DB/KV binding package |
| Sessions | `xiom.pulse.session` | local vectors (`xiom.session` store swap deferred, C-PULSE-09) | store-backed sessions behind the same API |
| Static assets | route 14 via `xiom.static` | registry package | unchanged |
| CSRF/CORS | `src/cors.xi` + `xiom.http.middleware` | registry package | unchanged |
| Outbound calls | (none today) | -- | a future `src/outbound.xi` seam |

Rules: bindings arrive as registry packages (packages lane -> bindings
lane), are wrapped once per seam, and never get linked into route code.
Requests are tracked in `docs/PACKAGE-WISHLIST-PULSE.md` ("Bindings
lane").

## 7. How this score is updated

At every PULSE wrap: adjust only the areas with new **evidence** (soak,
smoke, suite, or repro), recompute the weighted total, and note the delta
in one line at the top. Evidence lives in `SESSION.md`, `docs/repro/`,
`probe-logs/`, and the smoke/suite scripts. Do not raise an area for
"code written" -- raise it when a test or soak proves the behavior.
