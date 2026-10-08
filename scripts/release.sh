#!/usr/bin/env bash
# ============================================================================
# XIOM PULSE release packager (Linux): build, stage and zip one artifact
# per the ops naming convention: pulse-<ver>-<os>-<arch>.zip + .sha256.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/release.sh                 # version parsed from src/pulse.xi
#   scripts/release.sh --version 0.2.0 --out-dir dist
#   scripts/release.sh --no-build      # reuse out/pulse_app as-is
#
# Exit code: 0 = artifact + checksum written, 1 = failed.
# ============================================================================

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: release.sh [--version V] [--out-dir DIR] [--no-build]

  --version V   artifact version (default: parsed from src/pulse.xi)
  --out-dir D   output directory (default: dist/)
  --no-build    skip the build step (reuse out/pulse_app)
EOF
}

VERSION=""
OUT_DIR=""
DO_BUILD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION=${2:?missing value}; shift 2 ;;
    --out-dir) OUT_DIR=${2:?missing value}; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) printf 'unexpected argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION=$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' "$PULSE_REPO_ROOT/src/pulse.xi" | head -n 1 | tr -d '"')
fi
[ -n "$VERSION" ] || pulse_die "could not determine version (pass --version)"

case "$(uname -m)" in
  x86_64|amd64) ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) ARCH=$(uname -m) ;;
esac
OS=linux

if [ "$DO_BUILD" -eq 1 ]; then
  "$PULSE_SCRIPTS_DIR/build.sh" "$PULSE_REPO_ROOT/src/server.xi" --name pulse_app || pulse_die "build failed"
fi
[ -x "$PULSE_REPO_ROOT/out/pulse_app" ] || pulse_die "out/pulse_app missing (run build first)"

[ -n "$OUT_DIR" ] || OUT_DIR="$PULSE_REPO_ROOT/dist"
mkdir -p "$OUT_DIR"

NAME="pulse-$VERSION-$OS-$ARCH"
STAGE="$OUT_DIR/$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/resources/img"
cp "$PULSE_REPO_ROOT/out/pulse_app" "$STAGE/pulse_app"
cp "$PULSE_REPO_ROOT/resources/img/pulse-ico.ico" "$STAGE/resources/img/pulse-ico.ico"
cp "$PULSE_REPO_ROOT/README.md" "$STAGE/README.md"
cp "$PULSE_REPO_ROOT/LICENSE-APACHE" "$STAGE/LICENSE-APACHE"
cp "$PULSE_REPO_ROOT/LICENSE-MIT" "$STAGE/LICENSE-MIT"
cp "$PULSE_REPO_ROOT/NOTICE" "$STAGE/NOTICE"

ZIP="$OUT_DIR/$NAME.zip"
rm -f "$ZIP" "$ZIP.sha256"
# python3 zipfile keeps the archive portable and avoids the `zip` dependency
python3 - "$ZIP" "$STAGE" <<'PYEOF'
import os, shutil, sys
out_zip, stage = sys.argv[1], sys.argv[2]
base = out_zip[:-4] if out_zip.lower().endswith(".zip") else out_zip
shutil.make_archive(base, "zip", root_dir=stage)
PYEOF
[ -f "$ZIP" ] || pulse_die "zip creation failed"

( cd "$OUT_DIR" && sha256sum "$NAME.zip" > "$NAME.zip.sha256" )
pulse_log "release: artifact $ZIP"
pulse_log "release: checksum $ZIP.sha256"
pulse_log "release: contents:"
( cd "$STAGE" && find . -type f | sort )
exit 0
