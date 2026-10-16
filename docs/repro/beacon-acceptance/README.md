<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Consumer acceptance: xiom.pulse 0.1.0 (Beacon) -- published artifact

Scope: the publish close `REL-20261016-1810-packages-3` -- `xiom.pulse`
0.1.0 LIVE in eco-v0.1.192 (sha256
`53fcc56e3901fd36efe18fee469f3ee6e3b913d4793836a37bdbb28506d1fe15`).
Stage 1 (this unit): the INSTALLED artifact on both platforms -- the
carved conformance suite x2 + the `minimal.xi` live end-to-end x2.
Stage 2 (the closing half, next Q unit): PULSE Station consumes the
published package and runs the full smoke/fleet -- the 134-check-set
mapping note is the acceptance checklist.

## Result (stage 1 -- GREEN)

- Installs: checksum verified on both stores -- Windows
  (`%LOCALAPPDATA%\xiom\packages\xiom-pulse-0.1.0`) and WSL
  (`~/xiom/packages/xiom-pulse-0.1.0`); the WSL install also reports the
  signature verified (fp 4f:3b:47:f3:ae:17:b1:3c; the tool notes the
  ephemeral publisher key).
- Carved conformance suite (125 checks -- the mapped 134-set): **125/125
  x2 on both platforms** (`win-suite-r{1,2}.log`, `linux-suite-r{1,2}.log`).
- `minimal.xi` (the three-line surface: register + serve) live x2 on both
  platforms: `GET /health` -> 200 `{"status":"ok"}`, and a request
  carrying `X-Pulse-Quit: 1` shuts the loop down cleanly
  (`win-minimal-r{1,2}.log`, `linux-minimal-r{1,2}.log`).

## How to run

- Pinned env as in `docs/repro/template-verify/README.md`; install:
  `xiom pkg install xiom.pulse@0.1.0`.
- Suite: from the installed package root,
  `xiom --run tests/test_conformance.xi` (exit code = failures).
- Minimal: `PULSE_PORT=<port> xiom --run src/minimal.xi`, then
  `curl :<port>/health`; stop with a request carrying `X-Pulse-Quit: 1`.
- Runners used for the evidence:
  `probe-logs/beacon-acceptance/{run-win-beacon.ps1,run-linux-beacon.sh,install-wsl.sh}`.

## Evidence

- `probe-logs/beacon-acceptance/`: suite + minimal logs and server
  outs (`.out` / `.err`) for both platforms.
- Bus: stage-1 result filed back (ref `REL-20261016-1810-packages-3`).
