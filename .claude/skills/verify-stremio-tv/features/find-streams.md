# Find streams

The user enters an IMDb id and asks for movie or series streams; core queries every installed add-on and the list shows each add-on's streams, with debrid URL streams playable and torrent or external ones disabled.

## Sub-features

- `streams-movie` looks up a movie id (`tt0111161`).
- `streams-series` looks up an episode id (`tt0944947:1:1`).
- `streams-status` reports "<n> streams from <m> add-ons" or the error.
- `streams-playable` makes only URL streams focusable buttons; others show "<kind>, not playable" as plain text.

## How to get to it (user POV)

- In the right column, edit the IMDb id field if needed, then choose "Movie" or "Series".

## Driving it with tv.sh

Preconditions:

- AIOStreams installed (run [Install an add-on](./install-addon.md) first in the same run).

- **Movie lookup.** Run `$T focus streams.findMovie right` then `$T select`. Poll `$T text streams.status` until it contains `streams from`. Expect `1080 streams from 2 add-ons` (AIOStreams 1078, WatchHub 2) for `tt0111161`.
- **Rows.** Run `$T evidence find-streams`. In `find-streams.ax.jsonl`, nodes with `"identifier":"streams.row"` exist (type Button), and WatchHub rows have `"identifier":"streams.unplayableRow"` with labels ending `External, not playable`.
- **Series lookup.** From the movie results, run `$T type streams.itemID up "tt0944947:1:1"` (up from a row reaches the id field), confirm `$T text streams.itemID` reads `tt0944947:1:1`, then `$T focus streams.findSeries right`, `$T select`, and poll `$T text streams.status`. Observed `909 streams from 2 add-ons`.

## Gotchas

- Stream counts come from live debrid caches and change over time; assert `streams from` plus a non-zero count, not the exact number.
- The first playable row usually sits half below the list's bottom edge, which breaks agent-device's normal snapshot. The helper uses raw snapshots.
- The lookup takes 2-10 s; "Loading…" shows meanwhile.
- Unplayable rows used to be disabled buttons, which swallowed "up" presses so focus could never leave the list. If focus gets stuck on the first row again, that regression is back.
