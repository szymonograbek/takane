#!/usr/bin/env bash
# Runs the unit tests (app/Tests) for the pure layers on macOS. Lints them like the app build does.
# Full log: build/xcodebuild-test.log
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p build
xcodegen generate --quiet

log="build/xcodebuild-test.log"
if ! xcodebuild -project StremioTV.xcodeproj -scheme StremioTVTests -derivedDataPath build/DerivedData \
    -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation test > "$log" 2>&1; then
    grep -E "error:|failed|✘" "$log" | sort -u >&2 || true
    echo "tests failed, see $log" >&2
    exit 1
fi
grep -E "Test run with|Executed" "$log" | tail -2
