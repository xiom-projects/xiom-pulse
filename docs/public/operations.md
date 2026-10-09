---
title: Operations
description: Proxy, systemd, backups, and monitoring for a PULSE deployment.
---

# Operations

The supported production shape is a TLS-terminating proxy (nginx) in
front of PULSE on loopback. PULSE itself never binds a public address
by design.

## systemd (Linux)

```ini
[Unit]
Description=XIOM PULSE
After=network-online.target

[Service]
WorkingDirectory=/opt/pulse
EnvironmentFile=/etc/pulse.env
ExecStart=/opt/pulse/pulse_app
Restart=always
NoNewPrivileges=true
# Until the memory-growth issue is fixed (see Security and beta limits):
MemoryMax=512M

[Install]
WantedBy=multi-user.target
```

`/etc/pulse.env` carries `PULSE_PORT`, `PULSE_BIND=127.0.0.1`,
`PULSE_STORE_PATH`, `PULSE_AUDIT_PATH`, `PULSE_JWT_SECRET` (from your
secret store), `PULSE_LANDING_PATH` / `PULSE_ASSETS_DIR` when serving a
showcase, and `PULSE_BUILD_COMMIT` / `PULSE_BUILD_DATE` for provenance.
There is no graceful SIGTERM drain yet: restarts drop in-flight requests
briefly; `Restart=always` covers it.

## nginx

```nginx
server {
    listen 443 ssl;
    server_name pulse.example.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    location /metrics { deny all; }
}
```

Notes: enforce proxy-side client timeouts (PULSE has no receive
deadlines yet), restrict `/metrics` to your monitoring network, and keep
TLS/HSTS at the proxy.

## Backup and restore

- Snapshot: `scripts/backup.sh` (Linux) or `scripts/backup.ps1`
  (Windows) copies the store and audit log into a timestamped folder
  with a manifest of sizes + SHA256; pass `--kv-dir`/`-KvDir` (or set
  `PULSE_STORE_BACKEND=kv`) to snapshot the kv directory instead.
- Restore: stop the service, copy the snapshot back over the store path
  (or the kv directory), start, and verify with `/api/events/count`.
  The JSONL store tolerates a torn tail, so a slightly-live copy is safe.

## Monitoring

- Liveness: keyword check on `GET /health`.
- Version: poll `GET /api/version` (compare `version`/`commit` to the
  deployed release).
- Metrics: scrape `/metrics` from the monitoring network.
- Memory: alert on RSS growth; the current build must be restarted
  periodically until the memory-growth issue is fixed.
