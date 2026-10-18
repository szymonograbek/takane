#!/usr/bin/env bash
# Prints the UDID of the "Stremio Apple TV" simulator, creating and booting it when needed.
# Usage: udid="$(scripts/tvos-simulator.sh)"
set -euo pipefail

name="Stremio Apple TV"
device="$(xcrun simctl list devices available | grep -F "$name (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
if [[ -z "$device" ]]; then
    runtime="$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.tvOS-[0-9-]+' | tail -1)"
    [[ -n "$runtime" ]] || { echo "no tvOS simulator runtime; run: xcodebuild -downloadPlatform tvOS" >&2; exit 1; }
    device="$(xcrun simctl create "$name" com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K "$runtime")"
fi
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
echo "$device"
