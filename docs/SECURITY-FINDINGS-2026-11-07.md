<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Security findings -- 2026-11-07 (framing, static, uploads)

**Status: OPEN. The high/critical items are release-blocking for 0.3.0/1.0.**
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

The PULSE fix is an upload policy (default-safe allowlist, extension + MIME,
double-extension, active-content) plus a part-header cap and duplicate
disposition rejection; the corpus is the acceptance test.

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
