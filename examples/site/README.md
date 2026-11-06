<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Dynamic multi-page site scaffold

A runnable, server-rendered site on the **PULSE Beacon** core
(`xiom.pulse`) plus **`xiom.template` 0.2.0**. It is the reference for the
dynamic site surface in `docs/SITE-SERVER.md`; the product Station server
keeps its `PULSE_SITE_DIR` static mode unchanged.

## What it shows

| Concern | Implementation |
|---|---|
| Shared layout | `templates/layout.html`, injected as raw `{{{content}}}` |
| Partials | `templates/partials/nav.html` and `footer.html`, rendered then injected raw |
| Loops / conditionals | `{{#features}}...{{/features}}`, `{{^error}}`, `{{#error}}` |
| Auto-escaping | every `{{value}}`; raw `{{{value}}}` only for trusted fragments |
| URL-encoded form | `POST /contact` with `application/x-www-form-urlencoded` |
| Validation | server-side required/length checks, re-rendered form on failure |
| Static assets | `/assets/*` from `public/` via `xiom.static` in the fallback hook |
| Custom 404 | rendered by the same layout, status 404 |
| Health probe | `GET /health` JSON |

## Build and run

From the repository root, with the lane toolchain:

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 examples\site\main.xi -Name site_example
$env:PULSE_PORT = "18095"
$env:PULSE_LOG = "0"
.\out\site_example.exe
```

Then open <http://127.0.0.1:18095/>. `SITE_ROOT` defaults to
`examples/site`; set it when the working directory is elsewhere.

On Unix:

```sh
bash scripts/build.sh examples/site/main.xi --name site_example
PULSE_PORT=18095 PULSE_LOG=0 ./out/site_example
```

## Smoke

```powershell
.\scripts\site_smoke.ps1 -Port 18095
```

```sh
bash scripts/site_smoke.sh --port 18095
```

The smoke builds the app, starts it, and checks the home/about/features
pages, the form (success and validation failure), an asset, the custom 404,
and the traversal guard.

## Operational notes

- The example reads and renders template files per request for clarity. A
  production site should read them once at startup and cache the `Str`
  (the package has no compile/streaming step).
- Templates are trusted code. User values must only enter through
  `{{value}}`; reserve `{{{value}}}` for layout slots, partials and other
  trusted fragments. `xiom.pulse.html.html_escape` is the shared helper for
  handlers that build HTML without a template.
- PULSE speaks plaintext HTTP/1.1 on loopback. Terminate TLS at Caddy or
  nginx and keep the `PULSE_SITE_DIR` / fallback split in mind when mixing
  static and dynamic pages.
- The scaffold is deliberately not a CMS: no admin UI, no database, no
  editor. See `docs/ROADMAP-TOP-TIER.md` section 12 for the phase boundary.
