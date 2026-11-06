#!/usr/bin/env python3
# ============================================================================
# XIOM PULSE -- one-command app scaffold.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Copies scaffolds/api to a destination and substitutes __APP_NAME__ in the
# text files. Cross-platform and dependency-free (Python 3.7+).
#
# Usage:
#   python scripts/new_app.py my-app
#   python scripts/new_app.py my-app ./services/my-app
#   python scripts/new_app.py my-app ./services/my-app --force
# ============================================================================
import argparse
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "scaffolds" / "api"
TEXT_SUFFIXES = {".xi", ".toml", ".md", ".txt", ".caddy"}
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def die(message):
    sys.stderr.write("new-app: error: " + message + "\n")
    sys.exit(2)


def main():
    parser = argparse.ArgumentParser(description="Create a PULSE Beacon app from the scaffold")
    parser.add_argument("name", help="app name (letters, digits, . _ -)")
    parser.add_argument("dest", nargs="?", help="destination directory (default: ./<name>)")
    parser.add_argument("--force", action="store_true", help="remove an existing destination")
    args = parser.parse_args()

    name = args.name.strip()
    if not NAME_RE.match(name):
        die("invalid app name; use letters, digits, '.', '_' or '-' (max 64)")

    dest = Path(args.dest) if args.dest else Path.cwd() / name
    if dest.exists():
        if not args.force:
            die("destination exists: {} (use --force to replace)".format(dest))
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(TEMPLATE, dest)

    for path in dest.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in TEXT_SUFFIXES and path.name != "Caddyfile":
            continue
        text = path.read_text(encoding="utf-8")
        text = text.replace("__APP_NAME__", name)
        with path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)

    print("created {}".format(dest))
    print("next:")
    print("  xiom pkg install xiom.pulse@0.3.2 xiom.http@0.1.11")
    print("  # from the PULSE repo root:")
    if os.name == "nt":
        print("  .\\scripts\\build.ps1 {}\\src\\main.xi -Name {}".format(dest, name))
        print("  $env:PULSE_PORT = \"8080\"; .\\out\\{}.exe".format(name))
    else:
        print("  bash scripts/build.sh {}/src/main.xi --name {}".format(dest, name))
        print("  PULSE_PORT=8080 ./out/{}".format(name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
