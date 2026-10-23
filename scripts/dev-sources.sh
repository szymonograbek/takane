#!/usr/bin/env bash
# Runs a local Jellyfin server and a WebDAV folder over the same generated media, for developing
# and verifying media sources against real servers. Needs Docker (OrbStack or Docker Desktop) and
# ffmpeg. State lives in build/dev-sources; the clips are silent test patterns.
#
# Usage: scripts/dev-sources.sh up      start both servers, generating media and setting up Jellyfin once
#        scripts/dev-sources.sh env     print the URLs and credentials as shell assignments
#        scripts/dev-sources.sh down    stop both servers, keeping their state
#        scripts/dev-sources.sh reset   stop both servers and delete their state and media
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEV_SOURCES_DIR="$root/build/dev-sources"
compose=(docker compose -f "$root/scripts/dev-sources/compose.yml")

user=takane
password=takane-dev
jellyfin_local=http://localhost:8196
font=/System/Library/Fonts/Supplemental/Arial.ttf

# Folder names carry IMDb ids, so Jellyfin matches each title exactly. WebDAV serves the same tree.
movies=(
    "Movies/Sintel (2010) [imdbid-tt1727587]/Sintel (2010).mkv"
    "Movies/Big Buck Bunny (2008) [imdbid-tt1254207]/Big Buck Bunny (2008).mp4"
    "Movies/Tears of Steel (2012) [imdbid-tt2285752]/Tears of Steel (2012).mkv"
    "Movies/Elephants Dream (2006) [imdbid-tt0807840]/Elephants Dream (2006).mkv"
)
episodes=(
    "Shows/Pioneer One (2010) [imdbid-tt1748166]/Season 01/Pioneer One S01E01.mkv"
    "Shows/Pioneer One (2010) [imdbid-tt1748166]/Season 01/Pioneer One S01E02.mkv"
    "Shows/Pioneer One (2010) [imdbid-tt1748166]/Season 01/Pioneer One S01E03.mkv"
)
home_videos=("Home Videos/Beach Day.mp4")

lan_address() {
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo localhost
}

# A 90-second silent test pattern labelled with the file's name.
make_clip() {
    local path="$DEV_SOURCES_DIR/media/$1"
    [[ -f "$path" ]] && return
    mkdir -p "$(dirname "$path")"
    local label
    label="$(basename "${path%.*}")"
    ffmpeg -hide_banner -loglevel error \
        -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=90" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
        -vf "drawtext=fontfile=$font:text='${label//\'/}':fontsize=72:fontcolor=white:x=(w-tw)/2:y=h-140:box=1:boxcolor=black@0.6" \
        -shortest -c:v libx264 -preset veryfast -crf 38 -c:a aac -b:a 32k "$path"
}

make_media() {
    local clip
    for clip in "${movies[@]}" "${episodes[@]}" "${home_videos[@]}"; do make_clip "$clip"; done
    local subtitles="$DEV_SOURCES_DIR/media/${movies[0]%.*}.en.srt"
    [[ -f "$subtitles" ]] || printf '1\n00:00:01,000 --> 00:00:30,000\nA subtitle from a sidecar file.\n' >"$subtitles"
}

jellyfin() {
    local method=$1 path=$2 body=${3:-}
    curl -fsS -X "$method" "$jellyfin_local$path" -H 'Content-Type: application/json' \
        -H "Authorization: MediaBrowser Client=\"dev-sources\", Device=\"script\", DeviceId=\"dev-sources\", Version=\"1\"${token:+, Token=\"$token\"}" \
        ${body:+-d "$body"}
}

wait_for_jellyfin() {
    local attempt
    for attempt in $(seq 90); do
        curl -fsS "$jellyfin_local/System/Info/Public" >/dev/null 2>&1 && return
        sleep 2
    done
    echo "Jellyfin did not start; see: docker compose -f scripts/dev-sources/compose.yml logs jellyfin" >&2
    exit 1
}

# Runs Jellyfin's first-run wizard and adds the libraries. Jellyfin remembers it in its config.
set_up_jellyfin() {
    local token=""
    if [[ "$(curl -fsS "$jellyfin_local/System/Info/Public")" == *'"StartupWizardCompleted":true'* ]]; then
        return
    fi
    jellyfin POST /Startup/Configuration '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
    jellyfin GET /Startup/User >/dev/null
    jellyfin POST /Startup/User "{\"Name\":\"$user\",\"Password\":\"$password\"}"
    jellyfin POST /Startup/RemoteAccess '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}'
    jellyfin POST /Startup/Complete
    token="$(jellyfin POST /Users/AuthenticateByName "{\"Username\":\"$user\",\"Pw\":\"$password\"}" |
        python3 -I -c 'import json,sys; print(json.load(sys.stdin)["AccessToken"])')"
    jellyfin POST "/Library/VirtualFolders?name=Movies&collectionType=movies&paths=%2Fmedia%2FMovies&refreshLibrary=false" '{"LibraryOptions":{}}'
    jellyfin POST "/Library/VirtualFolders?name=Shows&collectionType=tvshows&paths=%2Fmedia%2FShows&refreshLibrary=false" '{"LibraryOptions":{}}'
    jellyfin POST "/Library/VirtualFolders?name=Home%20Videos&collectionType=homevideos&paths=%2Fmedia%2FHome%20Videos&refreshLibrary=false" '{"LibraryOptions":{}}'
    jellyfin POST /Library/Refresh
}

print_env() {
    local host
    host="$(lan_address)"
    cat <<EOF
# The simulator reaches the servers on localhost; an Apple TV on the same network uses $host.
DEV_JELLYFIN_URL=http://localhost:8196
DEV_JELLYFIN_LAN_URL=http://$host:8196
DEV_WEBDAV_URL=http://localhost:8197
DEV_WEBDAV_LAN_URL=http://$host:8197
DEV_SOURCES_USER=$user
DEV_SOURCES_PASSWORD=$password
EOF
}

case "${1:-}" in
    up)
        make_media
        mkdir -p "$DEV_SOURCES_DIR/jellyfin/config" "$DEV_SOURCES_DIR/jellyfin/cache"
        "${compose[@]}" up -d --wait >/dev/null
        wait_for_jellyfin
        set_up_jellyfin
        print_env
        ;;
    env) print_env ;;
    down) "${compose[@]}" down ;;
    reset)
        "${compose[@]}" down -v
        rm -rf "$DEV_SOURCES_DIR"
        ;;
    *)
        sed -n '2,10p' "$0" >&2
        exit 2
        ;;
esac
