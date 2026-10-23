# Playback

Choosing a stream opens a full-screen player that shows only the video. Select, up or down shows the controls: title, a focusable progress bar, elapsed and remaining time, back/forward one skip interval (10 s by default, Settings › Playback), play/pause, and buttons for subtitles, audio and speed that open a panel of choices above them, focused on the current one. The controls hide after 5 s of playing, never while paused, scanning or a panel is open. On the subtitles panel each add-on is a row that opens a page of its files. Menu ends a scan, goes back from an add-on page, then closes the panel, then the controls, then the player. Closing a panel puts focus straight back on its button. With subtitles on, the subtitles panel starts with Timing, which opens a strip along the bottom for moving the subtitles earlier or later while the video plays.

## Sub-features

- `play-open` starts the stream; with a saved position it starts there.
- `play-controls` shows the controls with focus on play/pause.
- `play-speed` changes the playback speed from the Speed panel.
- `play-subtitles` lists embedded tracks and selects one; the app draws its cues over the video, text and bitmap (PGS) alike.
- `play-seek` skips one skip interval (10 s by default) with left and right while the controls are hidden, and shows the controls for 2 s with the progress bar focused.
- `play-subtitle-timing` moves the subtitles: left and right 0.1 s earlier or later, held 0.5 s at a time, select starts the line nearest the playhead now, Menu leaves; the delay is remembered with the subtitles for the same stream.
- `play-timeline` on the focused progress bar: every tap jumps one skip interval, quick taps in one direction add up beside the picture ("+30s"), a hold scans at 2× and further presses change the rate.
- `play-live` plays a live channel (type `tv`): `player.live` (LIVE) replaces the progress bar, the times and back/forward; left and right show the controls on play/pause instead of seeking.
- `play-stop` returns to the screen that opened the stream list: Details, or Home for a hero Play or a Continue Watching card.

## How to get to it (user POV)

- [Find streams](./find-streams.md), then select a stream.

## Driving it with tv.sh

Preconditions:

- A stream list is on screen with focus on a `streams.row`.

