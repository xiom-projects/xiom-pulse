# Changelog

All notable changes to XIOM PULSE. Versions match the release tags
(`pulse-v<version>`); highlights for each release also appear in the
GitHub release body.

## [0.1.0] - 2026-10-09

First public release (beta). Artifacts: `pulse-0.1.0-linux-x64.zip`,
`pulse-0.1.0-windows-x64.zip` (+ `.sha256`, combined `SHA256SUMS`).
Built with XIOM v0.64.1.

### Added

- HTTP/1.1 core: router with path parameters and query strings, JSON
  envelope responses, security headers, `HEAD`/`OPTIONS`,
  `Expect: 100-continue`, `Transfer-Encoding: chunked` request decoding
  with a `TE`+`Content-Length` refusal (smuggling shape) and `501` for
  other transfer codings.
- Sessions with CSRF protection, HS256 JWT issue/verify, global
  token-bucket rate limiting, opt-in CORS allowlist (comma-separated).
- Events API: append/list/count/compact over a crash-safe JSONL store
  (default) or the embedded `xiom.kv` backend (opt-in), plus an audit
  log with size-based rotation.
- Prometheus metrics, structured access log, `/health`, `/api/version`
  with optional build provenance env.
- Showcase serving: `/assets/*` static files (ETag/304/Range/traversal
  guard) and `PULSE_LANDING_PATH` (read per request).
- Configuration: environment + JSON file overlay, `--check-config`,
  value validation warnings for invalid settings.
- Operations tooling: release packager, kv-aware backup/restore twins,
  HTTP/TCP soaks, crash/reopen tests, 78-check smoke suite, Dockerfile.

### Known limits

- Beta: single-threaded, no keep-alive or receive timeouts yet; no
  graceful SIGTERM drain.
- Memory-growth issue in the request path under investigation (run with
  a memory limit + restart policy).
- No credential/RBAC store; the login route is a demo.
- macOS artifacts are not published yet.
