# Playback

Choosing a stream opens a full-screen player that shows only the video. Select shows the controls: title, progress, elapsed and remaining time, back/forward 10 s, play/pause, and menus for subtitles, audio and speed. The controls hide after 5 s of playing. Menu closes a menu, then the controls, then the player.

## Sub-features

- `play-open` starts the stream; with a saved position it starts there.
- `play-controls` shows the controls with focus on play/pause.
- `play-speed` changes mpv's speed from the Speed menu.
- `play-subtitles` lists embedded tracks and selects one.
- `play-seek` skips 10 s with left and right while the controls are hidden.
- `play-stop` returns to the stream list.

## How to get to it (user POV)

- [Find streams](./find-streams.md), then select a stream.

## Driving it with tv.sh

Preconditions:

- A stream list is on screen with focus on a `streams.row`.

- **Open.** `$T select`. Within 30 s `$T text player.status` reads `… · playing · 1920×1080 · hwdec no`.
- **Controls.** After 5 s the controls are gone (screenshot shows video only). `$T select`; `$T focused` prints `player.playPause`.
- **Speed.** `$T focus Speed right 6`, `$T select`, press down 4 times, `$T select`. The log shows `property speed → speed(…oneAndAHalf)`.
- **Subtitles.** `$T focus Subtitles left 3`, `$T select`, `$T remote down`, `$T select`. The log shows `set sid=1` and the track list reports it selected.
- **Stop.** `$T remote menu` until the stream list is back (closes the controls, then the player).

## Gotchas

- agent-device's tvOS remote has no play/pause button; use the controls' play/pause.
- The simulator decodes in software (`hwdec no`). Hardware decoding needs a real Apple TV.
- Large REMUX streams take 5-15 s to start.
- Never call mpv frame capture in the simulator: it crashes the Metal simulator driver. Use `$T evidence` screenshots.
- Skip Intro needs an episode with SkipDB data and is not covered here.
