# Continue watching

After the user watches part of an item and stops, core records the position. Home shows it first under Continue Watching as a wide card with a progress line and the time left. Selecting the card opens its streams, which say where playback resumes, and the chosen stream starts there. Details' Resume (`details.resume`) does the same. A show with new episodes instead reads `New episode` (or `N new episodes`) and opens its Details.

## Sub-features

- `cw-row` lists the item on Home with time left (`<name>, 1 h 24 min left`; an episode adds `S1 · E2 ·`).
- `cw-resume` starts playback at the saved position.
- `cw-persist` writes the progress to the profile's library on disk.

## How to get to it (user POV)

- Home, the row under the hero, after playing something.

## Driving it with tv.sh

Preconditions:

- [Playback](./playback.md) ran for at least 10 s in this run and was stopped.

- **Listed.** `$T focus house up`, `$T remote down` (up from there reaches the hero). `$T focused` prints `continueWatching.item`; `$T text continueWatching.item` prints the time left.
- **Resume.** `$T select`, wait 12 s. The screen shows `Resumes at 0:20` (or the saved time). Select a stream; the log shows `load <url> from <seconds>s` (such as `from 406.19s`) and `player.status` starts at that time.
- **Persisted.** `source build/verify/current.env; grep -o '"timeOffset":[0-9]*' "$storage/library_recent.json"`.

## Gotchas

- Core copies progress into the library only on pause, stop and every 180 s.
- Long-press (`agent-device tv-remote longpress select --duration-ms 1500 --session stremio-tv-verify`) offers Mark as Watched (movies only) and Remove from Continue Watching, which rewinds the item in core.
- Removing the title from the library also drops it from Continue Watching; run this recipe before [Library](./library-calendar.md)'s Remove.
