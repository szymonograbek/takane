#!/usr/bin/env bash
# Drives the tvOS app in the "Stremio Apple TV" simulator through agent-device, with a
# throwaway core profile per run. Evidence goes to build/verify/<run-id>/ and survives cleanup.
#
#   tv.sh launch                     build, install, open with a fresh profile at Welcome, wait until ready
#   tv.sh doctor                     read-only health check of the current run
#   tv.sh focus <id> <dir> [max]     press <dir> (up|down|left|right) until element <id> has focus
#   tv.sh select                     press the remote's select button
#   tv.sh type <id> <dir> <text>     focus <id> via <dir>, type <text>, confirm with the keyboard's done
#   tv.sh type-env <id> <dir> <VAR>  same, text read from env var or .env.smoke (keeps secrets out of argv history)
#   tv.sh wait-text <text> [secs]    wait until <text> appears in the accessibility tree
#   tv.sh text <id>                  print the text of element <id>
#   tv.sh focused                    print the id (or label) of the focused element
#   tv.sh remote <button>            press a remote button: up|down|left|right|select|menu|home
#   tv.sh evidence <name>            save screenshot, raw accessibility snapshot and app log under the run dir
#   tv.sh cleanup                    close the session, quit the app, delete the profile (keeps evidence)
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
bundle_id=com.ograbek.stremio-tv
state="$root/build/verify/current.env"
session=stremio-tv-verify

load_state() {
    [[ -f "$state" ]] || { echo "no active run; run: tv.sh launch" >&2; exit 1; }
    source "$state"
}

ad() { agent-device "$@" --session "$session"; }

# Queries read raw snapshots: the normal snapshot refuses screens where a list row hangs
# past its scroll view ("node escaped its cumulative clip"), which the stream list always does.
#   query focused            identifier (or label) of the focused element
#   query text <id>          label of the first element with accessibility identifier <id>
#   query has <text>         exit 0 if any element's label equals <text>
#   query ref <id>           @ref of element <id> in this snapshot, for commands such as fill
#   query ready              exit 0 once core started and a screen shows (Welcome or the tabs)
query() {
    ad snapshot -i --raw 2>/dev/null | python3 -I -c '
import json, sys
mode, arg = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
nodes = [json.loads(line) for line in sys.stdin if line.startswith("{")]
if mode == "focused":
    hit = next((n for n in nodes if n.get("focused")), None)
    print(hit and (hit.get("identifier") or hit.get("label") or ""))
elif mode == "text":
    hit = next((n for n in nodes if n.get("identifier") == arg), None)
    print(hit["label"] if hit else "")
    sys.exit(0 if hit else 1)
elif mode == "ref":
    hit = next((n for n in nodes if n.get("identifier") == arg), None)
    print("@" + hit["ref"] if hit else "")
    sys.exit(0 if hit else 1)
elif mode == "has":
    sys.exit(0 if any(n.get("label") == arg for n in nodes) else 1)
elif mode == "ready":
    sys.exit(0 if any(n.get("identifier") in ("welcome.continue", "home.screen") for n in nodes) else 1)
' "$@"
}

case "${1:-}" in
launch)
    [[ ! -f "$state" ]] || { echo "a run is active ($state); run: tv.sh cleanup" >&2; exit 1; }
    "$root/scripts/build-app.sh" tvos-sim >/dev/null
    udid="$("$root/scripts/tvos-simulator.sh")"
    xcrun simctl install "$udid" "$root/build/DerivedData/Build/Products/Debug-appletvsimulator/StremioTV.app"
    run_id="$(date +%Y%m%d-%H%M%S)"
    data="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
    storage="$data/tmp/verify-$run_id"
    run_dir="$root/build/verify/$run_id"
    mkdir -p "$run_dir"
    # Each run starts at Welcome, as on a first launch.
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    plutil -remove onboardingFinished "$data/Library/Preferences/$bundle_id.plist" >/dev/null 2>&1 || true
    printf 'udid=%q\nrun_id=%q\nstorage=%q\nrun_dir=%q\nlog=%q\n' \
        "$udid" "$run_id" "$storage" "$run_dir" "$data/Library/Caches/Logs/app.log" > "$state"
    ad open "$bundle_id" --platform ios --target tv --udid "$udid" --relaunch \
        --launch-args -STREMIO_STORAGE_DIRECTORY --launch-args "$storage" >/dev/null
    for _ in $(seq 1 100); do
        query ready && break
        sleep 0.3
    done
    "$0" doctor
    ;;
