#!/usr/bin/env bash
# Scripts/bump-version.sh — sets the version in the three places it lives.
#
#   Scripts/bump-version.sh 1.0.3
#
# The Xcode project reads MARKETING_VERSION from Configs/Shared.xcconfig, so the
# project file is deliberately absent from this list.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: bump-version.sh <version>}"

case "${VERSION}" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "bump-version.sh: expected X.Y.Z, got ${VERSION}" >&2; exit 1 ;;
esac

python3 - "${ROOT}" "${VERSION}" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
version = sys.argv[2]

shared = root / "Configs" / "Shared.xcconfig"
text = re.sub(r"^MARKETING_VERSION = .*$", f"MARKETING_VERSION = {version}", shared.read_text(), flags=re.M)
shared.write_text(text)

cargo = root / "engine" / "Cargo.toml"
text = re.sub(r'^version = ".*"$', f'version = "{version}"', cargo.read_text(), count=1, flags=re.M)
cargo.write_text(text)

cask = root / "Casks" / "netbar.rb"
text = re.sub(r'^  version ".*"$', f'  version "{version}"', cask.read_text(), flags=re.M)
cask.write_text(text)
PY

echo "bump-version.sh: ${VERSION} in Shared.xcconfig, Cargo.toml and the cask" >&2
