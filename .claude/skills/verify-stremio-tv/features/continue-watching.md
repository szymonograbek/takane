# Continue watching

After the user watches part of an item and pauses or stops, core records the position and the item appears under "Continue watching" with its offset and duration.

## Sub-features

- `cw-after-stop` lists the item after stopping playback.
- `cw-offset` shows the offset reached, in seconds.
- `cw-persist` writes the progress to the profile's library on disk.

## How to get to it (user POV)

- Left column, below the add-on list, after playing something.

## Driving it with tv.sh

Preconditions:

- [Playback](./playback.md) ran for at least 10 s in this run and was stopped with Menu.

- **Listed.** Run `$T text continueWatching.item`. Prints `The Shawshank Redemption · <offset>s / <duration>s` with offset at least 10.
- **Persisted.** Run `source build/verify/current.env; grep -o '"timeOffset":[0-9]*' "$storage/library_recent.json"`. The value in milliseconds matches the offset shown.
- **Proof.** Run `$T evidence continue-watching`.

## Gotchas

- Core copies progress into the library only on pause, stop and every 180 s, not on every position update. A crash mid-playback loses up to 180 s.
- Numbers use the device locale's grouping: duration `8553` shows as `8.553s` or `8,553s`.
- A fresh profile has no items; an item listed before playback means the run is not on a fresh profile (check `$T doctor`).
