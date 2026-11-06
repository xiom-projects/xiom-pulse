<!-- Copyright (c) 2026 The XIOM Authors. SPDX-License-Identifier: MIT OR Apache-2.0 -->
# __APP_NAME__

A minimal PULSE **Beacon** API app: `GET /health`, `GET /api/hello`,
`POST /api/echo`, `GET /`, and a JSON 404. It is the starting point, not a
framework: replace the handlers in `src/main.xi` with your routes.

## Build and run

Install the pinned deps once (the scaffold lists them in `xiom.toml`):

```sh
xiom pkg install xiom.pulse@0.3.2 xiom.http@0.1.11
```

Build with the PULSE repo scripts (or your own pinned compiler invocation):

```sh
# from the PULSE repo root; replace path/to/app with this directory
bash scripts/build.sh path/to/app/src/main.xi --name __APP_NAME__
PULSE_PORT=8080 ./out/__APP_NAME__
```

```powershell
# from the PULSE repo root; replace path\to\app with this directory
.\scripts\build.ps1 path\to\app\src\main.xi -Name __APP_NAME__
$env:PULSE_PORT = "8080"
.\out\__APP_NAME__.exe
```

Check it:

```sh
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/api/hello
curl -s -X POST --data 'hello' http://127.0.0.1:8080/api/echo
```

## Production shape

- Terminate TLS at Caddy/nginx; `Caddyfile` is a working edge template with
  a `/health` probe and compression. Replace `example.com`.
- Keep `/health` stable; the edge uses it for rotation.
- Run as a supervised service (systemd/launchd/Windows service). PULSE is a
  single process today; multi-worker/drain is designed in
  `docs/DESIGN-WORKERS.md` and is not part of this scaffold yet.
- Read the memory limitation before any sustained-load claim:
  `docs/STATUS-FOR-WEBSITE.md` (bounded/short-run until the 1.0 gate).
- `/metrics` and the full Station features are not included in the Beacon
  scaffold. Use the Station product (`src/server.xi`) for sessions, the event
  store, OpenAPI and the game profile.

## Smoke

From the PULSE repo root:

```sh
python scripts/scaffold_smoke.py
```

It creates a temp app from this template, builds it with the pinned
toolchain, starts it, checks `/health`, `/api/hello`, `/` and the echo, and
cleans up.
