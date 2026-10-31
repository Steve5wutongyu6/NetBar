#!/usr/bin/env bash
# Scripts/update-brew.sh — rewrites the Homebrew formula and cask for a release.
#
#   Scripts/update-brew.sh v1.0.0 dist/NetBar-v1.0.0.zip
#
# Both files are generated: the version and the two checksums (release archive
# and cask zip) are the only things that change between releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage: update-brew.sh <tag> <zip>}"
ZIP="${2:?usage: update-brew.sh <tag> <zip>}"
VERSION="${TAG#v}"

[ -f "${ZIP}" ] || { echo "update-brew.sh: ${ZIP} not found" >&2; exit 1; }

ZIP_SHA="$(shasum -a 256 "${ZIP}" | cut -d' ' -f1)"

# The source archive is published with the release rather than taken from
# GitHub's on-demand tarballs, which are regenerated and not byte-stable.
SRC="${ROOT}/dist/netbar-${TAG}-src.tar.gz"
[ -f "${SRC}" ] || { echo "update-brew.sh: ${SRC} not found" >&2; exit 1; }
SRC_SHA="$(shasum -a 256 "${SRC}" | cut -d' ' -f1)"

python3 - "${ROOT}" "${VERSION}" "${ZIP_SHA}" "${SRC_SHA}" <<'PY'
import pathlib
import sys

root, version, zip_sha, src_sha = sys.argv[1:5]

formula = pathlib.Path(root, "Formula", "netbar.rb")
text = formula.read_text()
lines = []
for line in text.splitlines():
    if line.startswith("  url "):
        lines.append(
            f'  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v{version}/'
            f'netbar-v{version}-src.tar.gz"'
        )
    elif line.startswith("  sha256 "):
        lines.append(f'  sha256 "{src_sha}"')
    else:
        lines.append(line)
formula.write_text("\n".join(lines) + "\n")

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

echo "update-brew.sh: formula and cask updated for ${TAG}" >&2
