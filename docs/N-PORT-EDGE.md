<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# N-ports edge template (WP4 phase-1 slice)

The portable multi-worker shape: one PULSE process per port, and the edge
load-balances across the upstream pool. This is the Windows/macOS baseline
(SO_REUSEPORT is Linux-only; the app falls back to N ports when it is
requested but unavailable).

**Status:** phase-1 *slice* only. The supervisor, control-port drain, and the
1/2-worker throughput curve are still pending. Run the workers under your
service manager for now (systemd `pulse@.service`, NSSM, or a process
supervisor), e.g.:

```bash
PULSE_PORT=18201 PULSE_WORKER_ID=0 PULSE_REUSEPORT=0 PULSE_STORE_PATH=/var/lib/pulse/w0.jsonl ./out/pulse_app
PULSE_PORT=18202 PULSE_WORKER_ID=1 PULSE_REUSEPORT=0 PULSE_STORE_PATH=/var/lib/pulse/w1.jsonl ./out/pulse_app
```

## Caddy

```caddyfile
pulse.example.com {
    encode zstd gzip
    reverse_proxy 127.0.0.1:18201 127.0.0.1:18202 {
        lb_policy round_robin
        health_uri /health
        health_interval 10s
        health_timeout 2s
        fail_duration 15s
        transport http {
            dial_timeout 2s
            read_timeout 10s
            write_timeout 10s
        }
    }
}
```

## nginx

```nginx
upstream pulse_pool {
    server 127.0.0.1:18201 max_fails=3 fail_timeout=15s;
    server 127.0.0.1:18202 max_fails=3 fail_timeout=15s;
    keepalive 32;
}

server {
    listen 443 ssl;
    server_name pulse.example.com;
    # ssl_certificate / ssl_certificate_key as in DEPLOYMENT.md

    location / {
        proxy_pass http://pulse_pool;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_read_timeout 10s;
        proxy_send_timeout 10s;
    }

    location = /health {
        proxy_pass http://pulse_pool;
        access_log off;
    }
}
```

## Caveats

- `/health`, `/api/version`, `/api/echo`, static/site, and calculations are
  stateless and safe on any worker.
- Sessions and `/api/me` are **in-memory per worker**: a plain round-robin
  pool breaks login/me/logout. Configure sticky sessions (hash the `sid`
  cookie) or keep stateful routes on one worker until the shared store
  lands (`docs/DESIGN-WORKERS.md` section 6).
- `/metrics` is per process: scrape each worker port and label by worker.
- Do not expose the future control port through the edge; it binds loopback
  only.
