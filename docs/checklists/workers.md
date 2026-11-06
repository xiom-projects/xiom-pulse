<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# WP4 implementation checklist (supervisor / workers / drain)

Design: `docs/DESIGN-WORKERS.md`. **Status: design only; do not tag a release
claiming multi-worker until every phase-1 box is checked and the evidence is
attached.** The memory gate stays single-worker until phase 3.

## 0. Prerequisites (record the pin)

- [ ] Confirm on the pinned toolchain: `socket_set_reuseport(fd, on)`,
      `socket_poll_read(fds, ms)`, `posix_spawn`/`posix_spawnp`,
      `process_status`/`wait_status`, `proc_is_running`. Record the
      compiler/stdlib hashes in this file.
- [ ] Confirm the signal state: `os.on_signal` is a stub in v0.65.6; phase 1
      uses the loopback control port. Re-check on the next pin.
- [ ] Confirm the SQL/KV decision status; phase 1 must not depend on a
      shared store.

## 1. Config and bind

- [ ] Add `PULSE_WORKERS` (default 1), `PULSE_WORKER_CHILD`, `PULSE_WORKER_ID`,
      `PULSE_REUSEPORT`, `PULSE_CONTROL_PORT`, `PULSE_CONTROL_TOKEN`,
      `PULSE_DRAIN_TIMEOUT_MS` with validation tests (bad/zero values fall
      back with a warning, like the existing config keys).
- [ ] `PULSE_REUSEPORT=1` calls `socket_set_reuseport(fd, true)` **before**
      `socket_bind`; on Windows the expected Err falls back to N ports with a
      clear log line (no crash).
- [ ] N-ports mode: worker `i` binds `PULSE_PORT + i`; the supervisor passes
      the actual port to the child. Single-worker behavior is unchanged.
- [ ] Log `worker id`, `generation`, `port`, `reuseport` at startup.

## 2. Control port and drain

- [ ] Bind the control listener to `127.0.0.1:<PULSE_CONTROL_PORT>` only.
- [ ] Poll the public and control listeners with `socket_poll_read(&fds, 250)`
      so the accept loop can observe drain without a blocking accept.
- [ ] `POST /drain` (token from `PULSE_CONTROL_TOKEN`) sets `draining=true`,
      stops accepting, lets the in-flight request finish, sends
      `Connection: close`, closes idle keep-alive connections, and exits 0
      within `PULSE_DRAIN_TIMEOUT_MS`.
- [ ] `GET /health` on the control port returns 200 while accepting and 503
      while draining; `POST /quit` is the immediate drain.
- [ ] Tests: no public connection is accepted after drain starts; an
      in-flight request completes; an idle keep-alive connection is closed at
      the deadline; the process exits 0.
- [ ] Do not expose the control port through the edge; test a non-loopback
      request is impossible (bind check).

## 3. Supervisor

- [ ] `PULSE_WORKERS=N` (no `PULSE_WORKER_CHILD`) spawns N children with
      `env.args()[0]` and the child env (id, port/reuseport, control port,
      per-worker store path).
- [ ] Monitor `process_status`; restart an unexpected exit with backoff
      1/2/4/.../30 s; log the exit code and generation; cap restarts.
- [ ] Supervisor drain: ask every child to drain, wait for the deadline,
      kill survivors, exit 0. No orphan children.
- [ ] `PULSE_WORKERS=1` stays the current single-process path (no supervisor
      overhead) and passes the existing suite unchanged.
- [ ] Tests: spawn 2 children, kill one, verify restart; drain the supervisor
      and verify both children exit.

## 4. Edge and ops

- [ ] Caddy/nginx N-port upstream with health checks; add new ports before
      draining old ones; remove old upstreams after the drain.
- [ ] Ops unit template: N services with `PULSE_PORT`/worker id, control
      token, per-worker store paths; document restart/drain commands.
- [ ] Operator guide: which endpoints are multi-worker safe; the sticky
      session requirement; the per-worker event/upload behavior.

## 5. Smoke and curve

- [ ] 2-worker smoke (Linux x64 + Windows): `/health`, `/api/version`,
      a stateless POST, a static asset; drain; reload; zero failed new
      requests routed to healthy workers.
- [ ] Linux reuseport smoke: two workers on one port; close one listener and
      verify traffic continues; Windows returns the documented Err.
- [ ] 1/2-worker curve on `/serialize` behind the edge: record req/s, p50,
      p99, errors; acceptance 2 workers >= 1.6x, p99 not worse.
- [ ] Attach the raw JSON to `benchmarks/bttger/results/` and summarize in the
      report; do not publish a multi-worker sustained-load claim.

## 6. Shared-state boundary

- [ ] Sticky-session edge config (hash `sid`) tested for
      `/api/session/login` -> `/api/me` -> `/api/session/logout`.
- [ ] Document that round-robin without stickiness breaks sessions; do not
      silently enable it.
- [ ] Per-worker rate budget: `global/N` or a documented N x; test.
- [ ] Per-worker `PULSE_STORE_PATH` for events/audit; document the per-worker
      events API and the merge path; uploads on a shared filesystem.
- [ ] Game state: not multi-worker until the game profile/shared store; pin
      by user/match or run one worker for the game routes.
- [ ] Metrics: scrape every worker; label by `worker`; do not sum uptime.

## 7. CI and docs

- [ ] Add the 2-worker smoke to CI on Linux x64 and Windows; run reuseport
      only on Linux; skip with the expected Err on Windows.
- [ ] Keep the single-worker suites untouched.
- [ ] Update `docs/DESIGN-WORKERS.md`, `docs/DEPLOYMENT.md`,
      `docs/STATUS-FOR-WEBSITE.md`, ROADMAP WP4 and PROGRESS with the
      evidence.
- [ ] Do not include WP4 in a release note until phase 1 passes; the 24 h/1M
      gate remains single-worker.

## Definition of done (phase 1)

- 2 workers behind the edge: >= 1.6x on `/serialize`, zero errors.
- Drain and reload: zero failed new requests, in-flight completes, exit 0.
- Windows N-port path passes; Linux reuseport path passes or is explicitly
  documented as deferred.
- Sticky-session config tested; shared-state limits documented.
- No release claims multi-worker until the evidence is attached.
