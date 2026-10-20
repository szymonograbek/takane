---
name: verify-stremio-tv
description: Drive Takane (this repo's Stremio app) to prove a change works. tvOS app in the "Stremio Apple TV" simulator through agent-device with remote presses, plus a scripted end-to-end smoke journey on macOS and tvOS. Use after changing app/, core/ or scripts/, before claiming playback, add-on install, stream lookup or continue-watching behavior works.
---

# Verify Takane

The app is a SwiftUI client over stremio-core (Rust, `core/`) with AetherEngine playback. It ships as a macOS app and a tvOS app built from `app/Shared` (screens in `app/Shared/UI`) plus one platform folder each for assets. The feature map in `features/` lists what a user can do.

Two harnesses:

- **tvOS UI drive.** `.claude/skills/verify-stremio-tv/scripts/tv.sh` (below). Drives the real tvOS UI with remote presses through `agent-device`. This is the user path; prefer it.
- **Smoke journey.** `scripts/smoke.sh [--tvos] [type/id]`. Launches the app in a mode that runs install → streams → play 10 s → pause → continue watching by itself and writes `smoke-result.json`. It sends the same feature events the UI buttons send, but drives no UI. Use it for macOS (no UI driver is set up there) and as a fast regression check on both platforms. It is not proof that a UI control works. With `STREMIO_SMOKE_SUBTITLES_ADDON_URL` set (environment or `.env.smoke`) it also installs that subtitles add-on, waits for its files for the stream and plays the first one; `smoke-result.json` then lists subtitle counts per add-on, the first labels and the track played.

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

Stable handles (SwiftUI `accessibilityIdentifier`, in `app/Shared/UI`). Tab bar items have no identifier; `focus` matches them by their SF Symbol name (`house`, `books.vertical`, `calendar`, `magnifyingglass`, `gearshape`).

| Id | Element |
|---|---|
| `welcome.signIn`, `welcome.continue` | Welcome buttons. `launch` clears the onboarding flag, so every run starts here |
| `signIn.code` | the link code on Sign In with Stremio |
| `signIn.password`, `signIn.email`, `signIn.passwordField`, `signIn.submit`, `signIn.error` | email sign-in |
| `home.screen` | Home's scroll view |
| `hero.play`, `hero.details` | hero buttons (Play only for movies and live channels) |
| `continueWatching.item` | each Continue Watching card; label `<name>, <time left>`, or `<name>, New episode` for a show with new episodes |
| `poster.<imdb id>` | each poster in Home rows and search results |
| `search.recent`, `search.clearRecent` | on Search before anything is typed: each recent search (label is the query; selecting it runs it) and Clear, which confirms before forgetting them all |
| `search.genre` | on Search before anything is typed: each genre in the Movies by Genre and Series by Genre rows; label is the genre, selecting it opens its grid |
| `genre.screen` | a genre's grid of posters (`poster.<imdb id>`), or its empty or error state with Try Again |
| `library.screen` | the Library tab: the type and sort menus above a grid of posters (`poster.<imdb id>`), or its empty state |
| `library.type`, `library.sort` | the Library filter buttons, labeled with the current choice (`All Types`, `Series`; `Sort: Recently Watched`, `Sort: Name`). Selecting one opens a Show or Sort By list below it with the current choice focused; up and down move in it, a choice or Menu closes it with the button focused, and up from its first row closes it too. The rows have no identifier; match them by label. A long press on a poster offers Remove from Library |
| `calendar.screen` | the Calendar tab: one row per day of upcoming episodes, titled "Today", "Tomorrow", "In 3 days (Friday)", or its empty or error state |
| `upcoming.<video id>` | each upcoming episode card, such as `upcoming.tt0364845:24:3`; selecting it opens the show's details |
| `details.library` | Add to Library, or In Library once added; selecting it toggles |
| `details.resume`, `details.play`, `episode.<id>` | Details actions; focus lands on Resume, else Play, on open and when the details load |
| `details.description`, `details.descriptionDone` | the description, cut to four lines; selecting it opens the full text, which Done or Back closes |
| `details.back` | Go Back on a series whose add-ons list no episodes |
| `loading.cancel` | Cancel under the spinner while Details or Streams loads; it goes back |
| `streams.row` | each playable stream (unplayable ones are not listed); focus lands on the first once one arrives |
| `player.status` | the player container; label `H:MM:SS / H:MM:SS · <phase> · <w>×<h> · <decoder>`, such as `libavcodec H264 (SW)` |
| `player.subtitle` | the text subtitle on screen; its label is the cue's text. Bitmap subtitles have no element |
| `player.progress` | the player's progress bar; focus it with up from the buttons, then tap or hold left and right |
| `player.live` | the LIVE badge that replaces the progress bar, times and skip buttons on a live channel (type `tv`) |
| `player.playPause`, `player.subtitles`, `player.audio`, `player.speed`, `player.skip` | player controls |
| `player.option` | each row in the open subtitles, audio or speed panel, including an add-on's row on the subtitles page that opens its files |
| `player.upNext.play`, `player.upNext.dismiss` | the up next card's Play Now (Choose Stream when the next episode has no matching stream) and Cancel; the card shows near an episode's end while the controls are hidden, with Play Now focused |
| `settings.account`, `settings.addons`, `settings.playback`, `settings.subtitles`, `settings.about` | Settings rows |
| `playback.audioLanguage`, `playback.secondAudioLanguage`, `playback.seekStep`, `playback.upNextNotice`, `playback.autoplayNext`, `playback.hideSpoilers` | Settings › Playback rows; Second Language shows only when an audio language is set; Skip Interval opens a list of 5, 10, 15 and 30 seconds; Up Next Card opens a list of Off and 10, 20, 35 and 60 seconds before the end; Autoplay Next Episode and Hide Spoilers are toggles |
| `subtitles.language`, `subtitles.secondLanguage` | Settings › Subtitles language rows; Second Language shows only when a language is set |
| `subtitles.size`, `subtitles.font`, `subtitles.bold`, `subtitles.fileStyling`, `subtitles.textColor`, `subtitles.outlineColor`, `subtitles.backgroundColor`, `subtitles.opacity`, `subtitles.position`, `subtitles.reset` | Settings › Subtitles style rows; each but the Bold and Use File Styling toggles and Reset opens a list of choices |
| `subtitles.preview` | the live preview on Settings › Subtitles and on each style list, where it shows the focused choice |
| `addons.install`, `addons.manifestURL`, `addons.status`, `addons.row` | Settings › Add-ons |

Feature recipes with exact steps: `features/README.md`.

## Evidence

`$T evidence <name>` writes to `build/verify/<run-id>/`: `<name>.png` (simulator screenshot, 3840×2160), `<name>.ax.jsonl` (raw accessibility tree, one JSON node per line), and `app.log` (Swift, Rust and AetherEngine logs; long tokens are masked). Capture before and after each user action that matters.

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
- The simulator plays on the software route (`libavcodec … (SW)`). Hardware decoding, HDR, Dolby Vision and passthrough need a real Apple TV.
