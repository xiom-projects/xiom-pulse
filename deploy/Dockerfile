# ============================================================================
# XIOM PULSE runtime image (benchmark harness / staging rehearsal / showcase).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Build from the repo root with a Linux binary already present:
#   scripts/build.sh src/server.xi --name pulse_app        # WSL/Linux
#   docker build -f deploy/Dockerfile -t xiom-pulse:local .
#   docker run --rm -p 8080:8080 xiom-pulse:local
#
# The binary must match the base image's glibc (built on Ubuntu 24.04 /
# WSL 24.04 -> use ubuntu:24.04 as the base; bookworm images need a
# build against an older glibc). Per-site content is mounted or overridden
# via PULSE_ASSETS_DIR / PULSE_LANDING_PATH.
# ============================================================================
FROM ubuntu:24.04

RUN mkdir -p /data /app
WORKDIR /app
COPY out/pulse_app /app/pulse_app
COPY resources /app/resources

ENV PULSE_PORT=8080 \
    PULSE_BIND=0.0.0.0 \
    PULSE_STATIC_DIR=resources/img \
    PULSE_ASSETS_DIR=resources/public \
    PULSE_STORE_PATH=/data/pulse-events.jsonl \
    PULSE_KV_DIR=/data/pulse-kv \
    PULSE_AUDIT_PATH=/data/pulse-audit.log

EXPOSE 8080
ENTRYPOINT ["/app/pulse_app"]
