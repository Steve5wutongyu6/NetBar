#!/usr/bin/env bash
# Scripts/xcode-env.sh — selects the newest installed Xcode for xcodebuild.
#
# CI runners trail the newest Xcode; this prints an exportable DEVELOPER_DIR for
# the newest /Applications/Xcode*.app so the same scripts work locally and in CI.
# It never fails: when nothing newer than the active toolchain exists it prints
# a no-op assignment.
set -euo pipefail

# Pick the newest Xcode by version, not by name: "Xcode_9.app" must not beat
# "Xcode_27.app" the way a plain string sort would decide it.
candidate=""
for app in $(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V -r); do
  [ -d "${app}" ] || continue
  candidate="${app}"
  break
done

if [ -n "${candidate}" ] && [ -x "${candidate}/Contents/Developer/usr/bin/xcodebuild" ]; then
  printf 'export DEVELOPER_DIR=%s\n' "${candidate}/Contents/Developer"
else
  printf 'export DEVELOPER_DIR=%s\n' "$(xcode-select -p)"
fi
