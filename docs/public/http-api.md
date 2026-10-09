---
title: HTTP API
description: Endpoints, request limits, and response semantics.
---

# HTTP API

All responses are JSON unless noted. `GET /health` returns
`{"status":"ok"}`. Errors use a stable envelope:
`{"error":{"code":"...","message":"..."}}`.

## Public endpoints

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | liveness; keyword-friendly for monitors |
| GET | `/api/version` | `name`, `version` (+ `commit`/`build` when env-stamped) |
| POST | `/api/echo` | echoes the JSON body |
| GET | `/api/items/:id` | path-parameter demo route |
| GET | `/metrics` | Prometheus text (restrict at the proxy) |
| GET | `/openapi.json` | OpenAPI 3.1 contract (version substituted at serve time) |
| GET | `/favicon.ico` | from `PULSE_ICON_PATH` |
| GET | `/assets/*` | static files from `PULSE_ASSETS_DIR` (ETag, 304, Range) |
| GET | `/` | `PULSE_LANDING_PATH` HTML (read per request) |

## Sessions and tokens

| Method | Path | Notes |
|---|---|---|
| POST | `/api/session/login` | demo login; sets session + CSRF cookies |
| POST | `/api/session/logout` | requires the CSRF token |
| GET | `/api/me` | session profile; 401 without a session |
| POST | `/api/token` | issues an HS256 JWT |
| POST | `/api/token/verify` | verifies a JWT; 401 on signature failure |

## Events

| Method | Path | Notes |
|---|---|---|
| POST | `/api/events` | append an event (audited) |
| GET | `/api/events` | list; `?limit=1..100`, `?kind=` |
| GET | `/api/events/count` | `{"count":N}` |
| POST | `/api/events/compact` | rewrite without torn lines |

## Request limits and semantics

- Body cap: 1 MiB decoded; over-cap chunked bodies get `413`.
- Header block guard: 16 KiB read-loop guard plus a 100-header cap.
- `Transfer-Encoding: chunked` requests are decoded (chunk extensions
  ignored, trailers validated and skipped).
- `Transfer-Encoding` with `Content-Length` together is refused `400`
  (request-smuggling shape); any coding other than `chunked` is `501`.
- `Expect: 100-continue` is honored before the body is read.
- Unknown route `404`, wrong method `405`, bad JSON `400`.
- CORS is opt-in (`PULSE_CORS_ORIGIN`, comma-separated exact origins or
  `*`); preflight `OPTIONS` answers `204`.
- Mutating requests are audited; session flows are CSRF-protected.

Statuses: `200`, `204`, `400`, `401`, `403`, `404`, `405`, `413`, `500`,
`501`.

## CLI

`pulse_app openapi` prints the same contract document to stdout;
`pulse_app routes` prints the route table (`METHOD PATH` per line). Both
exit 0; `openapi` exits 1 when the document cannot be read.
