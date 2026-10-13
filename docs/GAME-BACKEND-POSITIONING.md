<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Positioning: PULSE as a game backend / control plane (2026-10-13)

Owner question: can PULSE support multiplayer networking for XIOM Engine
games? This note fixes the intended split so both lanes build the right
half. Short version: **PULSE is the game's HTTP/WS backend and control
plane; XIOM Engine owns the realtime tick traffic.** That is the same
split the industry uses (Nakama, PlayFab, GameLift control plane,
Steamworks services).

## 1. The two planes

| Concern | Owner | Why |
|---|---|---|
| Tick simulation, authoritative netcode, UDP/QUIC/WebTransport transport, delta snapshots, prediction/rollback, RPCs | **XIOM Engine** | needs per-packet control, unreliable/unordered transport, tight loops -- an HTTP framework is the wrong tool |
| Accounts, sessions, JWT, profiles, inventory/progression, leaderboards, matchmaking queues + lobby metadata, config/flags, telemetry ingest, purchases/webhooks, admin/ops, metrics/audit | **PULSE** | request/response + push semantics, identity, rate limits, idempotency, storage -- the framework's existing core |
| Dedicated-server control plane: register/heartbeat, allocate, drain, capacity | **PULSE** | plain HTTP + jobs; keeps game servers disposable and addressable |

PULSE never sits in the tick path. A dedicated game server talks to
PULSE on the control plane (register, heartbeat, match result report);
clients talk to PULSE for everything around the match and to the game
server for the match itself.

## 2. What PULSE already gives a game backend

Not aspirational -- shipped today: sessions + JWT HS256, CSRF/CORS,
global rate limiting, **idempotency keys** (purchase receipts, match
reports, dup webhooks -- a game-backend must), event store + counts,
audit trail, structured access log, metrics, OpenAPI contract (client
SDKs can be generated from it), error envelopes, validation, security
headers, backups, single-binary cross-platform deploys. That checklist
is 80% of what "backend-as-a-service for games" products sell.

## 3. What PULSE needs for the game use-case (priority signal)

These were already filed in the production relay; games make them
near-term rather than "top league nice-to-have":

1. **WebSockets** (wave-2 ask): lobby/social/notifications, turn-based
   play, low-rate realtime (1-10 Hz). The single biggest enabler. The
   keep-alive + deadline implementation (already unblocked) is its
   prerequisite.
2. **SSE** (wave-2 ask): one-way push (rank updates, queue status,
   notifications) with zero WS complexity.
3. **Jobs/queue layer** (designed, 0.4): matchmaking pools, retries for
   webhook/report delivery, rotation/pruning -- bullmq-style semantics
   already designed.
4. **Multi-worker + sticky routing** (SO_REUSEPORT ask + ops template):
   N PULSE workers behind nginx; lobby affinity via upstream hashing or
   shared lobby state in the store seam.
5. **Per-route rate policy** (internal backlog): telemetry ingest and
   auth endpoints need different limits than the global bucket.
6. Later, if wanted: per-IP connection caps and a `/api/game/*` route
   convention for control-plane endpoints (pure PULSE work).

## 4. What PULSE will NOT do (and that is the point)

UDP sockets, tick loops, snapshot interpolation, lag compensation, NAT
traversal/relays, voice. Those live in the engine's networking layer.
Keeping PULSE HTTP/WS-only keeps it honest: one process model, one
security story, one release train. If a game needs a relay service,
that is a separate engine-side binary, not a framework feature.

## 5. Synergies worth keeping on the radar

- **Shared identity**: game servers validating the same JWT PULSE
  issues means one auth story across match and meta.
- **Poll/select (wave-2 ask)**: enables a *later* option where a game
  server embeds a non-blocking PULSE control endpoint on its own loop
  (no second process per match). Not needed for v1; the ask is
  independent of this.
- **Engine's production relay overlaps PULSE's**: the engine lane may
  want an in-engine HTTP surface for local admin/telemetry. If so,
  we should reuse PULSE modules rather than build a second HTTP stack
  inside the engine.
