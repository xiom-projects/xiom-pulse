<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Software bill of materials (CycloneDX)

**Status 2026-11-06:** generator in-tree and validated in CI. The
`linux-x64` release build generates the SBOM with exact registry hashes and
uploads it; the publish job attaches `xiom-pulse.cdx.json` to the GitHub
Release. No SBOM is committed (it would go stale immediately); the release
artifact is the published one.

## Generate

Offline (no registry, no package hashes):

```sh
python3 scripts/sbom.py --out sbom/xiom-pulse.cdx.json
```

With registry metadata (exact tarball SHA-256, signature, public key and the
declared transitive dependency ranges):

```sh
XIOM_COMPILER=/path/to/xiom python3 scripts/sbom.py \
  --out sbom/xiom-pulse.cdx.json --fetch-hashes
```

Windows: `python scripts\sbom.py --out sbom\xiom-pulse.cdx.json --fetch-hashes`
(with `XIOM_COMPILER` set). `--fetch-hashes` runs `xiom pkg info
<name>@<version> --json` for each direct dependency; it takes ~16 s for 13
packages. Offline generation is the default so a source archive can still
produce an SBOM.

The generator is Python 3.7+ and stdlib-only. It writes CycloneDX **1.5**
JSON with:

| Part | Contents |
|---|---|
| Product | `xiom-pulse` version from `src/version.xi`, commit, toolchain/stdlib properties, hashes mode |
| Dependencies | every `[dependencies]` row in `xiom.toml` (13 at 0.2.2), as `library` components with `pkg:generic` purls |
| Package metadata | with `--fetch-hashes`: exact registry `SHA-256`, `xiom:pkg:signature`, `xiom:pkg:public-key`, and `xiom:dep:<name>` version ranges |
| Dependency graph | with `--fetch-hashes`: CycloneDX `dependencies` (product -> 13 packages + stdlib; each package -> stdlib) |
| Toolchain | `xiom-compiler` per platform (linux-x64, linux-arm64, windows-x64, macos-x64, macos-arm64) with its SHA-256 pin |
| Stdlib | `xiom-stdlib` git ref from `STDLIB_VERSION` |

The serial number is `uuid5(version + commit)` and the timestamp defaults to
the commit date, so the same revision produces the same SBOM on any host.
`--commit` and `--timestamp` override them; `SOURCE_DATE_EPOCH` is honoured
for the timestamp.

## Pin source and drift check

`toolchain-pins.json` is the in-repo mirror of the compiler version and the
five archive SHA-256 values used by the CI/release workflows. When the
workflow environment is present (`XIOM_TOOLCHAIN_VERSION`,
`XIOM_LINUX_SHA256`, `XIOM_LINUX_ARM64_SHA256`, `XIOM_WINDOWS_SHA256`,
`XIOM_MACOS_X64_SHA256`, `XIOM_MACOS_ARM64_SHA256`), the generator compares
them and exits 2 on a mismatch. Keep the JSON and the workflow env in sync
when the pin moves.

## Release attachment

On a `pulse-v*` tag:

1. the `linux-x64` build job (compiler and deps installed) runs
   `scripts/sbom.py --fetch-hashes --commit "$GITHUB_SHA"` and uploads the
   `pulse-sbom` artifact;
2. the publish job downloads all artifacts, combines the zip checksums, and
   adds `xiom-pulse.cdx.json` to the `gh release create` file list next to
   the zips, per-file checksums and `SHA256SUMS`.

The SBOM therefore describes the same source revision as the tagged
binaries and carries the registry hashes of the exact package versions.

## Validate

```sh
python3 -m json.tool sbom/xiom-pulse.cdx.json >/dev/null
python3 - <<'PY'
import json
d = json.load(open("sbom/xiom-pulse.cdx.json", encoding="utf-8"))
assert d["bomFormat"] == "CycloneDX" and d["specVersion"] == "1.5"
assert d["metadata"]["component"]["name"] == "xiom-pulse"
assert len(d["components"]) >= 10
print("ok", len(d["components"]), "components")
PY
```

CI runs the same shape check on the Linux legs with `--fetch-hashes`.
`cyclonedx-cli validate` is not installed in CI (no extra global tool); the
generator's required fields and the CI assertions are the current gate.

## Evidence (0.2.2, 2026-11-06)

- 19 components: 13 direct package components, 5 compiler platform
  components, 1 stdlib component.
- With `--fetch-hashes`, `xiom.pulse@0.3.2` carries
  `SHA-256 6f2b6ff83402715a1588a23b0c8fed1de0c24ea56c95e51871aaeba41f11af6d`
  plus its registry signature and public key; the same shape applies to every
  direct dependency.
- Offline and registry modes were both generated locally; the pin drift
  check was verified (`v0.65.7` -> exit 2, `v0.65.6` -> exit 0).
- The dependency graph has 15 entries: product -> 14 targets (13 packages +
  stdlib), each package -> `xiom-stdlib@6fdde4ee`, stdlib -> none. Every
  direct package declares only `xiom.std` (verified 2026-11-06), so the
  closure is complete for the current manifest.

## Limitations (be honest)

- **The closure is resolved for the current manifest, not in general.** All
  13 direct packages declare only `xiom.std`, which is the pinned stdlib
  component, so the emitted graph is complete. `--fetch-hashes` fails if a
  package ever declares a non-stdlib dependency that is not in the manifest;
  a general lockfile/resolver is still the long-term solution for a larger
  graph.
- **Stdlib is a git ref, not a tarball hash.** The full commit is carried in
  `xiom:stdlib:commit`; the archive is SHA-256 pinned by the toolchain
  release itself.
- **Not signed.** The release has build provenance (GitHub attestations) and
  per-file checksums; the SBOM is attached, not separately signed.
- **No SPDX output.** CycloneDX 1.5 is the chosen format; SPDX can be added
  if an auditor requires it.
- **Offline mode omits package hashes.** A consumer must re-run
  `--fetch-hashes` (or use the release artifact) for the verifiable package
  digests.

## Follow-ups

1. Add a general lockfile/resolver for future non-stdlib transitive
   dependencies (the current manifest is fully resolved).
2. Attach the SBOM to the build provenance attestation if the action supports
   extra subjects.
3. Add a CI diff gate when a dependency version changes without an SBOM
   update in the release notes.
4. Consider a signed SBOM (Sigstore/cosign) after the release signing story
   is fixed.
