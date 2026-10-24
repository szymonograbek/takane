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

`launch` builds the tvOS simulator app (`scripts/build-app.sh tvos-sim`), boots or creates the "Stremio Apple TV" simulator (`scripts/tvos-simulator.sh`), installs, and opens the app through agent-device session `stremio-tv-verify`. It passes `-STREMIO_STORAGE_DIRECTORY <container>/tmp/verify-<run-id>`, so core starts on an empty profile (default add-ons only), and `-STREMIO_MUTE 1`, so playback is silent. Ready means Welcome shows and `doctor` passes. `launch` waits for Welcome, runs `doctor` itself and exits non-zero when not ready.

Further `-STREMIO_KEY value` pairs after `launch` (or `launch --account`) reach the app as launch options (`LaunchOptions`). `$T launch -STREMIO_FIXTURE_SOURCE 1` lists the debug-only fixture source add-on: a Fixture row on Home with Sintel and Beach Day, streamed from the dev WebDAV server with Basic auth. Start that server first with `scripts/dev-sources.sh up`. `$T launch -STREMIO_SOURCES '[{"kind":"jellyfin","url":"http://localhost:8196","username":"takane","password":"takane-dev"},{"kind":"webdav","url":"http://localhost:8197","username":"takane","password":"takane-dev"}]'` adds both dev servers as sources (`kind` is `jellyfin` or `webdav`) through the app's own sign-in; they stay in the simulator's Keychain across runs and `cleanup`, and the option skips any already stored. Settings › Sources adds, renames and removes sources through the UI instead (`features/sources.md`); `xcrun simctl keychain "$(scripts/tvos-simulator.sh)" reset` clears them.

`$T relaunch` quits the app and opens it again on the run's profile, as after a reboot: Home with the same continue watching, stream and subtitle choices, and the sources from the Keychain. Use it to prove something survives a relaunch. The app log starts over, so capture evidence before relaunching.

For anything that needs a Stremio account (Trakt, sync), run `$T launch --account`. It keeps one profile, `Library/verify-account` in the simulator's app container, across runs and `cleanup`. When that profile is signed out, it signs in through the email screen (`$T sign-in`) with `STREMIO_TEST_EMAIL` and `STREMIO_TEST_PASSWORD` from the environment or `.env.smoke`. In a worktree without its own `.env.smoke`, it reads the main checkout's. Never print these or paste them into evidence. The profile holds the account's auth key, and the debug `app.log` does too.

One run at a time: `launch` refuses while `build/verify/current.env` exists. Never drive a session you did not launch.

First build after a clean checkout compiles the Rust bridge for three targets (a few minutes). The tvOS simulator runtime must be installed (`xcodebuild -downloadPlatform tvOS`).

## Doctor

```bash
$T doctor
```

Read-only. Checks the simulator is booted, Takane is the foreground app with a readable accessibility tree (on any screen, the player included), and the app log shows `starting bridge, storage at …verify-<run-id>` (proves this run's fresh profile, not the user's). Prints the evidence directory. Run it first whenever anything looks off. After agent-device reports `main thread execution timed out` or `still finishing a previous command`, doctor fails until the runner drains; wait about 20 s and run it again. Menu on the tab bar of a tab's root screen sends the app to the background; `agent-device open com.ograbek.takane --platform ios --target tv --udid <udid> --session stremio-tv-verify` brings it back with its state.

## Drive

tvOS is focus-driven: move focus with the remote, then press select. Tapping an unfocused element fails (`tap is supported on tvOS only when the requested point is inside the focused element`).

```bash
$T focus <accessibility-id> <up|down|left|right> [max]   # press until <id> has focus
$T select                                                # remote select
$T type <id> <dir> <text>                                # focus, type, confirm keyboard "done"
$T type-env <id> <dir> STREMIO_SMOKE_ADDON_URL           # same, text from env/.env.smoke
$T text <id>                                             # read an element's text
$T focused                                               # id of the focused element (a list row's inner id), else its label
$T wait-text "<exact label>" [secs]
$T remote <menu|left|right|up|down|home>
$T evidence <name>
```

