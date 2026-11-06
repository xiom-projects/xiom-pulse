<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Independent security review -- fixed scope (WP2)

**Status 2026-11-06:** scope fixed; **not booked**. Engaging a reviewer and
the spend are owner decisions. This document is the package to send for a
quote; it is not a claim that a review happened.

## 1. Objective

An independent, time-boxed review of PULSE's request path and release chain
for the **1.0 production-grade** claim. The goal is to find exploitable
defects and design weaknesses before the 1.0 tag, not to certify the whole
XIOM stack.

## 2. In scope

- **HTTP/1.1 framing:** request line, headers, Content-Length,
  Transfer-Encoding/chunked (including trailers/extensions), 100-continue,
  keep-alive/pipelining, caps, timeouts, HEAD/204/304 framing.
- **Parser differentials:** how PULSE disagrees with nginx/Caddy or a
  language HTTP client on the same bytes (the NUL-in-head class,
  `REL-20261106-1716-pulse`, is an example).
- **Multipart** parsing, upload caps and stored filename handling.
- **Static/site mode:** clean URLs, directory redirects, traversal guard,
  MIME typing, ETag/Range.
- **Auth and session:** session cookie/store, CSRF, JWT HS256 verification,
  stream auth (`PULSE_WS_AUTH`), CORS, rate limiting, middleware order.
- **Data seams:** JSONL/KV store durability and the SQL opt-in surface
  (integrity, not a full database audit).
- **Observability:** request-id/log injection, secret redaction, error
  envelopes.
- **Release chain:** workflow permissions, tag/version guard, artifact
  substitution, checksums, provenance, SBOM generation, dependency pins.
- **Build scripts** and the documented deployment shape (plaintext loopback
  behind a TLS proxy).

## 3. Out of scope

- The compiler, stdlib and registry package internals (separate projects;
  integration points are in scope, their code is not).
- TLS/HTTP/2/HTTP/3 at the edge (Caddy/nginx configuration is operator
  responsibility).
- The example site's content and the benchmark harness.
- A full cryptographic review of the standard algorithms; JWT/session
  composition is in scope, primitive implementation is not.
- Social engineering, physical access and third-party SaaS.

## 4. Threat model and access

- **Exposure:** internet-facing behind a TLS-terminating reverse proxy;
  PULSE speaks plaintext HTTP/1.1 on loopback.
- **Attacker:** unauthenticated remote client sending arbitrary bytes;
  authenticated low-privilege user for the auth/session surface; a
  compromised dependency or a release-pipeline attacker for WP2.
- **Access:** source at a fixed commit, CI logs, a staging instance the
  reviewer may attack (no production data), the relay/issue tracker for
  findings. Test data is synthetic.
- **Rules:** no high-volume denial of service, no third-party systems, no
  data exfiltration; report critical findings immediately through the
  private channel in `SECURITY.md`.

## 5. Focus questions

1. Can two parsers disagree on method/target/header boundaries (smuggling,
   cache poisoning, auth bypass)?
2. Can a request escape the site/static root or read a file outside it?
3. Can a session/CSRF/JWT check be bypassed or fixed?
4. Can a rate-limit or body/header cap be bypassed with bounded impact?
5. Can a log/error/request-id field inject a line or leak a secret?
6. Can the release workflow publish an artifact that does not match the
   tagged source (pin, permission, substitution, SBOM gap)?
7. Are there memory-safety issues reachable from a request in PULSE code
   (not the compiler/runtime)?

## 6. Deliverables

- A written report per finding: severity (critical/high/medium/low),
  affected version/commit, repro, impact, fix guidance, and a retest plan.
- A remediation retest after fixes.
- A public summary suitable for the 1.0 release (CC BY 4.0), with the
  reviewer's name/affiliation if they agree.
- A short note on what was **not** covered, so the public claim stays honest.

## 7. Effort and schedule

- Proposed shape: a fixed-scope review of **10-15 working days** (about
  80-120 hours), split into review (8-12 days) and retest (2-3 days).
- Two rounds: initial report, then a retest of the fixed items.
- The review should land before the 1.0 tag and after the current WP1
  memory/scale work; the exact window is set with the reviewer.

## 8. Acceptance

- No open critical/high finding at the 1.0 tag.
- Medium/low findings have a documented fix or an accepted, published risk.
- The report, retest and public summary are published; the SBOM and
  reproducible-build recipe are available to the reviewer.
- The public material does not say "audited" beyond what the report covers.

## 9. Current PULSE-side preparation

- `SECURITY.md` (reporting, scope, disclosure/CVE, safe harbor) and
  `docs/SECURITY-POLICY.md` (triage, severity/SLAs, release gating).
- Deterministic parser fuzz gate in CI (`tests/fuzz_parsers.xi`) and the
  known NUL-in-head finding.
- CycloneDX SBOM generator (`scripts/sbom.py`, `docs/SBOM.md`).
- Reproducible-build recipe (`docs/REPRODUCIBLE-BUILD.md`).
- SHA-256 pins, provenance attestations, five-platform CI and release
  dry-run.

## 10. Open owner decisions

1. Reviewer selection and spend (the roadmap reserves the WP2 budget).
2. NDA / data-handling terms and the staging instance owner.
3. Whether the report is published in full or as a summary; default is the
   public summary in section 6.
