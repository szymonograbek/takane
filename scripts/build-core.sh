#!/usr/bin/env bash
# Builds the Rust bridge into build/StremioBridge.xcframework (macOS, tvOS, tvOS simulator).
#
# Usage: scripts/build-core.sh [Debug|Release] [macosx|appletvos|appletvsimulator|all]
# The Xcode build phase passes $CONFIGURATION and $PLATFORM_NAME, so each app build refreshes
# only its own slice. The first run (or `all`) builds every slice and creates the XCFramework.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-${CONFIGURATION:-Debug}}"
platform="${2:-${PLATFORM_NAME:-all}}"
output="$root/build/StremioBridge.xcframework"

# Xcode build phases run with a minimal PATH. Resolve cargo and rustc through rustup
# (which honours rust-toolchain.toml) so a Homebrew rustc on PATH is never mixed in.
export PATH="$HOME/.cargo/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cargo="$(cd "$root/core" && rustup which cargo)"
export RUSTC="$(cd "$root/core" && rustup which rustc)"
# Xcode exports SDK and deployment variables for the app's platform; they would leak into
# the Rust builds of other slices.
unset SDKROOT MACOSX_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET

rust_target() {
    case "$1" in
        macosx) echo aarch64-apple-darwin ;;
        appletvos) echo aarch64-apple-tvos ;;
        appletvsimulator) echo aarch64-apple-tvos-sim ;;
        *) echo "unknown platform: $1" >&2; exit 1 ;;
    esac
}

# Matches the LibraryIdentifier xcodebuild assigns to each slice.
slice_dir() {
    case "$1" in
        macosx) echo macos-arm64 ;;
        appletvos) echo tvos-arm64 ;;
        appletvsimulator) echo tvos-arm64-simulator ;;
    esac
}

profile_dir="debug"
profile_flag=()
if [[ "$configuration" == "Release" ]]; then
    profile_dir="release"
    profile_flag=(--release)
fi

# Prints the path of the built static library.
build() {
    local target
    target="$(rust_target "$1")"
    local std_flag=()
    # tvOS is a tier 3 target with no prebuilt std.
    [[ "$target" == *tvos* ]] && std_flag=(-Zbuild-std=std,panic_abort)
    (cd "$root/core" && "$cargo" build --target "$target" ${std_flag[@]+"${std_flag[@]}"} ${profile_flag[@]+"${profile_flag[@]}"}) >&2
    echo "$root/core/target/$target/$profile_dir/libstremio_bridge.a"
}

if [[ "$platform" == "all" || ! -f "$output/Info.plist" ]]; then
    arguments=()
    for each in macosx appletvos appletvsimulator; do
        arguments+=(-library "$(build "$each")" -headers "$root/core/include")
    done
    rm -rf "$output"
    xcodebuild -create-xcframework "${arguments[@]}" -output "$output" >/dev/null
    echo "created $output ($configuration)"
else
    library="$(build "$platform")"
    # Copy only on change so Xcode relinks only when the library actually changed.
    rsync --checksum "$library" "$output/$(slice_dir "$platform")/libstremio_bridge.a"
    rsync --checksum --recursive --delete "$root/core/include/" "$output/$(slice_dir "$platform")/Headers/"
    echo "updated $platform slice of $output ($configuration)"
fi
