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
- Outbound HTTP (the 0.2 client seam) is SSRF-guarded: http/https only,
  userinfo refused, `localhost`/`.local`/`.internal`/`.home.arpa`
  families refused, numeric IPv4 in every inet_aton form (dotted, short,
  octal, hex, decimal) refused when loopback/private/CGNAT/link-local/
  multicast/reserved, and IPv6 loopback/unique-local/link-local plus
  v4-mapped forms refused. `PULSE_HTTP_ALLOWLIST` flips to a strict
  allowlist (and is the only way to opt private hosts in);
  `PULSE_HTTP_MAX_BYTES` caps responses. Caveat: the guard checks the
  literal host -- a public name that resolves to a private address (DNS
  rebinding) is stopped by the allowlist, not the blocklist.
- Mutating requests are written to the audit log (with rotation).
- Uploads (`POST /api/uploads`) are bounded: per-part and part-count
  caps, generated on-disk names (client filenames are never path
  components), and the same decoded-body cap as every other request.

## Known limits (the gap list)

- Single-threaded with no keep-alive and no receive timeouts: one slow
  client can hold the loop, and the proxy must enforce its own client
  deadlines.
- No graceful shutdown drain on SIGTERM; restarts drop in-flight
  requests.
- A memory-growth issue in the Linux request path is under investigation
  (upstream, C-PULSE-14; Windows is flat on v0.64.2). Run with a memory
  limit and a restart policy, and alert on RSS growth (see
  [Operations](./operations.md)).
- No credential/RBAC store: the login route is a demo; token issuance is
  not an identity system.
- No macOS artifacts yet; Windows and Linux are the tested platforms.
- No HTTP/2 or WebSockets; the proxy can terminate HTTP/2 to clients.

Claims about this project should stay within this page and the release
notes. If you find a security problem, please open a private report via
the repository's security tab or contact the maintainers.
