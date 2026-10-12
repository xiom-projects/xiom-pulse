<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# kv-mode server exits 0 at startup under v0.64.4 (PULSE toolchain-hold)

Finding: a PULSE binary **built with v0.64.4** exits immediately with
code 0 and no output when the kv store backend is enabled, so the server
never binds. The identical source tree built with v0.64.3 serves
normally. Pin-independent (reproduced with both `dd352f6` and `3df0843`).

## Repro

```
build: XIOM_COMPILER=<v0.64.4> XIOM_STDLIB=<pin> scripts\build.ps1 src\server.xi -Name pulse_app
run:   PULSE_STORE_BACKEND=kv out\pulse_app.exe    # exits 0, prints nothing, never listens
       (same binary, no env)                        # serves normally (jsonl default)
control: rebuild with v0.64.3 -> PULSE_STORE_BACKEND=kv serves 200 /health
```

## Matrix (2026-10-12, Windows; all with the same tree + store)

| toolchain | pin | backend env | result |
|---|---|---|---|
| v0.64.4 | dd352f6 | none (jsonl) | serves (smoke 119/119) |
| v0.64.4 | dd352f6 | `PULSE_STORE_BACKEND=kv` | **exit 0, silent** |
| v0.64.4 | 3df0843 | `PULSE_STORE_BACKEND=kv` | **exit 0, silent** (smoke-kv rc=1 at the sweep) |
| v0.64.3 | dd352f6 | `PULSE_STORE_BACKEND=kv` | serves 200 /health |
| v0.64.3 | 3df0843 | `PULSE_STORE_BACKEND=kv` | serves |
| v0.64.4 | any | `--version` / `routes` under the same env | print normally, exit 0 |

Additional isolations:

- The kv package API witness (`witness.xi` here: `kv_open` + `kv_put` +
  `kv_get` + `kv_count` + `kv_close`) is **green under both compilers**
  -- the standalone kv path is fine; the miscompile is in PULSE's own
  kv-mode startup control flow.
- `PULSE_STORE_BACKEND=kv` alone (no `PULSE_KV_DIR`) triggers it; an
  unrelated extra env var (`PULSE_KV_DIR` with the default backend) does
  not -- so it is the backend-branch code, not environment size.
- Full sweep on v0.64.4: FAILED=1, solely `smoke-kv`
  (`probe-logs/toolchain-0644/`, 24-smoke-kv.log); everything else green.

## Impact + status

v0.64.4 adoption is **ON HOLD** for PULSE (CI pins remain v0.64.3). The
permanent `&HandlerOut` helper re-land is deferred again with it (the
helper needs >= m261, but v0.64.4 reds the kv leg). Filed to the
compiler lane (see the relay item referenced in SESSION.md).

## Evidence

- This session's runs: `probe-logs/toolchain-0644/kv-repro/` (exit codes
  via cmd wrappers: `EXIT=0`), `probe-logs/toolchain-0644/24-smoke-kv.log`.
- Container witness: `witness.xi` (green both compilers).
