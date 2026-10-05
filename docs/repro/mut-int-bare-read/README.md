# `&mut Int` bare read yields the ADDRESS -- compiler finding (v0.63.1, OPEN)

**Filed by:** PULSE lane, 2026-10-05. **Pin:** v0.63.1
(`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`), stdlib `15cb889`,
`XIOM_RUNTIME_DIR=E:\xiom-lang\stdlib\runtime`.

## Summary

A `&mut Int` parameter used **bare in value position** (arithmetic RHS or
`return`) yields the **pointer address**, not the pointee. Explicit `*p`
dereference is correct in both read and write positions. No diagnostic.
The write-through half of the old v0.62.2 defect is fixed; this is the
remaining **read-side** half.

## Minimal repro

`probe.xi` (same file at `tests/probes/probe_mut_int_ref.xi`):

| Shape | v0.63.1 result |
|---|---|
| `fn bare_add(p: &mut Int) -> Int { p = p + 1; return p; }` | **BROKEN** -- `a=1056790543816 r=1056790543808` (addresses) |
| `fn deref_add(p: &mut Int) -> Int { *p = *p + 1; return *p; }` | correct (`b=11 r=11`) |
| `fn bare_read(p: &mut Int) -> Int { return p; }` | **BROKEN** -- returns `1056790543744` instead of `10` |
| `fn deref_read(p: &mut Int) -> Int { return *p; }` | correct (`10`) |

```powershell
. .\scripts\dev-env.ps1
.\scripts\run.ps1 docs\repro\mut-int-bare-read\probe.xi -Quiet
# v0.63.1: program_exit=5  (bits 0|2: bare_add + bare_read broken)
# correct compiler: program_exit=0
```

The printed addresses are Windows stack addresses of the caller's local
(e.g. `0x000000F60B1FFxxx`), proving the reference itself is used as the
value rather than being loaded through.

## App-context impact

`xiom.http` v0.1.0's request parser (`src/parser.xi`) keeps its cursor in a
`&mut Int` and uses the bare form:

```xiom
var method_str: Str = parse_until(input, pos_ref, 32);   // pos: Int param
pos_ref = pos_ref + xiom.string.str_len(method_str) + 1; // bare read => address
...
return Err(HttpParseError{ message: "Unexpected end of request line",
                           position: pos_ref });          // position = address
```

Observed through PULSE's consumer probe on valid input:
`pkg-http parse err: Unexpected end of request line pos=372324169712`.

## Workaround (PULSE)

- Always use explicit deref for `&mut Int` reads and writes:
  `*p = *p + 1; return *p;` (matches the ecosystem's existing
  `xiom.gbnf` pattern).
- For registry packages, avoid the affected path until the package is
  re-shipped (PULSE's own parser uses value locals, not `&mut Int`).

## Status

OPEN on v0.63.1. Distinct from the resolved v0.62.2/v0.62.3 write-drop
matrix (`docs/repro/v0622-regressions`) -- that covered writes; this is the
read side. Not previously filed.
