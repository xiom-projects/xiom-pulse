<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Security findings -- 2026-11-07 (framing, static, uploads)

**Status (2026-11-07):** framing and WebSocket are **fixed upstream**
(stdlib `30bacfa` / `e8ab289`) and the PULSE WS guard is fixed; both await the
next published toolchain pin for verification. The **static** item remains
open; uploads are fixed. The static high is release-blocking until the
toolchain pin + static fix.
Evidence: `tests/test_framing.xi` (fast parser/Station gate) and
`scripts/security_smoke.py` (live raw TCP, subcommands `framing`, `static`,
`upload`), plus the wrappers. Toolchain v0.65.6 + stdlib `6fdde4ee`.

## 1. Framing -- CRITICAL (stdlib; `REL-20261107-1032-pulse`)

| Finding | Observed | Expected |
|---|---|---|
| Duplicate Content-Length | `CL: 7` + `CL: 7` and `7` + `8` on `POST /api/echo` -> **200**, body echoed; first wins | reject, 400/close |
| Content-Length overflow | `CL: 999999999999999999999` on `GET /health` -> **200**; length reports 0 | reject, no wrap/desync |
| Whitespace before colon | `Content-Length : 7`, `Transfer-Encoding : chunked` -> **200**; header ignored, body bytes left | reject, 400/close |
| TE.TE | `TE: chunked` + `TE: identity` -> accepted as chunked, **200** | reject conflicting TE |
| LOW | `CL: +0`, `X-Test : v`, extra request-line token, leading-space obs-fold -> accepted | reject |

This is a proxy-differential/request-smuggling class (RFC 9112). The NUL
truncation finding `REL-20261106-1716-pulse` is the same class; `FRAMING_STRICT_NUL=1`
turns its five cases into hard failures. Live run: pass=22 fail=0 gap=10
known=5; `tests/test_framing.xi` is RED with 9 (12 strict).

**Upstream status:** stdlib **30bacfa** rejects duplicate/conflicting/
overflow/non-digit Content-Length, BWS before the colon, duplicate/non-chunked
TE, TE+CL, NUL/CTL/DEL in the head, extra request-line tokens/non-HTTP1.x and
obs-fold; new `smoke_net_framing_strict.xi`. Awaiting the next published
toolchain; the PULSE framing corpus stays known-red on v0.65.6.

## 2. Static canonical escape -- HIGH (packages; `REL-20261107-1032-pulse-2`)

- `mklink /J site\link-j <outside>` then `GET /link-j/outside-secret.txt` ->
  **200** with the outside canary (`OUTSIDE-CANARY-7f3a9c`). The lexical guard
  is not a canonical-path guard. Native symlink creation is skipped on this
  host (privilege); Unix CI exercises the same class.
- Encoded/dot-dot/backslash/NUL traversal is rejected (37/37); upload
  filenames stay inside the upload root.

## 3. Uploads -- HIGH/MEDIUM (PULSE-side fix)

Enforced today: per-part cap (413), part-count cap (413), total body cap
(413), generated names, duplicate fields/filenames stored separately,
NUL/CRLF filenames dropped.

Gaps accepted (200):
- **HIGH -- no MIME/extension allowlist:** `.php`, `.php` with
  `application/x-php`, `evil.txt.php`, `shell.PHP` are stored. If the upload
  directory is web-served/executed, this is RCE-capable.
- **MEDIUM -- active content:** `image/svg+xml` `.svg` and `text/html`
  `.html` are stored.
- **MEDIUM -- duplicate part `Content-Disposition`:** last-wins; `evil.php`
  overrides `dup.txt`.
- **LOW -- no part-header cap:** a 200 KiB part header is accepted.

**Resolved 2026-11-07:** the upload route now uses a strict multipart parser
with a default-safe extension + MIME allowlist, an 8 KiB part-header cap and
duplicate-`Content-Disposition` rejection; `.txt`/`text/plain` still uploads
200. `security_smoke upload` is **29/29 PASS, zero gaps**; `test_app` and the
live `http_smoke` (135) are green. Config: `PULSE_UPLOAD_ALLOWED_EXTS`,
`PULSE_UPLOAD_ALLOWED_MIMES`, `PULSE_UPLOAD_MAX_HEADER_BYTES` (all printed by
`--check-config`).

