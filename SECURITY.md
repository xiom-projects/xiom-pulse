<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Security policy

PULSE is pre-1.0. We take parser, auth and release-integrity reports
seriously and will credit good-faith research. This file is the public
contract; the internal triage and fix process is in
`docs/SECURITY-POLICY.md`.

## Supported versions

| Version | Status |
|---|---|
| `main` | supported (development line) |
| `0.2.x` / `pulse-v0.2.*` | supported until the next minor line replaces it |
| older tags | best effort, no guarantee |

The toolchain (compiler/stdlib) is a separate project; report compiler or
stdlib defects to the XIOM compiler/stdlib repositories, not here.

## Reporting a vulnerability

**Use GitHub private vulnerability reporting** on
`xiom-projects/xiom-pulse` (Security -> Report a vulnerability). If that
channel is unavailable, open a minimal public issue asking the maintainer
for a private channel; do **not** include exploit details, tokens, customer
data or a working denial-of-service recipe in a public issue.

Please include:

- affected version/tag and platform, and the exact commit if known;
- a minimal repro (request bytes or a small program) and the observed vs
  expected behavior;
- the impact you believe it has (for example: request smuggling,
  authentication bypass, path traversal, memory disclosure, crash);
- whether the report is under embargo and the date you plan to disclose.

Do not send secrets or third-party personal data. Test only against an
instance you own or are authorised to test.

## What is in scope

- The HTTP/1.1 parser and framing: request line, headers, Content-Length,
  Transfer-Encoding/chunked, caps, keep-alive, 100-continue.
- Multipart parsing, static/site path resolution and traversal guards.
- Sessions, CSRF, JWT verification, CORS, rate limiting and stream auth.
- The release pipeline: artifact integrity, provenance and the published
  checksums.
- Memory-safety issues in PULSE code reachable from a request.

## What is out of scope

- TLS/HTTP/2/HTTP/3 implementation at the edge (we tell operators to use
  Caddy/nginx; an edge misconfiguration is not a PULSE defect).
- The compiler, stdlib or third-party registry packages (report upstream;
  we will relay a PULSE-side guard if one is possible).
- Resource-exhaustion reports that only restate the documented single
  process/per-request caps. A bypass of a cap is in scope.
- Social engineering, physical access and dependency CVEs without a
  reachable PULSE path.

## Response targets

| Step | Target |
|---|---|
| Acknowledge | 3 business days |
| Triage + severity + plan | 10 business days |
| Fix: critical / high | 30 days |
| Fix: medium | 90 days |
| Fix: low | next scheduled release |

These are targets, not warranties. A complex parser or release-chain issue
may take longer; we will tell you the revised plan rather than go silent.

## Disclosure and CVE

We prefer coordinated disclosure. We will:

1. confirm the issue and agree a disclosure date with you (default: within
   90 days of the fix, or sooner by agreement);
2. request a CVE through GitHub Security Advisories when the issue warrants
   one, and publish the advisory with the fixed version;
3. credit you in the advisory unless you ask to remain anonymous;
4. publish the fix, the test/repro and (where relevant) the relay item or
   commit reference.

If a report is already public, tell us and we will move to a same-day
triage. We will not threaten or pursue good-faith research conducted under
this policy.

## Current assurance status (honest)

- **No independent external audit has been completed.** Do not treat PULSE
  as audited.
- A deterministic parser fuzz gate runs in CI (`tests/fuzz_parsers.xi`,
  `scripts/fuzz_parsers.ps1`/`.sh`): HTTP request parsing, chunked framing,
  multipart, urlencoded forms and HTML escaping.
- A **known upstream parser finding** is open: a NUL byte in the request
  head truncates the parsed method/target/headers
  (`REL-20261106-1716-pulse`, stdlib). The Station dispatcher rejects the
  empty method/target shape as defense in depth; the Beacon package needs
  the upstream parser fix. Do not rely on NUL-containing requests being
  rejected until that fix lands.
- Release artifacts are SHA-256 pinned with build provenance; see
  `docs/repro/` and the release workflow. An SBOM and a reproducible-build
  recipe are not yet published.

## Contact

Maintainer: Eleftherios Notas (`@lefterisnotas` on GitHub). The relay bus
(`xiom-relays`) is for cross-lane engineering coordination, not for public
vulnerability reports.
