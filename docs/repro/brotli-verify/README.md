<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Consumer-verify: xiom.brotli 0.1.0 (PULSE side)

Scope: the packages lane's delivery on the PULSE top-tier ask
(`REL-20261015-2202-pulse-3` item "real compression"; eco-v0.1.189,
sha256 `f37f3a39...`, announced at `REL-20261016-1515-packages`). This
unit consumes the INSTALLED registry artifact and proves the RFC 7932
surface PULSE will use for `Content-Encoding: br` response compression.

## Result

- **11/11 checks GREEN x2 on both platforms** on the pinned v0.64.5
  (stdlib pin `stdlib-092dfa0c`): Windows + WSL Ubuntu
  (`probe-logs/packages-verify/brotli-win.log` / `brotli-linux.log`);
  the install checksum matched the published sha256 on both stores.
- Covered: version pin 1.2.0; `Content-Encoding` helpers; `compress_bound`;
  one-shot round trip; quality sweep 0/5/11 byte-exact; streaming decode
  with full input consumption; streaming encode (FINISH) byte-exact round
  trip; corruption/truncation typed errors with upstream detail;
  empty-input boundary.
- Consumer note: with the dependency declared, the consumer build picks
  up the package's `port.args.json` automatically (the C bridge + the 35
  vendored translation units; `--opt-level`/`--timeout` are ignored at
  consumer build) -- passing them explicitly (as the runner does by
  expanding the installed `port.args.json`) is redundant but accepted.

## How to run

- Pinned env as in `docs/repro/template-verify/README.md`.
- Install once: `xiom pkg install xiom.brotli@0.1.0`.
- From this directory: `xiom --run probe.xi` (exit code = failures) --
  the local `xiom.toml` declares the dependency and the consumer build
  applies the dependency's `port.args.json`.
- Wrappers used for this session's evidence:
  `probe-logs/packages-verify/run-win-brotli.ps1` and
  `run-linux-brotli.sh` (the latter passes the expanded args explicitly).

## Evidence

- `probe-logs/packages-verify/brotli-win.log` / `brotli-linux.log`
  (11/11 + `exit code: 0`, two runs each).
- Bus: result filed to packages (ref `REL-20261016-1515-packages`).