- **Open.** `$T select`. Within 30 s `$T text player.status` reads `… · playing · 1920×1080 · libavcodec H264 (SW)`.
- **Controls.** After 5 s the controls are gone (screenshot shows video only). `$T select`; `$T focused` prints `player.playPause`.
- **Speed.** `$T focus player.speed right 6`, `$T select` (focus lands on Normal, `player.option`), press down twice, `$T select`. Reopening the Speed panel focuses 1.5× (labels follow the simulator's locale, such as `1,5×`).
- **Subtitles.** `$T focus player.subtitles left 3`, `$T select`: the panel lists Built-in (Off, the tracks) and Add-ons (one row per subtitles add-on). `$T remote down`, `$T select` picks the first track; the log shows `chooseSubtitles(…builtIn…)`. For a text track, within a few seconds of dialogue `$T text player.subtitle` prints the cue and `$T evidence` shows it above the picture's bottom edge. A bitmap track (`codec=dvd_subtitle` or PGS in the log) has no element: the log's `subtitle-delivery … published=1` marks a cue, and a screenshot then shows it. Off clears it at once.
- **Subtitle timing.** Needs a stream whose link stays the same across plays, so the remembered delay can be checked: the fixture source (`scripts/dev-sources.sh up`, `$T launch -STREMIO_FIXTURE_SOURCE 1`), Home › Fixture Movies › Sintel › Play, the `streams.row` labeled `Fixture, Sintel (2010).mkv`. On the subtitles panel open the Fixture row and pick `English 1`, its sidecar: one cue from 0:01 to 0:30 ("A subtitle from a sidecar file."). Within its first 15 s: `$T focus player.subtitles.timing up 6` (label `Timing, In Sync`), `$T select`. `$T focused` prints `player.timing` and the strip shows the cue as a block under the playhead. `$T remote right` three times: `$T text player.timing.offset` reads `0,3 s Later` and a screenshot shows the block moved off its dashed outline. Hold with `agent-device tv-remote press right --duration-ms 1600 --platform ios --target tv --session stremio-tv-verify`: 2.5 s more (`2,8 s Later`). Within 10 s of the cue's start `$T select` sets the delay so it starts now (at 0:08 about `6,9 s Later`). `$T remote menu` leaves the strip for the bare video; reopening the panel shows `Timing, 6,9 s Later` and Reset Timing, and `source build/verify/current.env; grep -o '"subtitleDelay":[-0-9]*' "$storage/streams.json"` prints `"subtitleDelay":6900`. To check it is remembered, relaunch with the fixture still listed (`$T relaunch` drops the launch option, so run `agent-device open com.ograbek.takane … --relaunch` with the storage, mute and fixture `--launch-args`), play the same `streams.row` from Continue Watching, and the panel reads `Timing, 6,9 s Later`. Reset Timing reads `Timing, In Sync` again.
- **Timeline.** Controls showing, `$T focus player.progress up 3`, then right away `$T remote right` three times: `player.status` jumps about 30 s at the default interval, and a screenshot within a second (`xcrun simctl io <udid> screenshot`) shows "+30s" at the right edge. With the controls hidden, one `$T remote right` jumps 10 s and `$T focused` prints `player.progress`; 2 s later the controls are gone. Hold with `agent-device tv-remote press right --duration-ms 800 --platform ios --target tv --session stremio-tv-verify`: the phase reads `paused`, the time keeps advancing about 2 s per second, and the snapshot has a `2×` label. `$T remote right` makes it `4×`; `$T remote left` twice reads `playing` again. Hold again and `$T select` (or `$T remote menu`): `playing`, still in the player.
- **Live.** Needs the free Pluto TV add-on: install `https://dev.nebulawp.org/stremio/pluto-tv-addon/manifest.json` as in [Install an add-on](./install-addon.md) (`$T type addons.manifestURL down <url>`; 7 installed). Home gains "Pluto TV Channels" and "Pluto TV Popular Channels" rows about six presses down from the tab bar; posters are `poster.<channel slug>`, such as `poster.cnn-headlines`. Select one; Details offers `Play` (not Play First Episode); select it, then the first `streams.row`. Within 30 s `player.status` reads `0:00:10 / 0:00:00 · playing · 1280×720` (no decoder field; the time counts up from the start, the duration stays 0:00:00). `$T remote right`: `$T focused` prints `player.playPause`, `$T text player.live` prints `Live` and `$T text player.progress` finds nothing. Menu closes the controls, then returns to Details.
- **Stop.** `$T remote menu` until Details is back with Resume (closes the controls, then the player). The stream list closed once the stream started playing; a stream that fails returns to it.

## Gotchas

- agent-device's tvOS remote has no play/pause button; use the controls' play/pause.
- The simulator decodes in software (`libavcodec … (SW)`). Hardware decoding needs a real Apple TV.
- Large REMUX streams take 5-15 s to start.
- The controls hide 5 s after the last press while playing, and arrows then skip one interval on the bare video instead. Each `$T focus` step reads a snapshot (about 1 s), so a long focus walk can outlast them. Pause first (select on `player.playPause`): the controls then stay up.
- The session picks a subtitle track in the profile's language at load, so subtitles may already show before the panel is opened.
- The player keeps the speed and tracks chosen for a title, so the next stream of it starts at that speed.
- Core remembers a subtitle delay only for the same stream. AIOStreams answers each lookup with new playback links, so a debrid stream played again starts in sync; use the fixture source to check the remembered delay.
- The fixture clip is 90 s and its one cue ends at 0:30 (later with a delay): seek back with the progress bar before opening the strip.
- Skip Intro needs an episode with data in the source Settings › Playback › Skip Data names (Stremio Premium, IntroDB or SkipDB) and is not covered here.
