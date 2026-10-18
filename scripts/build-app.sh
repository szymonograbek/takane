#!/usr/bin/env bash
# Generates the Xcode project and builds the app (Debug) into build/DerivedData.
#
# Usage: scripts/build-app.sh [macos|tvos-sim|tvos-device]   (default: macos)
# tvos-device only proves the device build compiles and links; it is unsigned, because
# signing for a device needs a provisioning profile from a registered Apple TV.
# Full log: build/xcodebuild-<platform>.log
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
platform="${1:-macos}"
signing=()
case "$platform" in
    macos) scheme=StremioTV-macOS; destination='platform=macOS,arch=arm64' ;;
    tvos-sim) scheme=StremioTV-tvOS; destination='generic/platform=tvOS Simulator' ;;
    tvos-device) scheme=StremioTV-tvOS; destination='generic/platform=tvOS'; signing=(CODE_SIGNING_ALLOWED=NO) ;;
    *) echo "unknown platform: $platform" >&2; exit 1 ;;
esac

cd "$root"
mkdir -p build
xcodegen generate --quiet
# The first build needs every XCFramework slice to exist before Xcode plans the build.
[[ -f build/StremioBridge.xcframework/Info.plist ]] || scripts/build-core.sh Debug all >/dev/null

log="build/xcodebuild-$platform.log"
if ! xcodebuild -project StremioTV.xcodeproj -scheme "$scheme" -configuration Debug \
    -derivedDataPath build/DerivedData -destination "$destination" ${signing[@]+"${signing[@]}"} build \
    > "$log" 2>&1; then
    grep -E "error:" "$log" | sort -u >&2 || true
    echo "build failed, see $log" >&2
    exit 1
fi
echo "built $scheme for $platform"
