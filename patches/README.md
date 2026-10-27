# Local patches (applied in the lane package home, pending upstream)

These are **not** applied by the repository build. They live here so the
experiment is reproducible and can be handed to the owning lane.

## beacon-0.3.1-http-alloc.diff

Target: `xiom.pulse` (PULSE Beacon) 0.3.1, file `src/http.xi`.
Applied locally at:
`%LOCALAPPDATA%\xiom-pulse-home\packages\xiom-pulse-0.3.1\xiom-pulse\src\http.xi`
(backup: `http.xi.orig` in the same directory).

### What it changes

1. `security_head_lines()` returns one string literal instead of a
   10-step `+` chain (each `+` allocated a fresh Str).
2. `build_response_full` / `build_response_bytes` append straight into one
   pre-sized `Vec[UInt8]` (`append_str`) instead of building a `head` Str
   line by line and copying it twice.
3. `with_header_line` pre-sizes the output and appends `line` directly
   (no `line + "\r\n"` Str, no intermediate byte Vec).
4. `parse_request` pre-sizes the header name/value Vecs and skips
   `str_trim` when the parser left no surrounding whitespace.

### Measured (v0.65.2 + stdlib-v0.65.2, Windows x64)

`tests/probes/probe_req_cycle.xi`, 50k iterations, peak RSS:

| mode | before | after |
|---|---|---|
| `build` | 5,590 B/iter | **60 B/iter** |
| `parse` | 7,993 B/iter | 7,963 B/iter (unchanged; stdlib-owned) |

Product `GET /health` retention (`scripts/post_retention_probe.ps1`):
keep-alive steady **40.9 -> 29.9 KB/req**; connection-per-request steady
~33.5 KB/req.

Correctness: `test_http`, `http_smoke` 135/135, `stream_smoke` 20/20,
`ws_auth_smoke` 11/11 all green with the patch applied.

### Apply locally (Windows lane home)

```powershell
$h = "$env:LOCALAPPDATA\xiom-pulse-home\packages\xiom-pulse-0.3.1\xiom-pulse"
Copy-Item "$h\src\http.xi" "$h\src\http.xi.orig" -Force
git apply --directory="$h" patches\beacon-0.3.1-http-alloc.diff
```

(The diff paths are `a/src/http.xi` / `b/src/http.xi`; `--directory`
points at the package root.)

### Upstream

Filed to the packages lane (`REL-20261027-*`, see the bus) for a Beacon
0.3.2 publish. Until then PULSE builds here see the patch; CI builds do
not, so CI retention numbers remain the unpatched ones.
