---
title: Quick start
description: Run PULSE locally and make the first requests.
---

# Quick start

Run the binary with defaults (loopback only):

```bash
./pulse_app
# pulse: listening on 127.0.0.1:8080
```

Or check the effective configuration without binding:

```bash
./pulse_app --check-config
```

Invalid values do not crash the server; they fall back to the default
and are reported as warnings at startup and in `--check-config`.

## First requests

```bash
curl -s http://127.0.0.1:8080/health
# {"status":"ok"}

curl -s http://127.0.0.1:8080/api/version
# {"name":"xiom-pulse","version":"0.1.0",...}

curl -s -X POST http://127.0.0.1:8080/api/echo \
  -H 'Content-Type: application/json' --data '{"hello":"pulse"}'
# {"echo":{"hello":"pulse"}}

curl -s -X POST http://127.0.0.1:8080/api/events \
  -H 'Content-Type: application/json' --data '{"kind":"note","msg":"first"}'
curl -s http://127.0.0.1:8080/api/events/count
# {"count":1}
curl -s 'http://127.0.0.1:8080/api/events?limit=1'
```

The store defaults to `pulse-events.jsonl` in the working directory; the
audit log defaults to `pulse-audit.log`. Point both at a data directory
for a real deployment (see [Configuration](./configuration.md)).

## Stop

`X-Pulse-Quit: 1` on `/health` is the test-only graceful shutdown hook.
Production supervision should stop the process with the supervisor
(no SIGTERM drain yet -- see [Security and beta limits](./security.md)):

```bash
curl -s -o /dev/null -H 'X-Pulse-Quit: 1' http://127.0.0.1:8080/health
```
