#!/usr/bin/env bash
# Builds the tvOS app signed for a paired Apple TV, installs it and launches it.
# Lists the paired physical Apple TVs and asks which one to use; with a single one, picks it.
# Pair an Apple TV first in Xcode (Window > Devices and Simulators).
#
# Usage: scripts/install-tvos.sh
# Full log: build/xcodebuild-tvos-install.log
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_id=com.ograbek.takane
cd "$root"
mkdir -p build

devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null
# One "<udid>\t<name> (<state>)" line per paired physical Apple TV.
lines=()
while IFS= read -r line; do lines+=("$line"); done < <(jq -r '.result.devices[]
    | select(.hardwareProperties.platform == "tvOS" and .hardwareProperties.reality == "physical")
    | "\(.hardwareProperties.udid)\t\(.deviceProperties.name) (\(.connectionProperties.tunnelState))"' "$devices_json")

case "${#lines[@]}" in
    0) echo "no paired Apple TV; pair one in Xcode > Window > Devices and Simulators" >&2; exit 1 ;;
    1) choice="${lines[0]}" ;;
    *)
        labels=()
        for line in "${lines[@]}"; do labels+=("${line#*$'\t'}"); done
        PS3="Apple TV: "
        select _ in "${labels[@]}"; do
            [[ -n "$REPLY" && "$REPLY" -ge 1 && "$REPLY" -le "${#lines[@]}" ]] && break
        done
        choice="${lines[REPLY-1]}"
        ;;
esac
udid="${choice%%$'\t'*}"
echo "installing on ${choice#*$'\t'}"

xcodegen generate --quiet
# The first build needs every XCFramework slice to exist before Xcode plans the build.
[[ -f build/StremioBridge.xcframework/macos-arm64/Headers/StremioBridge/module.modulemap ]] || scripts/build-core.sh Debug all >/dev/null

log=build/xcodebuild-tvos-install.log
if ! xcodebuild -project StremioTV.xcodeproj -scheme StremioTV-tvOS -configuration Debug \
    -derivedDataPath build/DerivedData -destination "id=$udid" -skipPackagePluginValidation \
    -allowProvisioningUpdates build \
    > "$log" 2>&1; then
    grep -E "error:" "$log" | sort -u >&2 || true
    echo "build failed, see $log" >&2
    exit 1
fi

xcrun devicectl device install app --device "$udid" build/DerivedData/Build/Products/Debug-appletvos/Takane.app >/dev/null
xcrun devicectl device process launch --device "$udid" "$bundle_id" >/dev/null
echo "installed and launched $bundle_id"
