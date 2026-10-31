#!/usr/bin/env bash
# Scripts/test.sh — runs every test: the engine's cargo suite and the app's
# unit tests against a freshly built app. CI and local runs use this one script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> engine tests" >&2
cargo test --locked --manifest-path "${ROOT}/engine/Cargo.toml" >&2
cargo clippy --locked --all-targets --manifest-path "${ROOT}/engine/Cargo.toml" -- -D warnings >&2
cargo fmt --check --manifest-path "${ROOT}/engine/Cargo.toml" >&2

echo "==> app tests" >&2
"${ROOT}/Scripts/build-rust.sh"
xcodebuild -project "${ROOT}/NetBar.xcodeproj" \
  -scheme NetBar -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "${ROOT}/build/DerivedData" \
  test | tee "${ROOT}/build/test.log" | grep -E "Test Suite|Test case|error:|TEST (SUCCEEDED|FAILED)|✘" || true
grep -q "TEST SUCCEEDED" "${ROOT}/build/test.log" || {
  echo "test.sh: app tests failed, see build/test.log" >&2
  exit 1
}
echo "==> all tests passed" >&2
