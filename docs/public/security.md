---
title: Security and beta limits
description: Security posture and the honest gap list for 0.1.x.
---

# Security and beta limits

PULSE 0.1.x is an honest beta. This page states the security posture and
the known gaps; do not deploy it as a hard production service yet.

## Posture

- TLS terminates at the proxy; PULSE binds loopback and never sees
  plaintext from the network.
- `PULSE_JWT_SECRET` must be set from a secret store in any real
  deployment (the built-in default is for local development only).
- Sessions are CSRF-protected by default (`PULSE_CSRF=0` disables it
  only for controlled testing).
- CORS is opt-in and exact-match (comma-separated allowlist, or `*` for
  open demos); it is off by default.
- A global token-bucket rate limit is available (`PULSE_RATE_LIMIT`,
  `PULSE_RATE_BURST`); per-client limits belong to the proxy.
- Request parsing is defensive: bounded header block (16 KiB guard, 100
  headers), 1 MiB decoded body cap, `Transfer-Encoding` + `Content-Length`
  refused, other transfer codings `501`.
- Mutating requests are written to the audit log (with rotation).

## Known limits (the gap list)

- Single-threaded with no keep-alive and no receive timeouts: one slow
  client can hold the loop, and the proxy must enforce its own client
  deadlines.
- No graceful shutdown drain on SIGTERM; restarts drop in-flight
  requests.
- A memory-growth issue in the request path is under investigation:
  RSS increases with served requests (about 32-48 KB per request on the
  tested platforms). Run with a memory limit and a restart policy, and
  alert on RSS growth (see [Operations](./operations.md)).
- No credential/RBAC store: the login route is a demo; token issuance is
  not an identity system.
- No macOS artifacts yet; Windows and Linux are the tested platforms.
- No HTTP/2 or WebSockets; the proxy can terminate HTTP/2 to clients.

Claims about this project should stay within this page and the release
notes. If you find a security problem, please open a private report via
the repository's security tab or contact the maintainers.
