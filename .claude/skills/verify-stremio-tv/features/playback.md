# Playback

Choosing a stream opens a full-screen player that shows only the video. Select shows the controls: title, a focusable progress bar, elapsed and remaining time, back/forward 10 s, play/pause, and buttons for subtitles, audio and speed that open a panel of choices above them, focused on the current one. The controls hide after 5 s of playing, never while a panel is open. On the subtitles panel each add-on is a row that opens a page of its files. Menu goes back from an add-on page, then closes the panel, then the controls, then the player. Closing a panel puts focus straight back on its button.

## Sub-features

- `play-open` starts the stream; with a saved position it starts there.
- `play-controls` shows the controls with focus on play/pause.
- `play-speed` changes mpv's speed from the Speed panel.
- `play-subtitles` lists embedded tracks and selects one.
- `play-seek` skips 10 s with left and right while the controls are hidden.
- `play-timeline` on the focused progress bar: taps jump 10 s, quick taps jump 10 s further each (up to 60 s), a hold scans at 2× and further presses change the rate.
- `play-stop` returns to the stream list.

## How to get to it (user POV)

- [Find streams](./find-streams.md), then select a stream.

## Driving it with tv.sh

Preconditions:

- A stream list is on screen with focus on a `streams.row`.

- **Open.** `$T select`. Within 30 s `$T text player.status` reads `… · playing · 1920×1080 · hwdec no`.
- **Controls.** After 5 s the controls are gone (screenshot shows video only). `$T select`; `$T focused` prints `player.playPause`.
- **Speed.** `$T focus player.speed right 6`, `$T select` (focus lands on Normal, `player.option`), press down twice, `$T select`. The log shows `property speed → speed(…oneAndAHalf)`.
- **Subtitles.** `$T focus player.subtitles left 3`, `$T select`, `$T remote down`, `$T select`. The log shows `set sid=1` and the track list reports it selected.
- **Timeline.** Controls showing, `$T focus player.progress up 3`, then right away `$T remote right` three times: `player.status` jumps about 60 s (10 + 20 + 30). Hold with `agent-device tv-remote press right --duration-ms 800 --platform ios --target tv --session stremio-tv-verify`: the phase reads `paused`, the time keeps advancing about 2 s per second, and the snapshot has a `2×` label. `$T remote right` makes it `4×`; `$T remote left` twice reads `playing` again. Hold again and `$T select`: `playing`.
- **Stop.** `$T remote menu` until the stream list is back (closes the controls, then the player).

## Gotchas

- agent-device's tvOS remote has no play/pause button; use the controls' play/pause.
- The simulator decodes in software (`hwdec no`). Hardware decoding needs a real Apple TV.
- Large REMUX streams take 5-15 s to start.
- Never call mpv frame capture in the simulator: it crashes the Metal simulator driver. Use `$T evidence` screenshots.
- The controls hide 5 s after the last press while playing, and arrows then skip 10 s on the bare video instead. Press on the bar before taking evidence, not after.
- Skip Intro needs an episode with SkipDB data and is not covered here.
