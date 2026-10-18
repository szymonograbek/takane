#!/usr/bin/env bash
# Runs the unit tests and lints them like the app build does: StremioTVTests (app/Tests) for the
# pure layers, then StremioTVAdapterTests (app/AdapterTests) for the HTTP adapters, on macOS.
#
# Live tests call the real services and are skipped unless enabled. xcodebuild hands the test
# process every variable prefixed with TEST_RUNNER_, prefix removed:
#   TEST_RUNNER_STREMIO_LIVE_TESTS=1 scripts/test.sh
# Full logs: build/xcodebuild-test-<scheme>.log
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p build
xcodegen generate --quiet

for scheme in StremioTVTests StremioTVAdapterTests; do
    log="build/xcodebuild-test-$scheme.log"
    if ! xcodebuild -project StremioTV.xcodeproj -scheme "$scheme" -derivedDataPath build/DerivedData \
        -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation test > "$log" 2>&1; then
        grep -E "error:|failed|✘" "$log" | sort -u >&2 || true
        echo "$scheme failed, see $log" >&2
        exit 1
    fi
    grep -E "Test run with|Executed" "$log" | tail -2
done
