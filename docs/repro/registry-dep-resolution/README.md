# Registry package deps are not mapped to source roots -- toolchain gap (v0.63.1)

**Filed by:** PULSE lane, 2026-10-05. **Pin:** v0.63.1.

## Summary

`xiom pkg install xiom.http` works (checksum + signature verified) and
`package.xi`/`xiom.toml` `[dependencies]` entries are parsed by
`xiom-graph`, but the compiler driver never maps a dependency to a source
directory:

- `xiom-graph/src/manifest.rs:resolve_source_roots` returns only the
  project's own roots (`[project].root`, `source-roots`, `src/`).
- `xiom/src/lib.rs` adds: file parent, project `src/`, graph roots, stdlib
  dirs. Installed packages under `$XIOM_HOME/packages/...` are **never**
  added to the checker catalog.
- `[dependencies]` (TOML) / `dependencies:` (legacy package.xi) are parsed
  into `DependencySpec` but not used for catalog source roots.

Result: `use xiom.http.parser;` fails `error[T001] undefined variable`
even though the package is installed and declared.

## Evidence (app context)

1. `xiom pkg install xiom.http`:
   `Installed xiom.http v0.1.0 to
   C:\Users\lefte\AppData\Local\xiom\packages\xiom-http-0.1.0`.
2. With only `package.xi` (deps declared) -> `tests/probes/probe_pkg_http.xi`:
   13 T001s, all `undefined variable 'http_*'`.
3. Adding `source-roots = ["src",
   "C:/Users/lefte/AppData/Local/xiom/packages/xiom-http-0.1.0/xiom-http/src"]`
   to `xiom.toml` makes the catalog load the package modules (next failure
   is then an unrelated package defect, see the package lane row).

## Workaround (PULSE)

`xiom.toml` `[project].source-roots` lists each installed package's `src/`
directory. Documented in the file; revisit when deps map to roots.

## Suggested fix (compiler/package lanes)

Resolve `[dependencies]` (name + version) to
`$XIOM_HOME/packages/<name-with-dashes>-<version>/<inner>/src` (and the
package root, because some packages keep their barrel `http.xi` at the
package root) and feed those dirs into `expand_sources_with_graph` /
`add_external_dir`. `xiom pkg lock`'s resolved tree is a ready-made source
for this mapping.

## Status

OPEN on v0.63.1. The installed-package flow (install, checksum,
signature, version metadata) is otherwise green.
