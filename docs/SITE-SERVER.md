<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PULSE as a multi-page site server

**Status 2026-11-06:** static site mode is shipped in the Station product;
the dynamic site surface is a first slice (server-rendered scaffold, shared
layout/partial composition, urlencoded forms, HTML escaping). Compression,
dynamic caching and i18n are not implemented. This document is the operator
and developer reference for both modes.

## 1. Two modes, one server

| Mode | Tier | What it does | Status |
|---|---|---|---|
| **Static site** | Station (`pulse_app`) | Serves a pre-built directory tree via `PULSE_SITE_DIR` | shipped |
| **Dynamic site** | Beacon (`xiom.pulse`) + `xiom.template` | Renders pages per request, parses forms, serves assets via the fallback hook | first slice; `examples/site` |

Static mode is the right choice for a generated site (SSG) and needs no
dependencies beyond the product binary. Dynamic mode is for pages that need
per-request data or a form; it is an application built on the Beacon core,
not a second product server.

## 2. Static site mode (shipped)

Set `PULSE_SITE_DIR` to the site root. Unmatched `GET`/`HEAD` requests fall
through to the tree; registered API routes always win.

| Behavior | Result |
|---|---|
| `/` | `index.html` |
| `/about` | `about.html` (clean URL) |
| `/sub/` | `sub/index.html` |
| `/sub` | `301` to `/sub/`, query preserved |
| missing path | `404.html` served with status 404 |
| `assets/app.js`, `assets/x.wasm` | JS / WASM MIME types |
| repeat request | `ETag` / `304`, `Cache-Control` (max-age `PULSE_SITE_MAX_AGE`) |
| `../` or encoded traversal | rejected by the static engine |
| framing | one `Content-Length`, owned by the response builder |

The regression suite is `tests/test_app.xi` (`site index`, clean URL,
directory index, 301, assets, WASM MIME, custom 404, API precedence,
traversal, single `Content-Length`).

Configuration:

| Variable | Default | Meaning |
|---|---|---|
| `PULSE_SITE_DIR` | (unset) | site root; empty disables site mode |
| `PULSE_SITE_MAX_AGE` | (config default) | `Cache-Control: max-age` for site files |

## 3. Dynamic site mode (first slice)

### 3.1 The pieces

- **Templating:** `xiom.template` **0.2.0** (signed registry package,
  sha256 `bedd03a9...c80580`) provides placeholders, sections, loops,
  inverted sections, dotted paths and HTML auto-escaping. It has no
  partials or inheritance; compose them by rendering a fragment and
  injecting it raw into a layout slot.
- **Form parsing:** `xiom.pulse.urlenc` parses
  `application/x-www-form-urlencoded` bodies and exposes
  `form_is_urlencoded`, `parse_form`, `parse_pairs`, `url_decode` and
  `form_value`. It is the same decoder the router uses for query strings.
- **Escaping:** `xiom.pulse.html.html_escape` escapes `& < > " '` for
  handlers that build HTML without a template. Template interpolation uses
  the same mapping automatically.
- **Assets:** the Beacon `fallback` hook plus `xiom.static` serves the
  `public/` tree with ETag, Range and the traversal guard, and renders the
  custom 404 for misses.
- **Form body cap and framing:** owned by the HTTP layer; a handler only
  sees a decoded body that already passed the configured caps.

### 3.2 The scaffold

`examples/site/` is the reference implementation:

```
examples/site/
  main.xi                     routes, layout composition, form handler, fallback
  templates/layout.html       shared document (raw title/nav/footer/content slots)
  templates/partials/         nav + footer fragments
  templates/pages/            index, about, features, contact, thanks, 404
  public/                     style.css, app.js, favicon.svg
```

Routes: `GET /`, `/about`, `/features`, `/contact`, `/health` and
`POST /contact`. The contact form validates required and length limits,
re-renders with `400` on failure, re-renders with `415` for a non-form
content type, and renders a thank-you page on success. All reflected values
are auto-escaped; the smoke asserts the escaped bytes.

Build and run from the repository root:

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 examples\site\main.xi -Name site_example
$env:PULSE_PORT = "18095"
$env:SITE_ROOT = "examples/site"
.\out\site_example.exe
```

Smoke: `scripts/site_smoke.ps1` (Windows) or `scripts/site_smoke.sh`
(Unix). It covers the pages, form success/failure, wrong content type,
asset MIME, custom 404 and traversal.

### 3.3 Layout and partial composition

The package does not support `{{>partial}}`. The scaffold composes:

1. render each page with its data (auto-escaped),
2. render `partials/nav.html` and `partials/footer.html` with empty data,
3. render `layout.html` with `title`, `nav`, `footer` and `content` as
   **raw** slots (`{{{...}}}`).

Only the layout's raw slots are unescaped. Page data must always use
`{{value}}`; keep `{{{value}}}` for trusted fragments produced by the
server. This is the same trust boundary as any template engine's raw
output.

### 3.4 Escaping rules

| Context | How to emit it |
|---|---|
| HTML text / quoted attribute | `{{value}}` (auto-escaped) or `html_escape(value)` |
| Trusted server fragment | `{{{fragment}}}` in a template only |
| Template file | trusted code; never build it from user input |
| JSON | use the JSON builder, not HTML escaping |

`html_escape` is not a sanitiser: it does not strip tags or decode
entities. It prevents a value from changing the document structure; it
does not make untrusted HTML safe to embed.

### 3.5 State-changing forms

The example contact form is unauthenticated and has no side effect beyond
rendering a response. Authenticated forms must use the Station session +
CSRF surface (`PULSE_CSRF`) or an equivalent token; do not copy the example
into a logged-in mutation path without it.

## 4. Deployment shape

PULSE speaks plaintext HTTP/1.1 on loopback; TLS and HTTP/2 stay at the
edge. The existing `docs/DEPLOYMENT.md` templates apply unchanged. A
minimal Caddy front for a site:

```caddyfile
site.example.com {
    encode zstd gzip
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        -Server
    }
    reverse_proxy 127.0.0.1:8080 {
        health_uri /health
        health_interval 10s
    }
}
```

For a static site, run the product with `PULSE_SITE_DIR`. For the dynamic
scaffold, run the Beacon binary with `SITE_ROOT` (or build a site-specific
binary from `examples/site/main.xi`). Keep `/metrics` on the private
interface; see `docs/DEPLOYMENT.md` for the nginx equivalent.

## 5. What is deliberately missing

| Gap | Tracking |
|---|---|
| Response compression (gzip/brotli/zstd) | parity P-15; edge `encode` covers it today |
| Dynamic page caching / TTL / ETag for rendered pages | parity D-10 |
| Partials and template inheritance in the package | compose fragments (section 3.3) |
| Redirects, canonical URLs, robots/sitemap | site ergonomics, P2 |
| i18n | parity E-08 |
| Dev reload loop | parity O-10 |
| Template caching in the scaffold | read once at startup in production |
| A CMS/admin panel | explicitly out of scope (ROADMAP section 12) |

## 6. Evidence

- `tests/test_app.xi`: HTML escape mapping, content-type detection,
  urlencoded decoding (plus, percent, duplicates, empty body), first-value
  lookup; the existing static-site regressions.
- `scripts/site_smoke.ps1` / `.sh`: end-to-end pages, form, assets, 404,
  traversal.
- `docs/repro/template-verify/probe.xi`: the 0.2.0 consumer verification
  (blocks, loops, auto-escape) on the installed artifact.
- CI: `xiom.template@0.2.0` is installed by the setup action and the site
  smoke runs on every leg.
