<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Repro: `xiom.kv` 0.1.0 `kv_get` returns a corrupted Str

**Filed:** 2026-10-07 by the PULSE consumer lane (WSL Linux build, v0.64.0).

## Symptom

After `kv_put(&mut store, "k", "abcdefghij")`, `kv_get(&store, "k")`
returns a decimal stack-address-like `Str` (e.g. `97116368003104`) instead of
`abcdefghij`, for every key and every value length (3, 5, 8, 10, 16 chars
observed).

`kv_get_bytes` is **correct** for the same key: it returns the stored bytes
(`abcdefghij`, len 10), and `Str::from_utf8` over those bytes renders the
expected text. So the stored record is intact; the `kv_get` Str
reconstruction is what misbehaves on v0.64.0.

## Run

```
scripts/run.sh docs/repro/kv-get-str-corruption/probe.xi
```

Expected (correct) print: `kv_get      =[abcdefghij]`.
Observed on v0.64.0: `kv_get      =[97116368003104]` (address changes per run).

## Consumer impact

- PULSE's JSONL-event store replacement (`xiom.kv` adoption) must read values
  through `kv_get_bytes` + `Str::from_utf8` until this is fixed; the probe
  `tests/probes/probe_pkg_kv.xi` carries that workaround.
- Any registry consumer that uses `kv_get` for Str values silently gets
  corrupted data (no error, no diagnostic).

## Classification (open)

PULSE cannot tell from the consumer side whether the root cause is (a) a
package-internal Str construction pattern that the compiler miscompiles on
v0.64.0 (C-PULSE-04/05 class) or (b) a genuine `xiom.kv` decoding defect.
Handover to the packages lane with the compiler lane copied: the two
platforms (Windows and WSL Linux v0.64.0) should be compared, and the
package's own conformance suite checked for a kv_get-after-kv_put case with
values >= 8 bytes.
