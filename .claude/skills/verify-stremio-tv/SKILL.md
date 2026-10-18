---
name: verify-stremio-tv
description: Drive the Stremio TV app (this repo) to prove a change works. tvOS app in the "Stremio Apple TV" simulator through agent-device with remote presses, plus a scripted end-to-end smoke journey on macOS and tvOS. Use after changing app/, core/ or scripts/, before claiming playback, add-on install, stream lookup or continue-watching behavior works.
---

# Verify Stremio TV

The app is a SwiftUI client over stremio-core (Rust, `core/`) with mpv playback. It ships as a macOS app and a tvOS app built from `app/Shared` plus one platform folder each. Every screen today is a diagnostic placeholder; the feature map in `features/` lists what a user can do.

Two harnesses:

- **tvOS UI drive.** `.claude/skills/verify-stremio-tv/scripts/tv.sh` (below). Drives the real tvOS UI with remote presses through `agent-device`. This is the user path; prefer it.
- **Smoke journey.** `scripts/smoke.sh [--tvos] [type/id]`. Launches the app in a mode that runs install → streams → play 10 s → pause → continue watching by itself and writes `smoke-result.json`. It calls the same `CoreStore` workflows the UI buttons call, but no UI. Use it for macOS (no UI driver is set up there) and as a fast regression check on both platforms. It is not proof that a UI control works.

Both need the debrid add-on URL: `STREMIO_SMOKE_ADDON_URL` in the environment or in the git-ignored `.env.smoke` at the repo root (`STREMIO_SMOKE_ADDON_URL=https://…/manifest.json`). It holds credentials. Never print it, commit it, or paste it into evidence.

## Launch

```bash
T=.claude/skills/verify-stremio-tv/scripts/tv.sh
$T launch
```

`launch` builds the tvOS simulator app (`scripts/build-app.sh tvos-sim`), boots or creates the "Stremio Apple TV" simulator (`scripts/tvos-simulator.sh`), installs, and opens the app through agent-device session `stremio-tv-verify`. It passes `-STREMIO_STORAGE_DIRECTORY <container>/tmp/verify-<run-id>`, so core starts on an empty profile (default add-ons only). Ready means `doctor` passes: the core status reads Ready and the log shows the app opened this run's profile. `launch` runs `doctor` itself and exits non-zero when not ready.

One run at a time: `launch` refuses while `build/verify/current.env` exists. Never drive a session you did not launch.

First build after a clean checkout compiles the Rust bridge for three targets (a few minutes). The tvOS simulator runtime must be installed (`xcodebuild -downloadPlatform tvOS`).

## Doctor

```bash
$T doctor
```

Read-only. Checks the simulator is booted, the app is foreground with `core.ready` visible, and the app log shows `starting bridge, storage at …verify-<run-id>` (proves this run's fresh profile, not the user's). Prints the evidence directory. Run it first whenever anything looks off.

## Drive

tvOS is focus-driven: move focus with the remote, then press select. Tapping an unfocused element fails (`tap is supported on tvOS only when the requested point is inside the focused element`).

```bash
$T focus <accessibility-id> <up|down|left|right> [max]   # press until <id> has focus
$T select                                                # remote select
$T type <id> <dir> <text>                                # focus, type, confirm keyboard "done"
$T type-env <id> <dir> STREMIO_SMOKE_ADDON_URL           # same, text from env/.env.smoke
$T text <id>                                             # read an element's text
$T focused                                               # id (or label) of the focused element
$T wait-text "<exact label>" [secs]
$T remote <menu|left|right|up|down|home>
$T evidence <name>
```

Stable handles (SwiftUI `accessibilityIdentifier`, in `app/tvOS/RootView.swift`):

| Id | Element |
|---|---|
| `core.ready` | "Ready" core status |
| `addons.manifestURL` | add-on manifest URL field (focused at launch) |
| `addons.status` | install result text |
| `streams.itemID` | IMDb id field (default `tt0111161`) |
| `streams.findMovie`, `streams.findSeries` | lookup buttons |
| `streams.status` | "<n> streams from <m> add-ons" or the error |
| `streams.row` | each playable stream row (a button) |
| `streams.unplayableRow` | torrent/external/other rows: plain text, never focusable |
| `player.status` | full-screen player line: `H:MM:SS / H:MM:SS · <phase> · <w>×<h> · hwdec <name>` |
| `continueWatching.item` | each continue-watching line: `<name> · <offset>s / <duration>s` |

Feature recipes with exact steps: `features/README.md`.

## Evidence

`$T evidence <name>` writes to `build/verify/<run-id>/`: `<name>.png` (simulator screenshot, 3840×2160), `<name>.ax.jsonl` (raw accessibility tree, one JSON node per line), and `app.log` (Swift, Rust and mpv logs; long tokens are masked). Capture before and after each user action that matters.

Proof standards:

- Drive the UI path in `features/`, not the smoke mode, when claiming a UI control works.
- Pair each action with the resulting state: the screen and the element text after it.
- Verify side effects, not only the screen: core persists to `<run storage>/profile.json` (installed add-ons) and `library_recent.json` (progress). Read them before cleanup (`source build/verify/current.env; ls "$storage"`).
- Playback proof is the `player.status` line advancing over time plus the screenshot showing video, not the row press alone.
- Network goes to the real add-ons and debrid. There are no mocks.

Smoke journey evidence: `smoke-result.json` (pass flag, streams, video size, decoder, audio output, render size, continue-watching offset) next to the app log. macOS: `~/Library/Logs/com.ograbek.stremio-tv/`, plus `smoke-frame.png`. tvOS: the app container's `Library/Caches/Logs/`, plus `smoke-screen.png`. `scripts/smoke.sh` prints the paths.

## Cleanup

```bash
$T cleanup
```

Copies the final app log into the run directory, closes the agent-device session, terminates the app it launched, deletes the run's profile directory and `build/verify/current.env`. It never deletes `build/verify/<run-id>/` and leaves the simulator booted (it is reused across runs). Run it after every run, including failed ones. The smoke script uses its own throwaway profile and cleans up after itself.

## Helpers

- `scripts/tv.sh` (this skill): every command above; `tv.sh` with no arguments prints usage.
- `scripts/build-app.sh [macos|tvos-sim|tvos-device]` (repo): build; logs in `build/xcodebuild-<platform>.log`.
- `scripts/smoke.sh [--tvos] [type/id]` (repo): scripted journey; exit 0 = pass.
- `scripts/tvos-simulator.sh` (repo): prints the simulator UDID, creating and booting it.

## Limits

- macOS UI is not driven by this skill. agent-device's macOS backend uses XCTest automation, which asks for a one-time system permission. Use `scripts/smoke.sh` on macOS until that permission is granted and a recipe is proven.
- agent-device's tvOS remote has no play/pause button. The player maps select to pause/resume, so use `select`.
- agent-device's normal `snapshot`/`is`/`get` fail once the stream list is on screen ("node escaped its cumulative clip"). `tv.sh` reads raw snapshots for that reason; do the same in ad-hoc commands (`agent-device snapshot -i --raw --session stremio-tv-verify`).
- The simulator decodes video in software and cannot read frames back from mpv (that crashes its Metal driver). Hardware decoding, HDR and passthrough need a real Apple TV.
