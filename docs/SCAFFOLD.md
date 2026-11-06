<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Start a new PULSE app

**Status 2026-11-06:** the one-command Beacon scaffold is shipped and
smoke-tested (`scripts/scaffold_smoke.py`). It is an API starting point, not
a CMS; the site scaffold is `examples/site` (`docs/SITE-SERVER.md`).

## Quickstart

```sh
python scripts/new_app.py my-app
cd my-app
xiom pkg install xiom.pulse@0.3.2 xiom.http@0.1.11
```

Then, from the PULSE repo root:

```sh
bash scripts/build.sh path/to/my-app/src/main.xi --name my-app
PULSE_PORT=8080 ./out/my-app
curl -s http://127.0.0.1:8080/health
```

```powershell
.\scripts\build.ps1 path\to\my-app\src\main.xi -Name my-app
$env:PULSE_PORT = "8080"
.\out\my-app.exe
```

## What you get

| File | Purpose |
|---|---|
| `src/main.xi` | Beacon app: `GET /health`, `GET /api/hello`, `POST /api/echo`, `GET /`, JSON 404 |
| `xiom.toml` | project name/version, `src` root, pinned `xiom.pulse`/`xiom.http` |
| `Caddyfile` | TLS/compression edge with a `/health` probe |
| `README.md` | build/run/deploy notes for this app |

The scaffold is deliberately small: replace the handlers in `src/main.xi`
with your routes, keep `/health` stable for the edge, and add the registry
packages you need (`xiom.session`, `xiom.jwt`, `xiom.static`, ...).

## Production shape

- Terminate TLS at Caddy/nginx; the `Caddyfile` is a working starting point.
  Replace `example.com` and keep the health probe.
- Run under a supervisor (systemd/launchd/Windows service). Multi-worker,
  drain and zero-downtime reload are designed in `docs/DESIGN-WORKERS.md`
  and are **not** part of the scaffold yet.
- The memory limitation is real: bounded/short-run deployments only until
  the 1.0 24 h/1M gate passes (`docs/STATUS-FOR-WEBSITE.md`).
- The scaffold uses Beacon. For sessions, the event store, OpenAPI, metrics,
  static/site mode and the game control plane, use the Station product
  (`src/server.xi`) or add the corresponding registry packages.
- Logs: set `PULSE_LOG=0` only when you have edge/access logs; PULSE is
  plaintext on loopback behind the proxy.

## Smoke

```sh
python scripts/scaffold_smoke.py
```

The smoke creates a temp app from the template, builds it with the pinned
toolchain, starts it on `127.0.0.1:18099`, checks `/health`, `/api/hello`,
`/`, the POST echo and the JSON 404, then cleans up. Exit 0 = GREEN.

## Method

A top-tier framework is judged by its **feature matrix and tests**, not LOC.
The scaffold is one feature row; every claim in the docs should point to a
test, a smoke or a CI step (see `docs/FEATURE-TESTS.md`).
