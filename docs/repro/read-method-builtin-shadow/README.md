# read-method builtin shadowing -- compiler finding (v0.63.1, OPEN)

**Filed by:** PULSE lane, 2026-10-05. **Pin:** v0.63.1
(`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`), stdlib `15cb889`,
`XIOM_RUNTIME_DIR=E:\xiom-lang\stdlib\runtime`.

## Summary

A method named `read` **called with exactly one argument** is hijacked by a
codegen builtin meant for raw-pointer `ptr.read()` dereference. The real
method call is never emitted; there is **no diagnostic**; the call site's
value is replaced by a load of the first argument (so `Result.is_ok` folds
to `false` / an `Int` result folds to 0). Renaming the method fixes it.

This kills every one-arg `.read(...)` method on the pin, including the
stdlib networking read path: `xiom.net.TcpStream.read`
(`xiom/net/net.xi:105`, `stream.read(&mut buf)`) can never be called, so
`tcp_listen`/`tcp_connect` accept sockets but no caller can read from them.

## Minimal repro

`probe.xi` (same file at `tests/probes/probe_method_matrix.xi`) defines five
struct method shapes and returns a bitmask of broken ones:

| Variant | Shape | v0.63.1 |
|---|---|---|
| A | `SockA.read(self, buf: &mut Vec[UInt8]) -> Result[Int, Int]` (push) | **BROKEN** (bit 1) |
| B | `SockB.take2(self, buf: &mut Vec[UInt8]) -> Result[Int, Int]` (push) | ok |
| C | `SockC.read(self, buf: &mut Vec[UInt8]) -> Int` (push) | **BROKEN** (bit 4) |
| D | `SockD.take3(self) -> Result[Int, Int]` | ok |
| E | `SockE.read5(self, buf: &mut Vec[UInt8]) -> Result[Int, Int]` | ok |

The only variable that matters is the name `read` (A vs B, C vs E). Having
`use xiom.io;` in scope is NOT required (both variants broken with and
without it; `probe_read_collision_a/b.xi` in `tests/probes/`).

```powershell
. .\scripts\dev-env.ps1
.\scripts\run.ps1 docs\repro\read-method-builtin-shadow\probe.xi -Quiet
# expected on v0.63.1: program_exit=5   (A|C broken, B/D/E green)
```

## IR evidence

`xiom --emit-ir probe.xi` on v0.63.1:

- `define @SockA.read`, `@SockC.read` are emitted but **never called** from
  `main`.
- `call @SockB.take2`, `call @SockD.take3`, `call @SockE.read5` are emitted.
- Net effect at the call site: the `read` value is a constant default
  (`%tmp597 = icmp ne i64 0, 0` for `.is_ok` in the networking repro).

## Root-cause pointer (for the compiler lane)

`crates/xiom-codegen/src/call.rs:3177`:

```rust
// Builtin read(ptr): load value through raw pointer.
if fn_name == "read" && args.len() >= 1 {
    let (ptr_val, ptr_ty) = self.compile_expr(&args[0])?;
    if ptr_ty.ends_with('*') { ... return Ok((tmp, pointee)); }
}
```

The guard checks only `fn_name` + arg count, not the receiver type; the
`&mut Vec` argument lowers to `%struct.Vec*` (ends with `*`), so the branch
fires and the user/stdlib method is skipped. The sibling `write` builtin
(`call.rs:3141`) requires `args.len() >= 2`, which is why
`stream.write(&msg)` still works. Suggested gate: only take the builtin path
when the receiver is a raw pointer (`receiver_expr` present and `*T`), or
only when no user method resolves.

## App-context impact (PULSE)

- `xiom.net.TcpStream.read` unusable -> the whole stdlib networking read
  path is dead on v0.63.1.
- `xiom.os.Pipe.read` (same one-arg shape) is presumably affected too.
- PULSE workaround: read through `xiom.net.socket.socket_recv(fd, max)`
  (raw fd API, verified green) and never name methods `read`.

## Status

OPEN on v0.63.1 -- not previously filed (packages findings list has no
`read`-method shadowing row).
