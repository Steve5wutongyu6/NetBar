#!/usr/bin/env bash
# Scripts/test.sh — runs every test: the engine's cargo suite and the app's
# unit tests against a freshly built app. CI and local runs use this one script,
# which delegates the app build to Scripts/build.sh so the SDK and architecture
# rules stay in a single place.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> engine tests" >&2
cargo test --locked --manifest-path "${ROOT}/engine/Cargo.toml" >&2
cargo clippy --locked --all-targets --manifest-path "${ROOT}/engine/Cargo.toml" -- -D warnings >&2
cargo fmt --check --manifest-path "${ROOT}/engine/Cargo.toml" >&2

echo "==> app tests" >&2
if ! "${ROOT}/Scripts/build.sh" --debug --test >"${ROOT}/build/test.log" 2>&1; then
  grep -E "error:|Test case .* failed|TEST FAILED" "${ROOT}/build/test.log" | head -40 >&2 || true
  echo "test.sh: app tests failed, see build/test.log" >&2
  exit 1
fi
grep -cE "Test case .* passed" "${ROOT}/build/test.log" >&2 || true
echo "==> all tests passed" >&2
