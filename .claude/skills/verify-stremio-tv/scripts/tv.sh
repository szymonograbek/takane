#!/usr/bin/env bash
# Drives the tvOS app in the "Stremio Apple TV" simulator through agent-device, with a
# throwaway core profile per run. Evidence goes to build/verify/<run-id>/ and survives cleanup.
#
#   tv.sh launch [--account] [-STREMIO_KEY value]...
#                                    build, install, open with a fresh profile at Welcome, wait until ready;
#                                    --account keeps one profile across runs, so a sign-in survives; each
#                                    -STREMIO_KEY value pair is passed to the app as a launch option
#   tv.sh sign-in                    from Welcome, sign in with STREMIO_TEST_EMAIL and STREMIO_TEST_PASSWORD
#                                    (env or .env.smoke); launch --account runs it when the profile is signed out
#   tv.sh doctor                     read-only health check of the current run
#   tv.sh trakt-check                pass once Trakt shows a play or pause from this run (needs launch --account
#                                    and Trakt linked on the account)
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
bundle_id=com.ograbek.takane
state="$root/build/verify/current.env"
session=stremio-tv-verify
# Secrets live in the main checkout's .env.smoke; a worktree may keep its own.
env_file="$root/.env.smoke"
[[ -f "$env_file" ]] || env_file="$(cd "$(git -C "$root" rev-parse --git-common-dir)/.." && pwd)/.env.smoke"

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
#   query ready              exit 0 once core started and a screen shows (Welcome or Home)
#   query foreground         exit 0 if Takane is foreground with a readable tree, on any screen
#                            (not "focused": the player with its controls hidden focuses nothing)
query() {
    ad snapshot -i --raw 2>/dev/null | python3 -I -c '
import json, sys
mode, arg = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
nodes = [json.loads(line) for line in sys.stdin if line.startswith("{")]
if mode == "focused":
    # A focused list row is a Cell whose identifier sits on a Button inside it
    # (images inside carry their SF Symbol name as identifier; skip those).
    # Nodes come in tree order, so descendants follow their ancestor.
    hit = next((n for n in nodes if n.get("focused")), None)
    if hit and not hit.get("identifier"):
        inside = {hit["index"]}
        for n in nodes[nodes.index(hit) + 1:]:
            if n.get("parentIndex") not in inside:
                continue
            if n.get("identifier") and n.get("type") != "Image":
                hit = n
                break
            inside.add(n["index"])
    print(hit and (hit.get("identifier") or hit.get("label") or ""))
elif mode == "text":
    hit = next((n for n in nodes if n.get("identifier") == arg), None)
    print(hit.get("label", "") if hit else "")
    sys.exit(0 if hit else 1)
elif mode == "ref":
    hit = next((n for n in nodes if n.get("identifier") == arg), None)
    print("@" + hit["ref"] if hit else "")
    sys.exit(0 if hit else 1)
elif mode == "has":
    sys.exit(0 if any(n.get("label") == arg for n in nodes) else 1)
elif mode == "ready":
    sys.exit(0 if any(n.get("identifier") in ("welcome.continue", "home.screen") for n in nodes) else 1)
elif mode == "foreground":
    sys.exit(0 if any(n.get("type") == "Application" and n.get("label") == "Takane" for n in nodes) else 1)
' "$@"
}

