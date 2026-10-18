# Stremio TV verification map

The maintained source for verifying what a user can do in Stremio TV. Read this index, then drive the matching feature file. Commands use `T=.claude/skills/verify-stremio-tv/scripts/tv.sh` from the repo root.

## Baseline preconditions

- `$T launch` succeeded and `$T doctor` passes: tvOS app in the "Stremio Apple TV" simulator, fresh core profile `verify-<run-id>`.
- A fresh profile has the six default add-ons (Cinemeta, YouTube, WatchHub, Public Domain Movies, OpenSubtitles v3, Local Files) and an empty continue-watching list.
- `STREMIO_SMOKE_ADDON_URL` is set or present in `.env.smoke` (the user's AIOStreams debrid add-on).
- Never drive an app instance this run did not launch.

## Driving conventions

- Start each recipe from the state its preconditions name; earlier recipes create that state.
- Move focus with `$T focus <id> <direction>`, then `$T select`. Never tap by coordinates.
- Read state with `$T text <id>` and `$T wait-text "<label>"`, which use raw snapshots.
- Treat ids and labels as literal.
- `$T cleanup` at the end of every run, passed or failed.

## Proof and skip reporting

- Capture `$T evidence <feature>-<step>` after each user action that changes state.
- Record the action, the element text afterwards, and any persisted side effect (`profile.json`, `library_recent.json` in the run's storage dir).
- If a precondition cannot be met (add-on URL missing, debrid down), report the feature as not verified with the failing command and reason. Do not substitute the smoke journey for a UI recipe.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior, then four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with tv.sh`, `Gotchas`.

## Features

- [Core status](./core-status.md) covers launch, the core Ready state and the default add-ons.
- [Install an add-on](./install-addon.md) covers installing by manifest URL and its persistence.
- [Find streams](./find-streams.md) covers movie and episode lookup across installed add-ons.
- [Playback](./playback.md) covers playing a stream full screen, pause, seek and stop.
- [Continue watching](./continue-watching.md) covers progress recorded after playback.
