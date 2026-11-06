<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Software bill of materials (CycloneDX)

**Status 2026-11-06:** generator in-tree and validated in CI; the release
job regenerates the SBOM from the tag commit and attaches it to the GitHub
Release. No SBOM is committed (it would go stale immediately); the release
artifact is the published one.

## Generate

```sh
python3 scripts/sbom.py --out sbom/xiom-pulse.cdx.json
```

Windows: `python scripts\sbom.py --out sbom\xiom-pulse.cdx.json`.

The generator is Python 3.7+ and stdlib-only. It writes CycloneDX **1.5**
JSON with:

| Part | Contents |
|---|---|
| Product | `xiom-pulse` version from `src/version.xi`, commit, toolchain/stdlib properties |
| Dependencies | every `[dependencies]` row in `xiom.toml` (13 at 0.2.2), as `library` components with `pkg:generic` purls |
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

On a `pulse-v*` tag, the release job checks out the tag, runs the generator
with `--commit "$GITHUB_SHA"`, and adds `xiom-pulse.cdx.json` to the
`gh release create` file list next to the zips, per-file checksums and
`SHA256SUMS`. The SBOM therefore describes the same source revision as the
tagged binaries.

## Validate

```sh
python3 -m json.tool sbom/xiom-pulse.cdx.json >/dev/null
python3 - <<'PY'
import json
d = json.load(open("sbom/xiom-pulse.cdx.json"))
assert d["bomFormat"] == "CycloneDX" and d["specVersion"] == "1.5"
assert d["metadata"]["component"]["name"] == "xiom-pulse"
assert len(d["components"]) >= 10
print("ok", len(d["components"]), "components")
PY
```

CI runs the same shape check on the Linux legs. `cyclonedx-cli validate` is
not installed in CI (no extra global tool); the generator's required fields
and the CI assertions are the current gate.

## Limitations (be honest)

- **Direct dependencies only.** The list is PULSE's manifest closure, not a
  recursive registry dependency graph; the registry packages currently
  depend on the stdlib, which is represented separately.
- **No package tarball hashes.** The registry publishes SHA-256 values for
  its tarballs; the generator does not fetch them (offline determinism).
  Adding them is a follow-up once the registry metadata is available in the
  build environment.
- **Stdlib is a git ref, not a tarball hash.** The full commit is carried in
  `xiom:stdlib:commit`; the archive is SHA-256 pinned by the toolchain
  release itself.
- **Not signed.** The release has build provenance (GitHub attestations) and
  per-file checksums; the SBOM is attached, not separately signed.
- **No SPDX output.** CycloneDX 1.5 is the chosen format; SPDX can be added
  if an auditor requires it.

## Follow-ups

1. Fetch and include registry tarball SHA-256 values.
2. Attach the SBOM to the build provenance attestation if the action
   supports extra subjects.
3. Add a CI diff gate when a dependency version changes without an SBOM
   update in the release notes.
4. Consider a signed SBOM (Sigstore/cosign) after the release signing story
   is fixed.