case "${1:-}" in
launch)
    [[ ! -f "$state" ]] || { echo "a run is active ($state); run: tv.sh cleanup" >&2; exit 1; }
    shift
    account=false
    [[ "${1:-}" == --account ]] && { account=true; shift; }
    options=()
    while (( $# >= 2 )) && [[ "$1" == -STREMIO_* ]]; do
        options+=(--launch-args "$1" --launch-args "$2")
        shift 2
    done
    (( $# == 0 )) || { echo "launch options are -STREMIO_KEY value pairs, got: $*" >&2; exit 1; }
    "$root/scripts/build-app.sh" tvos-sim >/dev/null
    udid="$("$root/scripts/tvos-simulator.sh")"
    xcrun simctl install "$udid" "$root/build/DerivedData/Build/Products/Debug-appletvsimulator/Takane.app"
    run_id="$(date +%Y%m%d-%H%M%S)"
    data="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
    # The account profile holds a Stremio auth key. It stays in the simulator, outside tmp.
    if $account; then storage="$data/Library/verify-account"; else storage="$data/tmp/verify-$run_id"; fi
    run_dir="$root/build/verify/$run_id"
    mkdir -p "$run_dir"
    # Each run starts at Welcome, as on a first launch.
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    plutil -remove onboardingFinished "$data/Library/Preferences/$bundle_id.plist" >/dev/null 2>&1 || true
    printf 'udid=%q\nrun_id=%q\nstarted=%q\naccount=%q\nstorage=%q\nrun_dir=%q\nlog=%q\n' \
        "$udid" "$run_id" "$(date +%s)" "$account" "$storage" "$run_dir" "$data/Library/Caches/Logs/app.log" > "$state"
    ad open "$bundle_id" --platform ios --target tv --udid "$udid" --relaunch \
        --launch-args -STREMIO_STORAGE_DIRECTORY --launch-args "$storage" \
        --launch-args -STREMIO_MUTE --launch-args 1 ${options[@]+"${options[@]}"} >/dev/null
    for _ in $(seq 1 100); do
        query ready && break
        sleep 0.3
    done
    query ready || { echo "neither Welcome nor Home appeared" >&2; exit 1; }
    if $account && ! query text home.screen >/dev/null; then "$0" sign-in; fi
    "$0" doctor
    ;;
doctor)
    load_state
    ok=true
    xcrun simctl list devices booted | grep -q "$udid" && echo "simulator booted: $udid" || { echo "simulator NOT booted"; ok=false; }
    query foreground && echo "app foreground" || { echo "app NOT foreground, or its tree is unreadable"; ok=false; }
    # Storage paths are partly masked in the log, so match on the run id.
    profile="$(basename "$storage")"
    grep -q "starting bridge, storage at .*$profile" "$log" && echo "profile: $profile" || { echo "app is NOT using this run's profile"; ok=false; }
    echo "evidence dir: $run_dir"
    $ok
    ;;
sign-in)
    load_state
    "$0" focus welcome.signIn down >/dev/null
    ad tv-remote press select >/dev/null
    "$0" focus signIn.password down >/dev/null
    ad tv-remote press select >/dev/null
    for _ in $(seq 1 20); do query text signIn.email >/dev/null && break; sleep 0.5; done
    "$0" type-env signIn.email up STREMIO_TEST_EMAIL >/dev/null
    # Done on the email keyboard opens the password keyboard: type there, then press its done.
    [[ -n "${STREMIO_TEST_PASSWORD:-}" || ! -f "$env_file" ]] || source "$env_file"
    for _ in $(seq 1 20); do [[ "$(query focused)" == "done" ]] && break; sleep 0.5; done
    ad type "${STREMIO_TEST_PASSWORD:?env var STREMIO_TEST_PASSWORD is empty}" >/dev/null
    for _ in $(seq 1 6); do
        [[ "$(query focused)" == "done" ]] && break
        ad tv-remote press down >/dev/null
    done
    ad tv-remote press select >/dev/null
    "$0" focus signIn.submit down >/dev/null
    ad tv-remote press select >/dev/null
    for _ in $(seq 1 120); do
        query text home.screen >/dev/null && { echo "signed in"; exit 0; }
        error="$(query text signIn.error)" && { echo "sign-in failed: $error" >&2; exit 1; }
        sleep 0.5
    done
    echo "not signed in after 60 s; focused: $(query focused)" >&2
    exit 1
    ;;
trakt-check)
    load_state
    $account || { echo "trakt-check needs launch --account" >&2; exit 1; }
    # The token on the Stremio account was issued to Stremio's Trakt app, so only its client id
    # (public, in the redirect from strem.io/trakt/auth) works with it. Reads only.
    python3 -I - "$storage/profile.json" "$started" <<'PY'
import datetime, json, sys, time, urllib.request
profile, started = sys.argv[1], int(sys.argv[2])
trakt = json.load(open(profile))["auth"]["user"].get("trakt")
if not trakt:
    sys.exit("the account has no Trakt link")
headers = {
    "Authorization": "Bearer " + trakt["access_token"],
    "trakt-api-version": "2",
    "trakt-api-key": "0e861f52c7365efe6da5ea3e2e6641b8d25d87aca3133e8d4f7dc8487368d14b",
    "User-Agent": "takane-verify",
}
def since_start(path, field):
    request = urllib.request.Request("https://api.trakt.tv" + path, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        items = json.load(response)
    at = lambda item: datetime.datetime.fromisoformat(item[field].replace("Z", "+00:00")).timestamp()
    return [item for item in items if at(item) >= started]
for _ in range(10):
    hits = since_start("/sync/playback?limit=10", "paused_at") + since_start("/sync/history?limit=10", "watched_at")
    if hits:
        for item in hits:
            title = (item.get("show") or item.get("movie") or {}).get("title")
            episode = item.get("episode") or {}
            where = f" S{episode['season']}E{episode['number']}" if episode else ""
            state = f"paused at {item['progress']:.1f}%" if "progress" in item else "watched"
            print(f"trakt: {title}{where} {state}")
        sys.exit(0)
    time.sleep(3)
sys.exit("Trakt shows nothing played since this run started")
PY
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
        [[ -n "${!4:-}" || ! -f "$env_file" ]] || source "$env_file"
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
    $account || rm -rf "$storage"
    rm -f "$state"
    echo "cleaned up; evidence kept in $run_dir"
    ;;
*)
    sed -n '2,17p' "$0"
    exit 1
    ;;
esac
