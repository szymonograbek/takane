# Playback

Choosing a stream opens a full-screen player that shows only the video. Select shows the controls: title, a focusable progress bar, elapsed and remaining time, back/forward one skip interval (10 s by default, Settings › Playback), play/pause, and buttons for subtitles, audio and speed that open a panel of choices above them, focused on the current one. The controls hide after 5 s of playing, never while a panel is open. On the subtitles panel each add-on is a row that opens a page of its files. Menu goes back from an add-on page, then closes the panel, then the controls, then the player. Closing a panel puts focus straight back on its button.

## Sub-features

- `play-open` starts the stream; with a saved position it starts there.
- `play-controls` shows the controls with focus on play/pause.
- `play-speed` changes the playback speed from the Speed panel.
- `play-subtitles` lists embedded tracks and selects one; the app draws its cues over the video, text and bitmap (PGS) alike.
- `play-seek` skips one skip interval (10 s by default) with left and right while the controls are hidden.
- `play-timeline` on the focused progress bar: taps jump one skip interval, quick taps jump one interval further each (up to 60 s), a hold scans at 2× and further presses change the rate.
- `play-stop` returns to the screen that opened the stream list: Details, or Home for a hero Play or a Continue Watching card.

## How to get to it (user POV)

- [Find streams](./find-streams.md), then select a stream.

## Driving it with tv.sh

Preconditions:

- A stream list is on screen with focus on a `streams.row`.

- **Open.** `$T select`. Within 30 s `$T text player.status` reads `… · playing · 1920×1080 · libavcodec H264 (SW)`.
- **Controls.** After 5 s the controls are gone (screenshot shows video only). `$T select`; `$T focused` prints `player.playPause`.
- **Speed.** `$T focus player.speed right 6`, `$T select` (focus lands on Normal, `player.option`), press down twice, `$T select`. Reopening the Speed panel shows 1.5× selected.
- **Subtitles.** `$T focus player.subtitles left 3`, `$T select`, `$T remote down`, `$T select`. The track list reports it selected; within a few seconds of dialogue `$T text player.subtitle` prints the cue, and `$T evidence` shows it above the picture's bottom edge. Off clears it at once.
- **Timeline.** Controls showing, `$T focus player.progress up 3`, then right away `$T remote right` three times: `player.status` jumps about 60 s (10 + 20 + 30) at the default interval. Hold with `agent-device tv-remote press right --duration-ms 800 --platform ios --target tv --session stremio-tv-verify`: the phase reads `paused`, the time keeps advancing about 2 s per second, and the snapshot has a `2×` label. `$T remote right` makes it `4×`; `$T remote left` twice reads `playing` again. Hold again and `$T select`: `playing`.
- **Stop.** `$T remote menu` until Details is back with Resume (closes the controls, then the player). The stream list closed once the stream started playing; a stream that fails returns to it.

## Gotchas

- agent-device's tvOS remote has no play/pause button; use the controls' play/pause.
- The simulator decodes in software (`libavcodec … (SW)`). Hardware decoding needs a real Apple TV.
- Large REMUX streams take 5-15 s to start.
- The controls hide 5 s after the last press while playing, and arrows then skip one interval on the bare video instead. Press on the bar before taking evidence, not after.
- The session picks a subtitle track in the profile's language at load, so subtitles may already show before the panel is opened.
- Skip Intro needs an episode with SkipDB data and is not covered here.
