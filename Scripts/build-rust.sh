#!/usr/bin/env bash
# Scripts/build-rust.sh — builds the Rust engine per architecture and merges the
# static libraries into one universal archive under engine/target/universal/.
#
# Called by the Xcode "Build Rust Engine" phase (env: ARCHS, NETBAR_ENGINE_PROFILE_DIR)
# and by Scripts/build.sh (env: NETBAR_PROFILE=debug|release).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${NETBAR_PROFILE:-}"
if [ -z "${PROFILE}" ]; then
  case "${NETBAR_ENGINE_LIB_DIR:-}${NETBAR_ENGINE_PROFILE_DIR:-debug}" in
    */release*) PROFILE=release ;;
    *)          PROFILE=debug ;;
  esac
fi
# Xcode narrows ARCHS to one destination while a script phase runs, so the
# universal architecture list travels in its own setting.
ARCHS_TO_BUILD="${NETBAR_ENGINE_ARCHS:-${ARCHS:-arm64 x86_64}}"

command -v cargo >/dev/null 2>&1 || {
  echo "build-rust: cargo not found; install Rust (https://rustup.rs)" >&2
  exit 1
}

slices=()
for arch in ${ARCHS_TO_BUILD}; do
  case "${arch}" in
    arm64|arm64e) triple=aarch64-apple-darwin ;;
    x86_64)       triple=x86_64-apple-darwin ;;
    *)            echo "build-rust: unsupported arch ${arch}" >&2; exit 1 ;;
  esac
  if ! rustup target list --installed 2>/dev/null | grep -qx "${triple}"; then
    echo "build-rust: installing rust target ${triple}" >&2
    rustup target add "${triple}" >/dev/null 2>&1 || {
      echo "build-rust: cannot install target ${triple} (offline?)" >&2
      exit 1
    }
  fi
  if [ "${PROFILE}" = release ]; then
    cargo build --release --locked --manifest-path "${ROOT}/engine/Cargo.toml" \
      --target "${triple}" >&2
  else
    cargo build --locked --manifest-path "${ROOT}/engine/Cargo.toml" \
      --target "${triple}" >&2
  fi
  slices+=("${ROOT}/engine/target/${triple}/${PROFILE}/libnetbar_engine.a")
done

OUT="${ROOT}/engine/target/universal/${PROFILE}"
mkdir -p "${OUT}"
if [ "${#slices[@]}" -eq 1 ]; then
  cp "${slices[0]}" "${OUT}/libnetbar_engine.a"
else
  lipo -create -output "${OUT}/libnetbar_engine.a" "${slices[@]}"
fi
echo "build-rust: ${OUT}/libnetbar_engine.a" >&2
