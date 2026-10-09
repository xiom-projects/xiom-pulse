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
   env file). Suggested env: `PULSE_PORT=8080`, `PULSE_BIND=127.0.0.1`
   (**address only -- the port goes in `PULSE_PORT`; never
   `addr:port`**), `PULSE_LOG=1`,
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

## D. Ops answers (received 2026-10-08) -- staging parked, local lane unblocked

**Owner decision: PULSE stays local (WSL + Docker) for now.** The VPS
staging package is parked until the owner greenlights the project going
real/public; nothing on the VPS is scheduled. PULSE needs nothing from ops
right now. When greenlit, ops executes the following (already specified):

1. **Linux toolchain source (was the open question):**
   `https://dl.xiom-lang.org/releases/<tag>/` carries `SHA256SUMS` +
   `xiom-<ver>-linux-x64.tar.gz`. Current: **v0.64.1, 29,352,608 B,
   published 2026-10-08, sha256
   `6f6787a3ff068929593270d849c21b1f597036f2152bc830e357b980c91b5601`**
   (`latest.json` names it). Archive root is `bin/xiom` + `lib/`; set
   `XIOM_BIN=<dir>/bin/xiom` and `XIOM_STDLIB=<dir>/lib`. Pinning pattern:
   version file + download `SHA256SUMS` + asset, `sha256sum -c`, extract;
   dl assets are immutable so old pins keep working; update = bump the pin
   and re-fetch. **WSL install done 2026-10-08** (extracted archive
   byte-identical to the installed tree; compiler binary sha256
   `36dd6fb5...b3b36b`); the Linux sweep is green on this pin
   (`SESSION.md` digest + `probe-logs/linux-sweep-20261008T134143Z/`).
   **Provisioning caveat (C-PULSE-13, filed):** on a fresh Unix install,
   `xiom pkg install` writes `$HOME/xiom/packages` while the compiler
   resolves `<install-root>/packages` (`~/.local/share/xiom`), so
   `[dependencies]` resolution misses the store until the two are bridged
   (symlink or an explicit `XIOM_HOME`); `xiom doctor` shows
   `[--] No packages` as the tell.
2. **DNS:** owner adds the A/AAAA for `staging.pulse.xiom-lang.org` ->
   xiom VPS `5.189.139.216` (GoDaddy); ops verifies propagation. Parked.
3. **TLS/proxy:** the VPS is Hestia-managed, nginx-only; ops adapts
   `deploy/nginx/pulse.conf.example` into a Hestia web template
   (`/usr/local/hestia/data/templates/web/nginx/php-fpm/`, assigned via
   `v-change-web-domain-tpl` + `v-rebuild-web-domain`) and issues the cert
   with Hestia LE (`v-add-letsencrypt-domain`) -- not a second nginx.
   PULSE's local nginx rehearsal stays as-is.
4. **Service:** systemd unit, `0600` env file, secret from the host secret
   store, bound to `127.0.0.1:8080` (keep the loopback bind hardcoded);
   public surface stays 443-only. `X-Pulse-Quit` remains a test hook;
   SIGTERM is the production stop once M4 signal handling lands.
   **Blocker note (2026-10-08):** the stdlib currently exposes no
   signal-handler installation API (`xiom.os.signal` has name/code/raise
   only), so PULSE cannot install a SIGTERM drain yet; filed in the
   stdlib wishlist. Until then the supervisor kills directly (the soak
   fleet proves the store heals from hard kills).
5. **Monitoring:** `/health` on UptimeRobot (keyword monitor; give it an
   honesty/state keyword), `/metrics` restricted via nginx allow/deny to
   monitoring sources.
