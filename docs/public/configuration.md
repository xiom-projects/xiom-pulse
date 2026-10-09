---
title: Configuration
description: Environment variables and the JSON config file.
---

# Configuration

PULSE reads configuration from environment variables, optionally
overlaid by a JSON file (`PULSE_CONFIG`); environment variables win. Run
`pulse_app --check-config` to dump the effective configuration. Invalid
values fall back to the default and produce a warning (startup and
`--check-config`).

| Variable | Default | Meaning |
|---|---|---|
| `PULSE_PORT` | `8080` | listen port |
| `PULSE_BIND` | `127.0.0.1` | listen address (loopback by design) |
| `PULSE_LOG` | `1` | `0` disables access-log lines |
| `PULSE_STORE_BACKEND` | `jsonl` | event store backend: `jsonl` or `kv` |
| `PULSE_STORE_PATH` | `pulse-events.jsonl` | JSONL event store |
| `PULSE_KV_DIR` | `pulse-kv` | kv segment directory (`kv` backend) |
| `PULSE_KV_PREFIX` | `evt-` | kv sequence-key prefix |
| `PULSE_AUDIT_PATH` | `pulse-audit.log` | audit trail |
| `PULSE_AUDIT_MAX_BYTES` | `5000000` | audit rotation threshold (`0` = off) |
| `PULSE_CONFIG` | (unset) | JSON config file (env wins) |
| `PULSE_ICON_PATH` | `resources/img/pulse-ico.ico` | `/favicon.ico` source |
| `PULSE_ASSETS_DIR` | `resources/public` | `/assets/*` showcase root |
| `PULSE_LANDING_PATH` | (unset) | HTML file served at `/` (read per request) |
| `PULSE_JWT_SECRET` | dev default | **set in production** (HS256) |
| `PULSE_SESSION_TTL` | `3600` | session seconds |
| `PULSE_RATE_LIMIT` | `0` | global req/s cap; `0` = off |
| `PULSE_RATE_BURST` | = limit | token-bucket capacity |
| `PULSE_CSRF` | `1` | `0` disables CSRF checks |
| `PULSE_CORS_ORIGIN` | (unset) | CORS allowlist: comma-separated origins, or `*` |

`PULSE_LANDING_PATH` is re-read on every request to `/`, so content
pipelines can update the landing page without restarting the server.

## JSON config file

Any of the documented keys can be set in the JSON file (`port`,
`bind`, `log`, `store_backend`, `store_path`, `kv_dir`, `kv_prefix`,
`audit_path`, `audit_max_bytes`, `config`, `icon_path`, `assets_dir`,
`landing_path`, `jwt_secret`, `session_ttl`, `rate_limit`,
`rate_burst`, `csrf`, `cors_origin`). Environment variables override the
file.

## Store backends

- `jsonl` (default): append-only file, crash-safe (a torn trailing line
  heals on the next append). Backup/restore by copying the file.
- `kv`: embedded segment store under `PULSE_KV_DIR` (`evt-seg-*.kv`),
  sequence-keyed, with native compaction. Restore by copying the
  directory back with the service stopped; verify with
  `/api/events/count`.

`scripts/backup.sh` / `scripts/backup.ps1` snapshot the store and the
audit log (kv-aware with `--kv-dir` / `-KvDir`; the kv dir is picked up
automatically when `PULSE_STORE_BACKEND=kv`).

## Build provenance

`PULSE_BUILD_COMMIT` and `PULSE_BUILD_DATE` are optional and surface in
`/api/version`; set them from the deployment pipeline so the running
process reports exactly which release it is.
