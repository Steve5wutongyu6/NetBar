#!/usr/bin/env bash
# Scripts/package.sh — builds the Release app and writes dist/NetBar-<tag>.zip
# plus a checksum file. Used by CI and by anyone cutting a release locally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-$(git -C "${ROOT}" describe --tags --always 2>/dev/null || echo dev)}"
APP="${ROOT}/build/Release/NetBar.app"

"${ROOT}/Scripts/build.sh" --release

[ -d "${APP}" ] || { echo "package.sh: ${APP} is missing" >&2; exit 1; }
mkdir -p "${ROOT}/dist"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ROOT}/dist/NetBar-${TAG}.zip"
( cd "${ROOT}/dist" && shasum -a 256 ./*.zip > SHA256SUMS.txt )
echo "package.sh: dist/NetBar-${TAG}.zip" >&2
