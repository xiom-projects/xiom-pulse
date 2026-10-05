# Missing struct field silently compiles -- compiler finding (v0.64.0, OPEN)

**Filed by:** PULSE lane, 2026-10-05, during the app-icon work.

## Summary

A struct literal that omits a declared field compiles **without any
diagnostic**; the omitted field reads uninitialized (garbage). In PULSE's
server the omitted `body_bytes: Vec[UInt8]` produced garbage `.len()` and
a `0xC0000005` access violation on real requests. Expected: `T001 missing
field 'b'` at the literal.

## Minimal repro

`probe.xi` (same file at `tests/probes/probe_missing_field.xi`):

```xiom
pub type Pair = { a: Int; b: Vec[UInt8]; }
fn main() -> Int {
  let p = Pair{ a: 1; };
  io.println("missing-field a=" + p.a.to_str());
  io.println("missing-field b.len=" + p.b.len().to_str());
  return 0;
}
```

v0.64.0 actual output:

```
missing-field a=1
missing-field b.len=2296606801712
  exit code: 0
```

(`b.len()` is uninitialized garbage; no warning/error at compile time.)

## App context

PULSE `src/server.xi` `HandlerOut` gained a `body_bytes` field for binary
responses; two construction sites (session login/logout) were missed. The
build reported success; `POST /api/session/login` crashed the server with
`server_exit=-1073741819` (0xC0000005). After initializing the field the
same requests are green (smoke 44/44).

## Suggested fix

Reject incomplete struct literals at type-check time (`missing field
'body_bytes'`), or at minimum emit a warning when a field initializer is
absent. This is the struct-literal equivalent of the "initialize every
local" discipline the ecosystem already documents.

## Status

OPEN on v0.64.0. Not previously filed (grep of packages
`docs/COMPILER-FINDINGS.md` shows no missing-field row).
