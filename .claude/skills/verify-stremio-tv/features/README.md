# Takane verification map

The maintained source for verifying what a user can do in Takane. Read this index, then drive the matching feature file. Commands use `T=.claude/skills/verify-stremio-tv/scripts/tv.sh` from the repo root.

## Baseline preconditions

- `$T launch` succeeded and `$T doctor` passes: tvOS app in the "Stremio Apple TV" simulator on the Welcome screen, fresh core profile `verify-<run-id>`.
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

- [Onboarding and sign-in](./onboarding.md) covers Welcome, the link code, email sign-in errors and continuing without an account.
- [Install an add-on](./install-addon.md) covers Settings › Add-ons: install by manifest URL, remove, persistence.
- [Find streams](./find-streams.md) covers Home, Search and Details leading to the stream list.
- [Playback](./playback.md) covers the player: controls, speed, subtitles, audio, seek, timeline scrubbing and stop.
- [Continue watching](./continue-watching.md) covers the Home row and resuming from the saved position.
- [Playback settings](./playback-settings.md) covers Settings › Playback (audio languages, skip interval, Up Next card, autoplay, hide spoilers) and Settings › Subtitles (languages, style, reset).
- [Library and calendar](./library-calendar.md) covers Add to Library on Details, the Library tab and the Calendar tab.
- [Trakt](./trakt.md) covers Settings › Account › Trakt and scrobbling playback to Trakt; it needs the test account.
- [Share logs](./share-logs.md) covers Settings › About › Share Logs: the link, its time range and stopping on leave.
