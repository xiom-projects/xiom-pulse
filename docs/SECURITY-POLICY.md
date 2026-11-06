<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Security triage, fix and disclosure process (internal)

**Status 2026-11-06.** Companion to the public `SECURITY.md`. This is the
operational process for the PULSE lane; it does not replace the public
reporting channel.

## 1. Intake

1. A report arrives through GitHub private vulnerability reporting (or is
   relayed by the owner).
2. Create one relay item (`to: <owning lane>`, `kind: bug`, severity) with
   the minimal repro and the affected version. Never paste secrets, tokens
   or customer data into an item.
3. Acknowledge the reporter within 3 business days with the item id and the
   next checkpoint.

## 2. Severity

| Severity | Examples | Fix target |
|---|---|---|
| **Critical** | remote code execution, authentication bypass, request smuggling with a demonstrated impact, release artifact substitution | 30 days, hotfix if a release is live |
| **High** | parser differential that changes routing/auth, traversal outside the site root, memory-safety crash reachable from a request, session fixation | 30 days |
| **Medium** | cap bypass with bounded impact, information disclosure in an error/log, CSRF gap on a state-changing route | 90 days |
| **Low** | hardening gap with no demonstrated impact, documentation/claim mismatch | next release |

When in doubt, start one level higher and downgrade after triage.

## 3. Triage questions

- Is the issue reachable in the stock Station server, the Beacon package,
  or only in an application built on it?
- Does it cross a trust boundary (proxy -> PULSE, PULSE -> store, release
  workflow -> artifact)?
- Is there a parser differential (a front proxy and PULSE disagree)? Treat
  it as high until disproven.
- Is there a cap/timeout that bounds the impact? A bypass is in scope; the
  documented cap is not.
- Does it reproduce on the current published archive, not just a local
  candidate?

## 4. Fix and evidence

- Write the failing test first (suite, smoke or fuzz invariant) where the
  behavior is reachable in PULSE code.
- If the root cause is upstream (compiler/stdlib/package), file the relay
  item with a minimal probe under `tests/probes/` or `docs/repro/`; add a
  PULSE-side guard only where it does not mask the upstream fix.
- Verify on the published toolchain/package pin, across the five CI legs
  when the fix is release-relevant.
- Update the parity row, `docs/STATUS-FOR-WEBSITE.md` (if the public claim
  changes) and `docs/PROGRESS.md` in the same unit.

## 5. Disclosure and CVE

- Use GitHub Security Advisories for the private draft and the CVE request.
- Advisory content: affected versions, fixed version, impact, workaround,
  credit, and a link to the test/repro (not raw exploit payloads).
- Default embargo: fix + 90 days, or sooner by agreement with the reporter.
- If the issue is already public, publish the advisory and remediation
  without waiting for the embargo.
- After publication, add the advisory to the release notes and the public
  status brief.

## 6. Release gating

A release is not cut while an open **critical** or **high** item is
unfixed, or while a known parser differential lacks either an upstream fix
or a documented, tested PULSE-side guard. Medium/low items may ship with a
documented workaround and a target release.

## 7. Assurance status and backlog

**Shipped:**

- Deterministic parser fuzz gate in CI: `tests/fuzz_parsers.xi` +
  `scripts/fuzz_parsers.ps1`/`.sh` (HTTP request/chunked, multipart,
  urlencoded, html_escape; ~45k iterations per run, PCG seeded).
- Public reporting policy (`SECURITY.md`) and this process.
- SHA-256 pins + build provenance in the release workflow.

**Open:**

- Independent, fixed-scope external review (WP2, month 7).
- SBOM (CycloneDX or SPDX) generated and attached to the release.
- Reproducible-build recipe with documented platform deltas.
- Fuzzing beyond parsers (auth/JWT, session, static path, release inputs).
- A public CVE/advisory history (none yet).

**Known findings:**

| Ref | State | Note |
|---|---|---|
| `REL-20261106-1716-pulse` | open (stdlib) | NUL in the request head truncates method/target/headers; Station guard rejects the empty shape; Beacon needs the parser fix |

## 8. Roles

- **PULSE lane:** intake, repro, PULSE-side fixes, release gating, docs.
- **Owner:** external reports, embargo decisions, CVE/advisory publication
  where GitHub permissions require it.
- **Compiler/stdlib/packages lanes:** upstream root cause + fix refs.
- **Ops:** incident response for a live deployment (rotate secrets, take
  the edge offline, preserve logs) before the code fix lands.