doctor)
    load_state
    ok=true
    xcrun simctl list devices booted | grep -q "$udid" && echo "simulator booted: $udid" || { echo "simulator NOT booted"; ok=false; }
    query ready && echo "app foreground, core ready" || { echo "neither Welcome nor Home is visible"; ok=false; }
    # Storage paths are partly masked in the log, so match on the run id.
    grep -q "starting bridge, storage at .*verify-$run_id" "$log" && echo "profile: fresh (verify-$run_id)" || { echo "app is NOT using this run's profile"; ok=false; }
    echo "evidence dir: $run_dir"
    $ok
    ;;
focus)
    load_state
    target="$2" direction="$3" max="${4:-8}"
    for _ in $(seq 0 "$max"); do
        [[ "$(query focused)" == "$target" ]] && { echo "focused $target"; exit 0; }
        ad tv-remote press "$direction" >/dev/null
    done
    echo "could not focus $target pressing $direction; focused now: $(query focused)" >&2
    exit 1
    ;;
select)
    load_state
    ad tv-remote press select >/dev/null
    ;;
type|type-env)
    load_state
    target="$2" direction="$3"
    if [[ "$1" == type-env ]]; then
        [[ -n "${!4:-}" || ! -f "$root/.env.smoke" ]] || source "$root/.env.smoke"
        text="${!4:?env var $4 is empty}"
    else
        text="$4"
    fi
    "$0" focus "$target" "$direction"
    # Filling the focused field opens the tvOS keyboard with the text entered. The ref comes
    # from a raw snapshot because selector lookups fail while the stream list is on screen.
    ad fill "$(query ref "$target")" "$text" >/dev/null
    # The tvOS keyboard's done button sits below the keys.
    for _ in $(seq 1 6); do
        [[ "$(query focused)" == "done" ]] && break
        ad tv-remote press down >/dev/null
    done
    ad tv-remote press select >/dev/null
    echo "typed ${#text} chars into $target"
    ;;
wait-text)
    load_state
    text="$2" secs="${3:-30}"
    for _ in $(seq 1 $((secs * 2))); do
        if query has "$text"; then
            echo "found: $text"
            exit 0
        fi
        sleep 0.5
    done
    echo "timed out after ${secs}s waiting for: $text" >&2
    exit 1
    ;;
text)
    load_state
    query text "$2"
    ;;
focused)
    load_state
    query focused
    ;;
remote)
    load_state
    ad tv-remote press "$2" >/dev/null
    ;;
evidence)
    load_state
    name="$2"
    xcrun simctl io "$udid" screenshot "$run_dir/$name.png" >/dev/null 2>&1
    ad snapshot -i --raw > "$run_dir/$name.ax.jsonl" 2>&1 || true
    cp "$log" "$run_dir/app.log"
    echo "saved $run_dir/$name.png, $name.ax.jsonl, app.log"
    ;;
cleanup)
    [[ -f "$state" ]] || { echo "nothing to clean"; exit 0; }
    source "$state"
    [[ -f "$log" ]] && cp "$log" "$run_dir/app.log"
    agent-device close "$bundle_id" --session "$session" >/dev/null 2>&1 || true
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    rm -rf "$storage"
    rm -f "$state"
    echo "cleaned up; evidence kept in $run_dir"
    ;;
*)
    sed -n '2,17p' "$0"
    exit 1
    ;;
esac
