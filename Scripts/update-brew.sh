#!/usr/bin/env bash
# Scripts/update-brew.sh — rewrites the Homebrew cask for a release.
#
#   Scripts/update-brew.sh v1.0.0 dist/NetBar-v1.0.0.zip
#
# The cask is generated: the version and the checksum of the release archive are
# the only things that change between releases. NetBar installs as a cask because
# Homebrew's build sandbox cannot run Xcode's Swift macro plugins; building from
# source is `make build`, or `brew install --HEAD` on a machine whose sandbox
# allows it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage: update-brew.sh <tag> <zip>}"
ZIP="${2:?usage: update-brew.sh <tag> <zip>}"
VERSION="${TAG#v}"

[ -f "${ZIP}" ] || { echo "update-brew.sh: ${ZIP} not found" >&2; exit 1; }

ZIP_SHA="$(shasum -a 256 "${ZIP}" | cut -d' ' -f1)"

python3 - "${ROOT}" "${VERSION}" "${ZIP_SHA}" <<'PY'
import pathlib
import sys

root, version, zip_sha = sys.argv[1:4]

cask = pathlib.Path(root, "Casks", "netbar.rb")
lines = []
for line in cask.read_text().splitlines():
    if line.startswith("  version "):
        lines.append(f'  version "{version}"')
    elif line.startswith("  sha256 "):
        lines.append(f'  sha256 "{zip_sha}"')
    else:
        lines.append(line)
cask.write_text("\n".join(lines) + "\n")
PY

echo "update-brew.sh: cask updated for ${TAG}" >&2
