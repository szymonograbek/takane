#!/usr/bin/env bash
# Builds and launches the app in smoke-test mode: browse the board, page a row, search and load a
# title's details from the default add-ons, install the add-on, resolve streams, play one, confirm
# core recorded progress, then quit. Exit code 0 means every step passed.
#
# The add-on URL contains debrid credentials, so it is read from STREMIO_SMOKE_ADDON_URL
# or from the git-ignored .env.smoke file, never from the repo. STREMIO_SMOKE_SUBTITLES_ADDON_URL,
# optional and read the same way, adds a subtitles add-on and plays one of its files.
#
# The default titles are free to share: Night of the Living Dead (1968) is in the public domain and
# Pioneer One is released under Creative Commons, so a run never streams copyrighted work.
#
# Usage: scripts/smoke.sh [--tvos] [--no-addons] [type/id]
#   scripts/smoke.sh                          macOS, movie/tt0063350
#   scripts/smoke.sh --tvos series/tt1748166:1:1
#   scripts/smoke.sh --no-addons              core starts without its default add-ons; checks that
#                                             board, search and details report none installed, then
#                                             that installing Cinemeta fills the board
# On tvOS it runs on the "Stremio Apple TV" simulator (created on first use) and also saves
# a simulator screenshot taken while the stream is on screen. Playback is muted (STREMIO_MUTE=1),
# so a run stays silent.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
platform=macos
if [[ "${1:-}" == "--tvos" ]]; then
    platform=tvos
    shift
fi
no_addons=0
if [[ "${1:-}" == "--no-addons" ]]; then
    no_addons=1
    shift
fi
item="${1:-movie/tt0063350}"
bundle_id=com.ograbek.takane

if [[ -z "${STREMIO_SMOKE_ADDON_URL:-}" && -f "$root/.env.smoke" ]]; then
    source "$root/.env.smoke"
fi
: "${STREMIO_SMOKE_ADDON_URL:?set STREMIO_SMOKE_ADDON_URL or add it to .env.smoke}"

report() {
    local logs="$1"
    echo "log: $logs/app.log"
    grep -E "SMOKE" "$logs/app.log" | sed -E 's/^[^ ]+ //' || true
    cat "$logs/smoke-result.json" 2>/dev/null || echo "no smoke-result.json"
}

if [[ "$platform" == macos ]]; then
    # Always test what the sources build today, never a stale app.
    "$root/scripts/build-app.sh" macos >/dev/null
    app="$root/build/DerivedData/Build/Products/Debug/Takane.app"
    logs="$HOME/Library/Logs/$bundle_id"
    rm -f "$logs/smoke-result.json" "$logs/smoke-frame.png"

    # A fresh core profile per run, so results never depend on state left by earlier runs. Saved
    # window state is ignored too: restored from a build with other scenes, it opens no window.
    storage="$(mktemp -d -t stremio-smoke)"
    trap 'rm -rf "$storage"' EXIT

    status=0
    STREMIO_STORAGE_DIRECTORY="$storage" \
    STREMIO_SMOKE_ADDON_URL="$STREMIO_SMOKE_ADDON_URL" \
    STREMIO_SMOKE_SUBTITLES_ADDON_URL="${STREMIO_SMOKE_SUBTITLES_ADDON_URL:-}" \
    STREMIO_SMOKE_ITEM="$item" \
    STREMIO_SMOKE_EXIT=1 \
    STREMIO_MUTE=1 \
    STREMIO_SMOKE_CATALOG_EMPTY="$no_addons" \
    EMPTY_OFFICIAL_ADDONS="$no_addons" \
    STREMIO_LOG_LEVEL="${STREMIO_LOG_LEVEL:-debug}" \
        "$app/Contents/MacOS/Takane" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 || status=$?
    echo "exit code: $status"
    report "$logs"
    exit "$status"
fi

"$root/scripts/build-app.sh" tvos-sim >/dev/null
app="$root/build/DerivedData/Build/Products/Debug-appletvsimulator/Takane.app"

device="$("$root/scripts/tvos-simulator.sh")"
xcrun simctl install "$device" "$app"

data="$(xcrun simctl get_app_container "$device" "$bundle_id" data)"
logs="$data/Library/Caches/Logs"
storage="$data/tmp/smoke-storage"
rm -rf "$storage" "$logs/smoke-result.json" "$logs/smoke-frame.png" "$logs/smoke-screen.png"

SIMCTL_CHILD_STREMIO_STORAGE_DIRECTORY="$storage" \
SIMCTL_CHILD_STREMIO_SMOKE_ADDON_URL="$STREMIO_SMOKE_ADDON_URL" \
SIMCTL_CHILD_STREMIO_SMOKE_SUBTITLES_ADDON_URL="${STREMIO_SMOKE_SUBTITLES_ADDON_URL:-}" \
SIMCTL_CHILD_STREMIO_SMOKE_ITEM="$item" \
SIMCTL_CHILD_STREMIO_SMOKE_EXIT=1 \
SIMCTL_CHILD_STREMIO_MUTE=1 \
SIMCTL_CHILD_STREMIO_SMOKE_CATALOG_EMPTY="$no_addons" \
SIMCTL_CHILD_EMPTY_OFFICIAL_ADDONS="$no_addons" \
SIMCTL_CHILD_STREMIO_LOG_LEVEL="${STREMIO_LOG_LEVEL:-debug}" \
    xcrun simctl launch --terminate-running-process "$device" "$bundle_id" >/dev/null

# The app writes the result, then keeps the frame on screen for 2 s before quitting.
for _ in $(seq 1 600); do
    [[ -f "$logs/smoke-result.json" ]] && break
    sleep 0.2
done
xcrun simctl io "$device" screenshot "$logs/smoke-screen.png" >/dev/null 2>&1 || true
sleep 3

rm -rf "$storage"

echo "simulator: $device"
echo "screenshot: $logs/smoke-screen.png"
report "$logs"
grep -q '"passed" : true' "$logs/smoke-result.json" 2>/dev/null
