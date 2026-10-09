# C-PULSE-17 repro: `xiom.io.list_dir` returns dangling names

**Filed 2026-10-10 by the PULSE lane (routed to compiler/stdlib since the
defect is in `xiom/io/io.xi`'s readdir loop).** Toolchain: v0.64.2,
Windows lane stdlib and Linux pinned stdlib `4dd8844`.

## Symptom

`io.list_dir(path)` returns a `Vec[Str]` whose entries compare equal
RIGHT AFTER the call (`ld.value[0] == "aa.txt"` passes), but whose bytes
are backed by memory that later allocations overwrite:

- concatenating/printing a listed name yields decimal pointer-looking
  garbage (`shown=[[2483528924144]]`);
- `io.remove_file(io.join_paths(dir, listed_name))` FAILS (the retained
  entry is already clobbered by the time `join_paths` allocates);
- a name captured and copied byte-wise immediately can still work, which
  makes failures intermittent in consumers.

Measured on v0.64.2 (Windows lane stdlib and Linux pinned `4dd8844`):
`names_ok=true print_ok=false rm_ok=false`. This bit PULSE's
multipart-upload test cleanup (leftover files across runs) before the
root cause was isolated.

PULSE-side workaround adopted the same day: no `list_dir` in production
or tests (the upload route already stores names it generates; tests
extract the generated names from the response JSON and use
`io.file_exists`/`remove_file` on those).

## Run

```
.\scripts\run.ps1 docs\repro\io-list-dir-dangling\probe.xi
```

Exit 0 = names equal `aa.txt`/`bb.txt` (fixed); exit 1 = corruption
reproduced. The probe writes `.tmp-lsd/` next to itself and removes the
files on the way out.
