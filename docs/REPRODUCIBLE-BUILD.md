<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Reproducible-build recipe

**Status 2026-11-06:** recipe and comparison procedure documented; a
**same-host payload gate** ships in CI (Linux x64 + Windows) and is green on
Windows v0.65.6 (`6a896cef…204184`, 5,195,776 bytes). **Cross-host and zip
bit-identity are not proven.** The release artifacts are SHA-256 pinned and
carry build provenance; this recipe is how a third party re-derives them. Do
not claim reproducible builds beyond the same-host payload gate.

## 1. Pins

Use exactly these inputs; the SBOM (`docs/SBOM.md`) records the same set.

| Input | Pin | Verification |
|---|---|---|
| Compiler | **v0.65.6** | `toolchain-pins.json` + the release workflow env |
| linux-x64 | `a8fc6668…4ce5d` | SHA-256 of the `.tar.gz` |
| linux-arm64 | `dca04f07…328d8` | SHA-256 |
| windows-x64 | `a52b8cf3…f886` | SHA-256 |
| macos-x64 | `c5f0eb0b…e47ab` | SHA-256 |
| macos-arm64 | `0fc5c6cd…2ca1c` | SHA-256 |
| Stdlib | `6fdde4ee89f0108025715031e60976ca7d1a5e82` (`STDLIB_VERSION`) | git ref |
| Packages | `xiom.toml` `[dependencies]` | 13 rows at 0.2.2 |

Install the toolchain from the official archive and verify the hash before
extracting. The `setup-xiom` composite action is the reference
implementation (download, SHA-256, extract, install deps).

## 2. Environment

- A clean checkout at the tag/commit (no local edits, no untracked files in
  the build path).
- `XIOM_COMPILER` pointing at the pinned compiler; `XIOM_STDLIB` at the
  pinned stdlib checkout; `XIOM_HOME` at a package home containing every
  `xiom.toml` dependency at the pinned version.
- The same OS/architecture as the artifact. Cross-host bit-identity is the
  goal; the known deltas are listed in section 5.
- No ambient `PULSE_*` variables: they are runtime configuration, not build
  inputs, but keep the shell clean.

`scripts/dev-env.ps1` / `dev-env.sh` set these for the lane-local home; a
reproducer should set them explicitly rather than rely on the lane home.

## 3. Build

Linux/macOS:

```sh
bash scripts/build.sh src/server.xi --name pulse_app --timeout-sec 300
bash scripts/release.sh --no-build --version 0.2.2
```

Windows:

```powershell
.\scripts\build.ps1 src\server.xi -Name pulse_app -TimeoutSec 300
.\scripts\release.ps1 -NoBuild -Version 0.2.2
```

`build.ps1`/`build.sh` pass the vendored SQLite amalgamation as a C source
when the entry imports the SQL/migrations modules; do not add extra
`--c-source` flags. The release scripts stage the binary, resources, docs
and licences and produce `dist/pulse-<ver>-<os>-<arch>.zip` +
`.zip.sha256`.

## 4. Compare

1. Compare the published `SHA256SUMS` / per-file `.sha256` with the rebuilt
   zip: `sha256sum dist/pulse-*.zip` (Linux/macOS) or
   `Get-FileHash -Algorithm SHA256` (Windows).
2. If the archive hash differs, compare the **payload** before calling it a
   source difference:

   ```sh
   unzip -p dist/pulse-0.2.2-linux-x64.zip pulse_app | sha256sum
   unzip -l dist/pulse-0.2.2-linux-x64.zip
   ```

   On Windows, extract to a temp dir and hash `pulse_app.exe` plus every
   resource file.
3. Compare the SBOM (`xiom-pulse.cdx.json`) component list; a version or pin
   change is the first thing to rule out.

## 5. Known deltas

| Delta | Why | What to compare |
|---|---|---|
| Zip byte differences | `Compress-Archive`/`shutil` store file mtimes and ordering; the stage is not timestamp-normalised | Payload hashes and file list; normalise mtimes before zipping once a gate exists |
| Windows PE metadata | v0.65.3 evidence: published `.text` identical to the RC; `.rdata`/`.rsrc` differ | Hash the `.text` section or the extracted binary code, not just the zip |
| macOS signing/quarantine | macOS may add code-signing/resource metadata | Extract and hash the Mach-O payload; document the signing step |
| Absolute source paths | Debug info/strings may embed the build path | Build from the same path (or a container) when comparing bit-for-bit |
| Compiler build timestamp | The compiler/runtime may embed one | Same compiler archive on both sides; report a compiler-side delta upstream |

The server itself does **not** embed a compile-time build date: `GET
/api/version` reads `PULSE_BUILD_COMMIT`/`PULSE_BUILD_DATE` from the
environment at runtime.

## 6. Gate (same-host, shipped)

`scripts/repro_check.ps1` / `.sh` build `src/server.xi` twice in the same
workspace (`repro_a`, `repro_b`), compare the SHA-256 of the two executables,
delete them, and fail on a mismatch. CI runs it on **Linux x64** and
**Windows**.

This gate proves same-host payload determinism. It does **not** prove
cross-host bit-identity or zip bit-identity. Still open:

1. run the double build on linux-arm64, macOS x64 and macOS arm64;
2. normalise zip mtimes/ordering, then compare the archive itself;
3. build in two clean hosts/containers and compare the payload;
4. publish the result in the release notes and the SBOM.

Until those land, a cross-host rebuild that differs is a **finding to
triage**, not automatically a regression. Report it with the payload
comparison and the delta class above.

## 7. Current evidence

- Release dry-run `41885910214` packaged all five platforms on v0.65.6.
- Per-file SHA-256 + `SHA256SUMS` + GitHub build provenance exist.
- Same-host double build on Windows v0.65.6: **identical** payload
  `sha256 6a896cef391a2b0db1836ef4f766b1a4c2b9310f05ef4272107c5de2b7204184`
  (5,195,776 bytes). The gate is in CI on Linux x64 + Windows.
- Cross-host / zip bit-identity is still a WP2 open item.
