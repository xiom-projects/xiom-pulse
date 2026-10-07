<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> OPS lane: staging + release/CI requests

**From:** PULSE lane (owner relay, 2026-10-07, updated after the Linux/WSL
session). PULSE is the official XIOM web-backend external project; repo
stays private until the owner says otherwise. Everything below is a
request for the ops lane; PULSE provides configs and evidence, ops owns
infra.

## A. Staging site `staging.pulse.xiom-lang.org`

1. **DNS:** A/AAAA record for `staging.pulse.xiom-lang.org` -> VPS.
2. **VPS OS -- RESOLVED, Linux is fine.** The 2026-10-07 session verified
   that the Linux toolchain exists and works: XIOM compiler v0.64.0 is
   installed on WSL Ubuntu at the canonical Unix layout
   (`~/.local/share/xiom`), PULSE builds a native Linux ELF
   (`out/pulse_app`, x86-64, 609 KiB) from the same source tree, and the
   full runtime works (http smoke 61/61, suites x2, soak, TLS E2E through
   nginx on Linux). So **staging can run on the Linux VPS directly**; a
   Windows host is no longer required.
   Remaining ops input: the artifact source/pin for the Linux toolchain
   on the VPS (which installer/archive on dl.xiom-lang.org, checksum),
   and how to keep it updated. Windows-x64 remains the dev platform and
   both platforms are exercised from the same commit.
3. **TLS + reverse proxy:** certbot for the subdomain; nginx site based on
   `deploy/nginx/pulse.conf.example` (TLS termination, HSTS,
   `Connection: close` upstream, 10s read timeouts, `/metrics` restricted).
   Note for distro nginx on Linux: the temp paths must be set explicitly
   (`client_body_temp_path` etc.) when running unprivileged; the PULSE
   `.sh` E2E shows the pattern.
4. **Service:** run the Linux binary under systemd (restart-on-failure,
   env file). Suggested env: `PULSE_PORT=8080`, `PULSE_LOG=1`,
   `PULSE_STORE_PATH=<data>/pulse-events.jsonl`,
   `PULSE_AUDIT_PATH=<data>/pulse-audit.log`,
   `PULSE_JWT_SECRET=<from secret store>`, optional `PULSE_RATE_LIMIT`,
   `PULSE_STATIC_DIR=resources/img`. Never commit the secret.
   `X-Pulse-Quit: 1` is the graceful test-shutdown hook; production
   supervision should send SIGTERM/SIGKILL (signal handling is on the M4
   list).
5. **Firewall:** public 80/443 only; the app binds loopback.
6. **Health/monitoring:** proxy health check on `/health`; scrape
   `/metrics` from the monitoring network (blocked publicly by config).
7. **Evidence PULSE provides:** `scripts/proxy_e2e.ps1` GREEN (Windows
   nginx) **and** `scripts/proxy_e2e.sh` GREEN 11/11 from WSL Linux (nginx
   1.24, TLS, HSTS, header hygiene, POST bodies, metrics, rid);
   `docs/DEPLOYMENT.md` runbook; the full `.sh` twin set below.

8. **Build/test modes PULSE has verified (answering the owner question):**
   - **WSL (recommended for builds):** the Linux compiler produces native
     Linux binaries; all 12 `.sh` scripts were written and verified from
     WSL on 2026-10-07 (dev-env, run, build, http_smoke, soak_http,
     soak_tcp, concurrent, crash_test, rate_smoke, store_soak,
     proxy_e2e; shared `scripts/lib.sh`).
   - **Docker (recommended for the staging rehearsal / CI once a Linux
     archive is published):** run the Linux `pulse_app` in a clean
     `debian:bookworm-slim`-style container (glibc-compatible) and nginx
     as a second container or sidecar for the TLS path; this reproduces
     the VPS composition hermetically. Caveat observed on the dev box:
     Docker Desktop's WSL integration puts containers in their own network
     namespace, so container-to-WSL-host proxying needs host networking or
     running both sides in containers; on a real Linux host this is a
     non-issue.
   - Docker adds isolation/repeatability, not new capability: WSL alone
     is sufficient for daily verification today.

## B. Releases + CI (for when the repo goes public)

Mirror the `E:\xiom-lang\xiom` release model, artifacts on
`dl.xiom-lang.org`:

1. **Workflow:** on tag push -> full fleet (suites x2, smoke, rate smoke,
   store soak, 30m soak) -> build artifacts -> checksums (+ signature if
   the xiom repo does) -> upload to the dl mirror -> GitHub Release notes.
2. **Artifact matrix:** `windows-x64` (primary) **and `linux-x64` --
   verified buildable today from the Linux toolchain**; `macos-x64`
   (intel), `macos-arm64` (silicon) as those targets land. Each artifact
   needs the toolchain on its runner (download the pinned compiler +
   stdlib, checksum-verified) -- ops input needed on runner availability
   and dl upload flow.
3. **Naming (proposal):** `pulse-<version>-<os>-<arch>.zip` containing
   `pulse_app.exe` (Windows) or `pulse_app` (Linux), plus
   `resources/img/pulse-ico.ico`, `README.md`, `LICENSE-*`, `NOTICE`;
   plus `.sha256` files.
4. **Version stamping:** PULSE will add build-info (version + commit)
   surfaced in `/api/version` and `pulse --version` before the first
   public release; ops to confirm the version/tag convention matches the
   xiom repo.
5. **Need from ops:** dl.xiom-lang.org upload credentials/automation,
   runner/OS matrix confirmation, secret storage for the workflow,
   branch/tag protection rules, and whether staging should auto-deploy
   from `main` once public.

## C. Owner notes

- PULSE repo has an `origin` (github.com/xiom-projects/xiom-pulse) but
  nothing is pushed without owner approval; CI files should be added only
  when the owner green-lights going public.
- `.ps1` + `.sh` twin requirement: **DONE** (2026-10-07) -- every script
  ships as both, `.sh` verified from WSL, LF enforced via `.gitattributes`.