Stable handles (SwiftUI `accessibilityIdentifier`, in `app/Shared/UI`). Tab bar items have no identifier; `focus` matches them by their SF Symbol name (`house`, `books.vertical`, `calendar`, `magnifyingglass`, `gearshape`).

| Id | Element |
|---|---|
| `welcome.signIn`, `welcome.continue` | Welcome buttons. `launch` clears the onboarding flag, so every run starts here |
| `signIn.code` | the link code on Sign In |
| `signIn.password`, `signIn.email`, `signIn.passwordField`, `signIn.submit`, `signIn.error` | email sign-in |
| `home.screen` | Home's scroll view |
| `hero.play`, `hero.details` | hero buttons (Play only for movies and live channels) |
| `continueWatching.item` | each Continue Watching card; label `<name>, <time left>`, or `<name>, New episode` for a show with new episodes |
| `poster.<imdb id>` | each poster in Home rows and search results |
| `shelf.seeAll` | See All, the last card of each source's row on Home (which shows the source's 20 newest titles); selecting it pushes Library (`push library(<source>)`) with that source picked |
| `search.recent`, `search.clearRecent` | on Search before anything is typed: each recent search (label is the query; selecting it runs it) and Clear, which confirms before forgetting them all |
| `search.genre` | on Search before anything is typed: each genre in the Movies by Genre and Series by Genre rows; label is the genre, selecting it opens its grid |
| `genre.screen` | a genre's grid of posters (`poster.<imdb id>`), or its empty or error state with Try Again |
| `library.screen` | the Library tab, or Library pushed from See All with its own title: the menus above a grid of posters (`poster.<imdb id>`), or its empty state |
| `library.picker` | shown once a source exists: Your Library or a source's name. Selecting it opens a Library list with Your Library, then each source by name. A source lists all its titles, Recently Added first, 100 at a time as you scroll |
| `library.type`, `library.sort` | the Library filter buttons, labeled with the current choice (`All Types`, `Series`; `Sort: Recently Watched`, `Sort: Name`; for a source `Sort: Recently Added`, `Sort: Name`, `Sort: Year`, and types All Types, Movies, Series). Selecting one opens a Show or Sort By list below it with the current choice focused; up and down move in it, a choice or Menu closes it with the button focused, and up from its first row closes it too. The rows have no identifier; match them by label. A long press on a poster offers Remove from Library |
| `calendar.screen` | the Calendar tab: one row per day of upcoming episodes, titled "Today", "Tomorrow", "In 3 days (Friday)", or its empty or error state |
| `upcoming.<video id>` | each upcoming episode card, such as `upcoming.tt0364845:24:3`; selecting it opens the show's details |
| `details.library` | Add to Library, or In Library once added; selecting it toggles |
| `details.like`, `details.love` | icon-only Like (thumbs up) and Love (heart) after the library button, shown only when signed in and the title is ratable; the selected one is filled and has the Selected trait. Selecting it clears the rating; selecting the other switches |
| `details.resume`, `details.play`, `episode.<id>` | Details actions; focus lands on Resume, else Play, on open and when the details load |
| `details.description`, `details.descriptionDone` | the description, cut to four lines; selecting it opens the full text, which Done or Back closes |
| `details.back` | Go Back on a series whose add-ons list no episodes |
| `loading.cancel` | Cancel under the spinner while Details or Streams loads; it goes back |
| `streams.row` | each playable stream (unplayable ones are not listed); focus lands on the first once one arrives |
| `streams.offer` | signed out, in builds with `RAPIDAPI_KEY`: each service under Other Services below the streams, label its name and how it offers the title (`Prime Video`, `Rent 9.99 PLN · Buy 39.99 PLN`); focus lands on the first when no stream is listed. Selecting one opens its link, or an alert when nothing on the device opens it (always in the simulator) |
| `player.status` | the player container; label `H:MM:SS / H:MM:SS · <phase> · <w>×<h> · <decoder>`, such as `libavcodec H264 (SW)` |
| `player.subtitle` | the text subtitle on screen; its label is the cue's text. Bitmap subtitles have no element |
| `player.progress` | the player's progress bar; focus it with up from the buttons, then tap or hold left and right. Its value is the chapter at the playhead (`Chapter 2`, or the file's title for it), empty when the stream has no chapters; read it from a raw snapshot (`"value"`) |
| `player.live` | the LIVE badge that replaces the progress bar, times and skip buttons on a live channel (type `tv`) |
| `player.playPause`, `player.subtitles`, `player.audio`, `player.speed` | player controls; back and forward have no identifier (`focused` prints their symbol, such as `goforward.30`) |
| `player.skip` | Skip Intro, Recap, Credits or Preview: shows while the controls are hidden during a segment with skip data (Stremio Premium, IntroDB or SkipDB) |
| `player.option` | each row in the open subtitles, audio or speed panel, including an add-on's row on the subtitles page that opens its files |
| `player.subtitle.second` | the second subtitle on screen, above `player.subtitle`; its label is the cue's text |
| `player.subtitles.second` | Second Subtitles on the subtitles page, after Timing and Reset Timing, while the stream has text tracks or add-ons offer files; label `Second Subtitles, Off` or `Second Subtitles, Russian`. Selecting it opens a page of Off, the stream's text tracks and the add-ons' rows (`player.option`), without the track the first subtitles show |
| `player.subtitles.timing` | Timing, first on the subtitles page while subtitles are on; label `Timing, In Sync`, `Timing, 0,3 s Later` or `Timing, 1,5 s Earlier` (the decimal follows the simulator's locale). Selecting it opens the timing strip. Reset Timing follows it as a `player.option` while the delay is not zero |
| `player.timing`, `player.timing.offset` | the subtitle timing strip, which takes focus and the remote's presses (label `Subtitle Timing`, value the delay), and the delay in words above its lanes |
| `player.timing.suggestion` | on the timing strip, the delay the speech suggests while it differs from the current one by 0.5 s or more; label `Suggested: 1,8 s Later. Press Up to apply`. Up applies it |
| `player.tab.info`, `player.tab.episodes`, `player.tab.chapters` | the content tabs' names at the left of the transport bar's row of buttons, with playback in the middle and the track buttons on the right; Episodes only for a series once its metadata loaded, Chapters only when the file has chapters. Selecting a name opens its tab below the bar (the open one is bold and has the Selected trait); with a tab open, focusing another name switches to it |
| `player.info` | the Info tab: label `<title>, Season 5, Episode 6 · <name>, <description>, <stream name>` |
| `player.episode.<video id>` | each episode card in the Episodes tab, such as `player.episode.tt0903747:5:6`; the playing one's caption has a `Playing` image, watched ones a `Watched` image |
| `player.chapter.<number>` | each chapter card in the Chapters tab, numbered from 0 by the engine, label `<title>, <start>` such as `Chapter 2, 4:09` |
| `player.upNext.play`, `player.upNext.dismiss` | the up next card's Play Now (Choose Stream when the next episode has no matching stream) and Cancel; the card shows near an episode's end while the controls are hidden, with Play Now focused |
| `settings.account`, `settings.addons`, `settings.sources`, `settings.playback`, `settings.subtitles`, `settings.about` | Settings rows; Sources reads `Sources, None`, `Sources, 1 source` or `Sources, <n> sources` |
| `settings.moreOptions` | More Options on Settings › Playback and Settings › Subtitles, after the common rows. Selecting it shows the rarely changed rows below it and keeps focus on it; its value reads `Expanded`, `Collapsed`, or `Collapsed, 2 changed` while hidden settings differ from their defaults, and the row shows `2 changed` beside its chevron. It starts collapsed each time the page opens |
| `settings.trakt` | Trakt on Settings › Account when signed in; its value reads Connected or Not Connected |
| `trakt.qr`, `trakt.retry`, `trakt.disconnect` | Settings › Account › Trakt: the QR code that connects Trakt (shown while not connected, the app polls the account every 3 s until it leaves the screen), Try Again after waiting failed, and Disconnect when connected (confirms first) |
| `about.shareLogs` | Share Logs on Settings › About |
| `shareLogs.screen`, `shareLogs.window`, `shareLogs.url`, `shareLogs.key`, `shareLogs.showKey`, `shareLogs.retry` | Share Logs: the screen, its time range button (`Last Hour` by default; opens Last 15 Minutes, Last Hour, Last 6 Hours, Last 24 Hours, Last 7 Days), the address to fetch the logs from, the log key (release builds only; its text is redaction glyphs until shown), the Show Log Key / Hide Log Key button beside it, and Try Again when sharing failed |
| `playback.audioLanguage`, `playback.secondAudioLanguage`, `playback.seekStep`, `playback.skipSegmentSource`, `playback.upNextNotice`, `playback.autoplayNext`, `playback.hideSpoilers` | Settings › Playback rows; Skip Data and Hide Spoilers sit behind `settings.moreOptions`; Second Language shows only when an audio language is set; Skip Interval opens a list of 5, 10, 15 and 30 seconds; Skip Data opens a list of IntroDB and SkipDB, with Premium Account first for a Stremio Premium account; Up Next Card opens a list of Off and 10, 20, 35 and 60 seconds before the end; Autoplay Next Episode and Hide Spoilers are toggles |
| `subtitles.language`, `subtitles.secondLanguage` | Settings › Subtitles language rows; Second Language shows only when a language is set |
| `subtitles.size`, `subtitles.font`, `subtitles.bold`, `subtitles.fileStyling`, `subtitles.textColor`, `subtitles.outlineColor`, `subtitles.backgroundColor`, `subtitles.opacity`, `subtitles.position`, `subtitles.reset` | Settings › Subtitles style rows; Font, Bold, Text, Outline, Opacity and Use File Styling sit behind `settings.moreOptions`; each but the Bold and Use File Styling toggles and Reset opens a list of choices |
| `subtitles.preview` | the live preview on Settings › Subtitles and on each style list, where it shows the focused choice |
| `addons.install`, `addons.manifestURL`, `addons.submit`, `addons.status`, `addons.row` | Settings › Add-ons; `addons.submit` is the Install button under the field, `addons.status` exists only while it has a message |
| `sources.row`, `sources.addJellyfin`, `sources.addWebDAV` | Settings › Sources: each source (label `<name>, <Jellyfin or WebDAV>`, in the order added), then Add Jellyfin Server and Add WebDAV Folder. With no source only the two add rows show |
| `source.browse`, `source.folders`, `source.name`, `source.kind`, `source.server`, `source.username`, `source.edit`, `source.remove` | a source's page: Browse, which opens its folders, Folders (WebDAV only), its values (label `Name, <name>`), Edit, and Remove, which confirms ("Remove <name>?") before removing and going back |
| `sourceFolders.row`, `sourceFolders.loading`, `sourceFolders.retry` | a WebDAV source's Folders page: each top-level folder (label `<name>, <Movies, Shows or Other Videos>`, the suggested kind until one is chosen; `Saving…` while it saves), which opens a list of the three kinds with the current one checked and focused (rows have no identifier; match them by label); the row shown while it loads; Try Again when listing failed. Focus lands on the first folder |
| `library.browse`, `library.retry` | with a source picked: Browse Folders after the menus, which opens the source's folders; Try Again when the source could not be read |
| `browser.screen`, `browser.folder`, `browser.episode`, `browser.retry` | a source's folder: each folder (label its name), each episode file (`S1 E2 · <name>`, opens the show's details), then titles as `poster.<id>`; Try Again on the empty and failed states. Focus lands on the first entry |
| `sourceForm.name`, `sourceForm.url`, `sourceForm.username`, `sourceForm.password`, `sourceForm.save`, `sourceForm.error` | the add and edit form; Name only when editing, an empty password keeps the stored one when editing. Save shows a spinner while the server is asked and keeps focus; `sourceForm.error` exists only after a failed save |
