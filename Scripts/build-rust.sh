#!/usr/bin/env bash
# Scripts/build-rust.sh — builds the Rust engine and places the static library
# under engine/target/universal/<profile>/libnetbar_engine.a.
#
# Called by the Xcode "Build Rust Engine" phase and by Scripts/build.sh
# (env: NETBAR_PROFILE=debug|release).
#
# Two toolchains are supported:
#   * rustup   — builds every architecture and merges them with lipo
#   * plain cargo (Homebrew's rust) — builds for the host architecture only,
#     which is all a source install needs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${NETBAR_PROFILE:-}"
if [ -z "${PROFILE}" ]; then
  case "${NETBAR_ENGINE_LIB_DIR:-debug}" in
    */release*) PROFILE=release ;;
    *)          PROFILE=debug ;;
  esac
fi
# Xcode narrows ARCHS to one destination while a script phase runs, so the
# universal architecture list travels in its own setting.
ARCHS_TO_BUILD="${NETBAR_ENGINE_ARCHS:-${ARCHS:-arm64 x86_64}}"

command -v cargo >/dev/null 2>&1 || {
  echo "build-rust: cargo not found; install Rust (https://rustup.rs or brew install rust)" >&2
  exit 1
}

OUT="${ROOT}/engine/target/universal/${PROFILE}"
mkdir -p "${OUT}"

# macOS ships bash 3.2, where an empty array cannot be expanded under `set -u`.
PROFILE_FLAG=""
if [ "${PROFILE}" = release ]; then
  PROFILE_FLAG="--release"
fi

# Decide by what rustup can actually do: Homebrew builds run with a rustup shim
# on PATH but no usable toolchain, and there the plain build is the right one.
use_rustup=0
if [ "${NETBAR_PLAIN_CARGO:-0}" = "1" ]; then
  use_rustup=0
elif command -v rustup >/dev/null 2>&1 \
   && rustup which rustc >/dev/null 2>&1 \
   && [ -n "$(rustup target list --installed 2>/dev/null)" ]; then
  use_rustup=1
fi

if [ "${use_rustup}" -eq 1 ]; then
  # Homebrew's rust can shadow the rustup toolchain on PATH, and its rustc only
  # ships the host target, so both binaries are pinned to the rustup toolchain.
  CARGO="$(rustup which cargo 2>/dev/null || command -v cargo)"
  RUSTC="$(rustup which rustc 2>/dev/null || command -v rustc)"
  export RUSTC
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
    "${CARGO}" build ${PROFILE_FLAG} --locked --manifest-path "${ROOT}/engine/Cargo.toml" \
      --target "${triple}" >&2
    slices+=("${ROOT}/engine/target/${triple}/${PROFILE}/libnetbar_engine.a")
  done

  if [ "${#slices[@]}" -eq 1 ]; then
    cp "${slices[0]}" "${OUT}/libnetbar_engine.a"
  else
    lipo -create -output "${OUT}/libnetbar_engine.a" "${slices[@]}"
  fi
else
  # No rustup: one host-architecture build. A universal release comes from the
  # rustup toolchain, which is what CI and the published cask use.
  echo "build-rust: plain cargo, building for the host architecture" >&2
  unset RUSTC || true
  cargo build ${PROFILE_FLAG} --locked --manifest-path "${ROOT}/engine/Cargo.toml" >&2
  cp "${ROOT}/engine/target/${PROFILE}/libnetbar_engine.a" "${OUT}/libnetbar_engine.a"
fi

echo "build-rust: ${OUT}/libnetbar_engine.a" >&2