## 4. Harness and CI policy

- `scripts/security_smoke.py` is the shared engine; wrappers:
  `framing_smoke`, `static_traversal_smoke`, `upload_security_smoke`.
  `--allow-known-gaps` prints every `GAP:` line and exits 0; remove it for
  the strict release gate. `--strict-nul`/`-StrictNul` makes the NUL cases
  hard failures.
- `tests/test_framing.xi` is known-red; do **not** put it in the normal
  suite until the stdlib fix lands or the known-gaps mode is added. The live
  smokes are wired with `--allow-known-gaps` for visibility.
- The 1M/24h soaks are unrelated to these tests and stay heavy/uncapped-off.

## 5. Release impact

0.3.0/1.0 are held while these high/critical items are open. The framing fix
is stdlib/compiler; the static fix is `xiom.static`; the upload policy is a
PULSE change. The 24 h/1M memory gate remains separate and open.

## 6. WebSocket / SSE / OpenAPI / schema (2026-11-07)

### 6.1 WebSocket -- CRITICAL (stdlib; `REL-20261107-1349-pulse`)

A masked FIN text frame with 64-bit length `0x8000000000000000` (MSB set, no
payload) sent to `GET /api/ws` crashes the server on Windows
(`0xC0000005`) or hangs it; `/health` becomes unresponsive. The stdlib
`ws_frame_take` returns a negative consumed count; `src/stream.xi`
`drop_prefix` indexes with it. Remote unauthenticated DoS.

RFC 6455 gaps: RSV1 accepted/echoed; invalid UTF-8 echoed (no 1007); close
codes 1005/999/1-byte echoed; non-minimal 16/64-bit lengths accepted; a
declared `1<<40` length ends in a 1001 idle timeout instead of 1009/1002.
**PULSE guard fixed (2026-11-07):** `src/stream.xi` rejects MSB-set and
non-minimal lengths, oversize declarations, RSV, unmasked frames, control
violations, invalid UTF-8 and invalid close codes; the consumed count is
bounded. Strict `ws_negative_corpus` is **14/14**, `test_stream`/`test_app`/
`stream_smoke` are green. Upstream stdlib **e8ab289** fixes `ws_frame_take`
(relay 1349 fixed); awaiting the pin. The stdlib client `ws_recv` remains
exposed until the pin. Reserved opcodes 3-7/11-15 still close 1003 instead of
1002 (minor).

### 6.2 SSE (W-08/W-12) -- gaps

Basic SSE and disconnect/reconnect work (3 ticks/done/zero chunk; 8
mid-stream disconnects keep the server alive; exactly one access-log line per
connection; fds 61 -> 61). No `id:` on events, no `retry:`, and
`Last-Event-ID: 2` is ignored (the stream restarts at 1,2,3).

### 6.3 OpenAPI reverse drift (W-14) -- gaps

25 router routes + 2 stream routes; the document has 26 operations. All 25
router routes are present; no duplicates; `--check` is green and its failure
path works. `GET /assets/{path}` is documented but served by the
`dispatch_one` special case; `GET /api/sse` and `GET /api/ws` are in `routes`
but absent from the document.

### 6.4 Schema matrix (R-14) -- gaps

Missing/extra/wrong-type/nested/array/empty/65-char/malformed/top-level-array
behave with 400 `invalid_request`; extra scalar/nested fields are accepted by
design; Unicode length is byte-based (33 two-byte chars = 66 bytes rejected);
no enum; the number/bool/object/array rules exist but no product route
exercises them.

### 6.5 Harness

`scripts/gap_probe_lib.py` + `ws_negative_corpus.py`,
`sse_reconnect_probe.py`, `openapi_drift_probe.py`,
`schema_matrix_probe.py`, `gap_stream_probes.ps1`. WS is `continue-on-error`
in CI until the crash is fixed; SSE/OpenAPI/schema are blocking known-gap.
