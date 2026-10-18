# Playback

Choosing a playable stream opens a full-screen mpv player that plays the debrid stream, shows position, state, resolution and decoder, pauses on select, seeks with left and right, and stops on Menu.

## Sub-features

- `play-open` opens the full-screen player from a stream row.
- `play-progress` advances the position while playing.
- `play-pause` toggles pause with select (or play/pause on a real remote).
- `play-seek` jumps 10 s with left and right.
- `play-stop` stops and returns to the list with Menu.

## How to get to it (user POV)

- After [Find streams](./find-streams.md), move focus down onto a playable row and press select.

## Driving it with tv.sh

Preconditions:

- Streams listed for `tt0111161` with focus on `streams.findMovie`.

- **Open.** Run `$T focus streams.row down 4` then `$T select`. Within 30 s `$T text player.status` reads `… · playing · 1920×1080 · hwdec no`.
- **Progress.** Poll `$T text player.status` until it starts `0:00:10`. Run `$T evidence playback-playing`; the screenshot shows the film frame with the status line.
- **Pause.** Run `$T select`, wait 1 s, `$T text player.status`. Phase reads `paused` and the position stops changing across two reads 2 s apart.
- **Resume.** Run `$T select`. Phase reads `playing` again.
- **Seek.** Note the position, run `$T remote right`, read again. Position is about 10 s later.
- **Stop.** Run `$T remote menu`. `$T text player.status` fails (player dismissed) and the stream list is back. Run `$T evidence playback-stopped`.

## Gotchas

- agent-device's tvOS remote has no play/pause button; select is mapped to pause/resume for that reason.
- The simulator decodes in software (`hwdec no`). Do not treat that as a regression; hardware decoding needs a real Apple TV.
- The first row may be a 50+ GB REMUX; startup can take 5-15 s while mpv buffers.
- Never call mpv frame capture in the simulator: it crashes the Metal simulator driver. Use `$T evidence` screenshots.
