<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM PULSE -> OPS lane: staging + release/CI requests

**From:** PULSE lane (owner relay, 2026-10-07). PULSE is the official XIOM
web-backend external project; repo stays private until the owner says
otherwise. Everything below is a request for the ops lane; PULSE
provides configs and evidence, ops owns infra.

## A. Staging site `staging.pulse.xiom-lang.org`

1. **DNS:** A/AAAA record for `staging.pulse.xiom-lang.org` -> VPS.
2. **The one blocking question: VPS OS.** PULSE builds are currently
   **Windows x64 only** (XIOM AOT via clang/lld on Windows). If the VPS
   runs Linux, staging needs either (a) a Windows host, or (b) the
   compiler lane's Linux target before it can run there. Please confirm;
   PULSE will adapt the deploy steps accordingly.
3. **TLS + reverse proxy:** certbot for the subdomain; nginx site based on
   `deploy/nginx/pulse.conf.example` (TLS termination, HSTS,
   `Connection: close` upstream, 10s read timeouts, `/metrics` restricted).
4. **Service:** run the PULSE exe under a supervisor (Windows: NSSM or
   Task Scheduler with restart-on-failure; Linux: systemd when builds
   exist). Suggested env file: `PULSE_PORT=8080`,
   `PULSE_LOG=1`, `PULSE_STORE_PATH=<data>/pulse-events.jsonl`,
   `PULSE_AUDIT_PATH=<data>/pulse-audit.log`,
   `PULSE_JWT_SECRET=<from secret store>`, optional
   `PULSE_RATE_LIMIT`. Never commit the secret.
5. **Firewall:** public 80/443 only; the app binds loopback.
6. **Health/monitoring:** proxy health check on `/health`; scrape
   `/metrics` from the monitoring network (blocked publicly by config).
7. **Evidence PULSE provides:** `scripts\proxy_e2e.ps1` GREEN locally
   (TLS, HSTS, header hygiene, POST bodies, metrics, rid);
   `docs/DEPLOYMENT.md` runbook.

## B. Releases + CI (for when the repo goes public)

Mirror the `E:\xiom-lang\xiom` release model, artifacts on
`dl.xiom-lang.org`:

1. **Workflow:** on tag push -> full fleet (suites x2, smoke, rate smoke,
   30m soak) -> build artifacts -> checksums (+ signature if the xiom repo
   does) -> upload to the dl mirror -> GitHub Release notes.
2. **Artifact matrix:** `windows-x64` now; `linux-x64`, `macos-x64`
   (intel), `macos-arm64` (silicon) as the compiler's targets land.
   Each artifact needs the toolchain available on its runner (download
   the pinned compiler archive + stdlib, checksum-verified) -- ops input
   needed on runner OS availability and dl upload flow.
3. **Naming (proposal):** `pulse-<version>-<os>-<arch>.zip` containing
   `pulse_app.exe` (or `pulse_app`), `resources/img/pulse-ico.ico`,
   `README.md`, `LICENSE-*`, `NOTICE`; plus `.sha256` files.
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
- All PULSE scripts will ship as both `.ps1` and `.sh` (owner requirement)
  before the public release, so Linux contributors and CI runners can use
  them directly.
