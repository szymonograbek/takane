#!/usr/bin/env bash
# Builds the tvOS app (Release, unsigned) and packages it as build/Takane.ipa for sideloading.
# The sideloading tool signs the app with the user's own Apple ID.
#
# Usage: scripts/package-ipa.sh
# Full log: build/xcodebuild-ipa.log
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p build
xcodegen generate --quiet
# Xcode checks that the bridge XCFramework exists before its build phase can create it.
scripts/build-core.sh Release appletvos

log=build/xcodebuild-ipa.log
if ! xcodebuild -project StremioTV.xcodeproj -scheme StremioTV-tvOS -configuration Release \
    -derivedDataPath build/DerivedData -destination 'generic/platform=tvOS' -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO build \
    > "$log" 2>&1; then
    grep -E "error:" "$log" | sort -u >&2 || true
    tail -n 40 "$log" >&2
    echo "build failed, see $log" >&2
    exit 1
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/Payload"
cp -R build/DerivedData/Build/Products/Release-appletvos/StremioTV.app "$staging/Payload/"
rm -f build/Takane.ipa
(cd "$staging" && zip -qry "$root/build/Takane.ipa" Payload)
echo "build/Takane.ipa"
