#!/usr/bin/env python3
# ============================================================================
# XIOM PULSE -- CycloneDX SBOM generator (WP2 release integrity).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Emits a CycloneDX 1.5 JSON SBOM for one source revision:
#   * the product component (name/version/commit),
#   * every [dependencies] row in xiom.toml,
#   * the compiler (one component per platform, with its SHA-256 pin),
#   * the stdlib git ref from STDLIB_VERSION.
#
# Pins come from toolchain-pins.json; when the workflow env is present
# (XIOM_TOOLCHAIN_VERSION / XIOM_*_SHA256) the script checks the two agree
# and fails on drift. The serial number and timestamp are deterministic
# (uuid5 of version+commit; the commit timestamp unless SOURCE_DATE_EPOCH or
# --timestamp is given), so the same revision produces the same SBOM.
#
# Usage:
#   python scripts/sbom.py --out sbom/xiom-pulse.cdx.json
#   python scripts/sbom.py --out /tmp/sbom.json --commit "$GITHUB_SHA"
#
# Exit code 0 = written; 2 = input/pin error.
# ============================================================================
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PINS_PATH = ROOT / "toolchain-pins.json"
TOML_PATH = ROOT / "xiom.toml"
VERSION_PATH = ROOT / "src" / "version.xi"
STDLIB_PATH = ROOT / "STDLIB_VERSION"

ENV_PLATFORMS = {
    "XIOM_LINUX_SHA256": "linux-x64",
    "XIOM_LINUX_ARM64_SHA256": "linux-arm64",
    "XIOM_WINDOWS_SHA256": "windows-x64",
    "XIOM_MACOS_X64_SHA256": "macos-x64",
    "XIOM_MACOS_ARM64_SHA256": "macos-arm64",
}


def die(message):
    sys.stderr.write("sbom: error: " + message + "\n")
    sys.exit(2)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        die("cannot read {}: {}".format(path, exc))


def product_version():
    m = re.search(r'"(\d+\.\d+\.\d+)"', read_text(VERSION_PATH))
    if not m:
        die("cannot read the product version from src/version.xi")
    return m.group(1)


def dependencies():
    deps = {}
    in_deps = False
    for raw in read_text(TOML_PATH).splitlines():
        line = raw.strip()
        if line.startswith("["):
            in_deps = line == "[dependencies]"
            continue
        if not in_deps or not line or line.startswith("#"):
            continue
        m = re.match(r'^"([^"]+)"\s*=\s*"([^"]+)"', line)
        if m:
            deps[m.group(1)] = m.group(2)
    if not deps:
        die("no [dependencies] rows found in xiom.toml")
    return deps


def pins():
    try:
        data = json.loads(read_text(PINS_PATH))
    except ValueError as exc:
        die("toolchain-pins.json is not valid JSON: {}".format(exc))
    if not data.get("compiler") or not data.get("platforms"):
        die("toolchain-pins.json needs compiler + platforms")
    return data


def check_pins(pin_data):
    env_ver = os.environ.get("XIOM_TOOLCHAIN_VERSION")
    if env_ver and env_ver != pin_data["compiler"]:
        die(
            "toolchain drift: XIOM_TOOLCHAIN_VERSION={} but toolchain-pins.json has {}".format(
                env_ver, pin_data["compiler"]
            )
        )
    for env_name, platform in ENV_PLATFORMS.items():
        env_hash = os.environ.get(env_name)
        if env_hash and env_hash.lower() != pin_data["platforms"].get(platform, "").lower():
            die(
                "toolchain drift: {} does not match toolchain-pins.json[{}]".format(
                    env_name, platform
                )
            )


def git_commit(explicit):
    if explicit:
        return explicit
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=str(ROOT), stderr=subprocess.DEVNULL
        ).decode("ascii").strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def timestamp(explicit):
    if explicit:
        return explicit
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch:
        try:
            dt = datetime.datetime.fromtimestamp(int(epoch), datetime.timezone.utc)
            return dt.isoformat().replace("+00:00", "Z")
        except ValueError:
            die("SOURCE_DATE_EPOCH is not an integer: {}".format(epoch))
    try:
        return subprocess.check_output(
            ["git", "show", "-s", "--format=%cI", "HEAD"],
            cwd=str(ROOT),
            stderr=subprocess.DEVNULL,
        ).decode("ascii").strip()
    except (OSError, subprocess.CalledProcessError):
        return datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")


def purl(name, version, platform=None):
    base = "pkg:generic/{}@{}".format(name, version)
    if platform:
        base += "?platform={}".format(platform)
    return base


def build_bom(version, commit, deps, pin_data, stamp):
    compiler_version = pin_data["compiler"].lstrip("v")
    short_stdlib = read_text(STDLIB_PATH).strip()[:8] if STDLIB_PATH.exists() else "unknown"
    components = []

    for name in sorted(deps):
        components.append(
            {
                "type": "library",
                "name": name,
                "version": deps[name],
                "purl": purl(name, deps[name]),
            }
        )

    for platform in sorted(pin_data["platforms"]):
        digest = pin_data["platforms"][platform]
        components.append(
            {
                "type": "framework",
                "name": "xiom-compiler",
                "version": compiler_version,
                "purl": purl("xiom-compiler", compiler_version, platform),
                "hashes": [{"alg": "SHA-256", "content": digest.lower()}],
            }
        )

    components.append(
        {
            "type": "library",
            "name": "xiom-stdlib",
            "version": short_stdlib,
            "purl": purl("xiom-stdlib", short_stdlib),
            "properties": [
                {"name": "xiom:stdlib:commit", "value": read_text(STDLIB_PATH).strip()}
            ],
        }
    )

    serial = uuid.uuid5(uuid.NAMESPACE_URL, "xiom-pulse:{}:{}".format(version, commit))
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:{}".format(serial),
        "version": 1,
        "metadata": {
            "timestamp": stamp,
            "tools": [
                {"vendor": "XIOM", "name": "scripts/sbom.py", "version": "1"}
            ],
            "component": {
                "type": "application",
                "name": "xiom-pulse",
                "version": version,
                "purl": purl("xiom-pulse", version),
                "properties": [
                    {"name": "xiom:pulse:commit", "value": commit},
                    {"name": "xiom:pulse:toolchain", "value": pin_data["compiler"]},
                    {"name": "xiom:pulse:stdlib", "value": short_stdlib},
                ],
            },
        },
        "components": components,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate a CycloneDX SBOM for PULSE")
    parser.add_argument("--out", required=True, help="output .cdx.json path")
    parser.add_argument("--commit", default="", help="source commit (default: git HEAD)")
    parser.add_argument("--timestamp", default="", help="ISO-8601 timestamp (default: commit date)")
    args = parser.parse_args()

    pin_data = pins()
    check_pins(pin_data)
    version = product_version()
    commit = git_commit(args.commit)
    stamp = timestamp(args.timestamp)
    bom = build_bom(version, commit, dependencies(), pin_data, stamp)

    out = Path(args.out)
    if not out.is_absolute():
        out = ROOT / out
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(bom, handle, indent=2, sort_keys=True)
        handle.write("\n")
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    print(
        "sbom: {} components={} version={} commit={} sha256={}".format(
            out, len(bom["components"]), version, commit[:12], digest[:16]
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
