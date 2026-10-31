#!/usr/bin/env bash
# Scripts/build.sh — builds the engine and the app with the sibling Xcode project.
#
#   Scripts/build.sh [--debug|--release] [--test]
#
# --test runs the unit tests against the built app on a headless destination.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/build"
CONFIG="${CONFIG:-Debug}"
DO_TEST=0
for arg in "$@"; do
  case "${arg}" in
    --debug)   CONFIG=Debug ;;
    --release) CONFIG=Release ;;
    --test)    DO_TEST=1 ;;
    *) echo "build.sh: unknown option ${arg}" >&2; exit 2 ;;
  esac
done

if [ "${CONFIG}" = Release ]; then NETBAR_PROFILE=release; else NETBAR_PROFILE=debug; fi
export NETBAR_PROFILE

SIGNING_ARG=""
XCCONFIG="${XCCONFIG_OVERRIDE:-}"
if [ -n "${NETBAR_SIGNING_XCCONFIG:-}" ] && [ -f "${NETBAR_SIGNING_XCCONFIG}" ]; then
  XCCONFIG="${NETBAR_SIGNING_XCCONFIG}"
fi

# No -destination for plain builds: it narrows the build to one architecture.
# Tests need a destination, and they run on the host anyway.
ARGS=(-project "${ROOT}/NetBar.xcodeproj" -scheme NetBar -configuration "${CONFIG}"
      -derivedDataPath "${ROOT}/build/DerivedData")
TEST_ARGS=("${ARGS[@]}" -destination "platform=macOS")

# The project targets the macOS 27 SDK. A CI runner that only has an older SDK
# cannot link against it, so when NETBAR_ALLOW_OLDER_SDK=1 the deployment target
# drops to whatever SDK is installed. Local builds with Xcode 27 are untouched.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)"
if [ "${NETBAR_ALLOW_OLDER_SDK:-0}" = "1" ]; then
  OLDEST="$(printf '%s\n27.0\n' "${SDK_VERSION}" | sort -V | head -1)"
  if [ "${OLDEST}" != "27.0" ]; then
    echo "build.sh: installed SDK is ${SDK_VERSION}; building against it instead of 27.0" >&2
    ARGS+=("MACOSX_DEPLOYMENT_TARGET=${SDK_VERSION}")
    TEST_ARGS+=("MACOSX_DEPLOYMENT_TARGET=${SDK_VERSION}")
  fi
fi

# Xcode 27 resolves the scheme's destination to the local Mac and then builds
# only that slice, so a universal release states its architectures outright.
if [ "${CONFIG}" = Release ]; then
  ARGS+=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
  TEST_ARGS+=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi
if [ -n "${XCCONFIG}" ]; then
  ARGS+=(-xcconfig "${XCCONFIG}")
fi

"${ROOT}/Scripts/build-rust.sh"

xcodebuild "${ARGS[@]}" build | tee "${ROOT}/build/build-${CONFIG}.log" | grep -E "error:|warning:|BUILD" || true
grep -q "BUILD SUCCEEDED" "${ROOT}/build/build-${CONFIG}.log" || {
  echo "build.sh: build failed, see build/build-${CONFIG}.log" >&2; exit 1; }

if [ "${DO_TEST}" -eq 1 ]; then
  xcodebuild "${TEST_ARGS[@]}" test
fi
echo "build.sh: ${ROOT}/build/${CONFIG}/NetBar.app"