6. **Releases/CI (on greenlight):** dl is pull-based -- no upload
   credentials. CI creates a GitHub Release with assets + `SHA256SUMS`;
   the VPS `dl-deploy.sh` (hourly :17) verifies checksums, publishes
   `releases/<tag>/` + `latest.json`, prunes to 20 tags. Runners:
   GitHub-hosted `windows-latest`/`ubuntu-latest`; **org rule: actions must
   be pinned to full SHAs** (`sha_pinning_required=true`; ops has the
   canonical set). Tag convention `pulse-v<semver>`. The org secret
   `XIOM_RELEASE_TOKEN` exists (org default token is read-only); rulesets
   reapplied from `scripts/apply-github-rulesets.ps1` when public. Staging
   auto-deploy from `main`: default no (hourly pull-deploy cron is the
   standard if wanted later).
7. **PULSE to-dos before any public release (unchanged):** build-info /
   version stamp surfaced in `/api/version` and `pulse --version`; keep
   the `.ps1`/`.sh` twins; when greenlit, ops re-runs the `.sh` E2E set
   against the VPS deployment as the acceptance harness.
   **Update (2026-10-08):** `--version`/`--help` and the
   `/api/version` `commit`/`build` fields are live and verified on both
   platforms; values come from `PULSE_BUILD_COMMIT`/`PULSE_BUILD_DATE`
   (deploy env). True compile-time stamping needs a toolchain define flag
   (filed); ops can set the env vars in the systemd unit until then.
   **Also shipped locally (2026-10-08):** `scripts/release.{ps1,sh}`
   produce the exact `pulse-<ver>-<os>-<arch>.zip` + `.sha256` artifacts
   (contents staged per section B.3), and `scripts/backup.{ps1,sh}`
   snapshot store + audit with a sha256 manifest (restore runbook in
   `docs/DEPLOYMENT.md` section 9). The CI-at-greenlight flow above is
   unchanged; these let PULSE cut identical artifacts by hand today.
   **Also shipped (2026-10-08, showcase round):** general `/assets/*`
   serving + `PULSE_LANDING_PATH` (per-site showcase content) and
   `deploy/Dockerfile` (ubuntu:24.04, container E2E verified). `PULSE_BIND`
   defaults to `127.0.0.1` -- the hardcoded-loopback requirement for host
   deployments stands; only containers set `0.0.0.0` inside their own
   network. Planned use (post-greenlight): one process per subdomain
   (`pulse.`, `orbit.`, `xvector.`) behind the same Hestia nginx pattern,
   honestly labeled beta.

## E. Update (2026-10-08 wrap 3) -- owner decisions: live subdomain, phase plan, release sequence

1. **DNS:** the owner added **`pulse.xiom-lang.org`**; the **staging
   subdomain is not needed** for the showcase. `orbitdb.` and `xvector.`
   pages come later (their DNS records exist); same template, one process
   per subdomain when deployed.
2. **Phase 1 (now -- nothing deploys):** marketing pages are built by the
   **website lane** (`docs/WEBSITE-RELAY-PULSE.md` carries the brief +
   paste prompt); the **PULSE lane** owns the product UI
   (`PULSE_LANDING_PATH`/`PULSE_ASSETS_DIR`) and reviews every technical
   claim. Ops: no action yet.
3. **Phase 2 (owner greenlight) -- release sequence:** GitHub Actions
   release workflow -> repo goes **public** -> branch rulesets protect
   `main` (mirror the xiom/stdlib repos; actions pinned to full SHAs per
   the org rule) -> CI cuts `pulse-v<semver>` with artifacts +
   `SHA256SUMS` -> dl publishes `releases/<tag>/` + `latest.json`
   (existing pull-deploy flow). Tag/asset conventions per section B.
   The DCO check workflow (`.github/workflows/dco.yml`) is already in
   the tree; the release workflow is the new piece.
4. **Ops deploy after 3:** the `pulse.` subdomain per sections A/D (TLS
   via the Hestia pattern, systemd unit, loopback bind, monitoring); the
   website lane wires live status/version + download links afterwards
   (CORS origin = the site origin).
5. **Cover image:** the owner drops it into the PULSE repo at
   `resources/img/` (e.g. `pulse-cover.png`); PULSE wires it into the
   product landing and passes a copy to the website lane.
6. **Pin/evidence:** unchanged from D -- v0.64.1 on both platforms, Linux
   sweep green, and the one known-red package gate is closed
   (`xiom.http` 0.1.2 republish verified on Windows and Linux).
7. **Release hygiene (wrap 4):** `xiom.toml` no longer carries
   machine-specific `source-roots` paths (dependency resolution via
   `[dependencies]` is verified on both platforms -- C-PULSE-02 closed),
   and the HTTP surface gained chunked request decoding (smoke 76/76 on
   both platforms). A clean CI checkout builds with `xiom pkg install`
   for the ten deps plus the D.1 bridge caveat on Unix layouts.
8. **Demo gating (C-PULSE-14, corrected wrap 6):** the request path
   retains ~32 KB/req (Windows) / ~48 KB/req (Linux) RSS linearly -- a
   soak-sampler bug had hidden it on Windows (fixed). Before any
   unattended demo (either OS), wait for the runtime fix (m235 candidate)
   or deploy with `MemoryMax=` + `Restart=always` in the systemd unit
   plus an RSS alert in monitoring.
9. **CI/release implementation (wrap 7, committed):**
   `.github/workflows/ci.yml` (PR tier: build + suites x2 + the 78-check
   smoke on ubuntu and windows), `release.yml` (tag `pulse-v*` -> guard
   [tag == `src/pulse.xi` version, ancestor of main] -> fleet [suites x2,
   smoke, rate, crash, 60s kv store soak on Linux; suites + smoke on
   Windows] -> `pulse-<ver>-<os>-<arch>.zip` + `.sha256` + combined
   `SHA256SUMS` -> GitHub Release), `heavy.yml` (weekly 30m HTTP + 10m kv
   soaks + RSS probe), and `.github/actions/setup-xiom` (pinned
   SHA256-verified toolchain v0.64.1, stdlib checkout at `STDLIB_VERSION`
   = 4dd8844..., the C-PULSE-13 bridge, ten pinned deps). Rulesets mirror
   the xiom repo: `protect-main` (PR-only, linear history, required
   checks `ubuntu-latest` + `windows-latest` + `DCO`) and
   `protect-release-tags` (`pulse-v*`, no delete/force). dl publish: ops
   pull-deploy from the GitHub Release assets.
10. **First release cut (2026-10-09):** dry-run dispatch caught a
   mis-transcribed Windows toolchain SHA (Linux leg was green); fixed and
   re-verified, then `pulse-v0.1.0` was tagged at `cc3e741` and the
   release workflow published the GitHub Release with
   `pulse-0.1.0-linux-x64.zip`, `pulse-0.1.0-windows-x64.zip`, per-asset
   `.sha256` and the combined `SHA256SUMS` (build provenance attested).
   Ops mirrors to `dl.xiom-lang.org/pulse/releases/pulse-v0.1.0/` +
   `pulse/latest.json` (slug `pulse`). Rulesets verified live:
   `protect-main` (DCO + `ubuntu-latest` + `windows-latest`) and
   `protect-release-tags` (`pulse-v*`); all workflow `uses:` are
   SHA-pinned; the release job uses the repo token (no PAT).
11. **C-PULSE-16 (ops finding, wrap 8):** `PULSE_BIND` is **not
   enforced** in 0.1.x -- the app binds the wildcard (stdlib
   `socket_bind` is wildcard-only; address-aware bind is filed with the
   compiler/stdlib lane). Keep the host firewall + proxy-only exposure,
   as verified on the demo. PULSE will enforce loopback and add a
   LISTEN-address smoke check once the primitive lands; per the owner,
   no re-cut of 0.1.0 -- the fix ships with the next release (macOS
   x64/arm64 legs are prepared but gated behind the `RELEASE_BUILD_MACOS`
   variable: the 2026-10-09 dry run hit upstream darwin blockers -- the
   runtime C `_SC_AVPHYS_PAGES`, arm64 x86 inline asm, and a codegen
   intrinsic issue; all filed, enable the variable when they clear).
