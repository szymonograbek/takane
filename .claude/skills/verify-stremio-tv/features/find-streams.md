# Find streams

Home shows a hero, Continue Watching and one row per add-on catalog. Search finds titles across add-ons. A title opens Details (Play, Resume, seasons and episodes), and Play opens the stream list: each add-on's playable streams under the add-on's name.

## Sub-features

- `home-rows` lists catalog rows titled with their type ("Popular Movies").
- `search` shows results grouped by type as the user types.
- `recent-searches` shows the last searches before anything is typed; selecting one runs it, Clear forgets them all. Steps of typing a longer search ("bre" for "breaking bad") are left out.
- `details` shows logo or title, year, runtime, genres, rating, description, Play and episodes. Each episode card shows its still, its number and name, and its overview; with Hide Spoilers on, unwatched ones blur the still and drop the overview ([Playback settings](./playback-settings.md)).
- `streams` lists playable streams per add-on; torrent-only results are hidden.
- `no-streams` explains when nothing is playable.

## How to get to it (user POV)

- Home → a poster → Play; or Search → type → a poster → Play.

## Driving it with tv.sh

Preconditions:

- [Onboarding](./onboarding.md) continued without an account; the debrid add-on is installed ([Install an add-on](./install-addon.md)).

- **Search.** `$T focus magnifyingglass right`, `$T remote down`. Find the search field's ref in a raw snapshot (`type == SearchField`) and run `agent-device fill <ref> shawshank --session stremio-tv-verify` (it may report a read-back mismatch; the text still lands). `$T wait-text "The Shawshank Redemption" 20`.
- **Recent searches.** After the search above, clear the field (or relaunch on the same profile) and the Search tab shows `Recent Searches` with a `search.recent` labeled `shawshank`. `$T focus search.recent down 3`, `$T select`: the field fills and "The Shawshank Redemption" shows again. `$T focus search.clearRecent right`, `$T select`, then select Clear Recent Searches: the row goes away and "Search Your Add-ons" shows.
- **Details.** `$T focus poster.tt0111161 down 3`, `$T select`, wait 6 s. `$T focused` prints `details.play`.
- **Streams.** `$T select`, wait up to 15 s. Focus moves to the first `streams.row`; the screenshot shows `AIOStreams | ElfHosted` rows.
- **No streams.** Without the debrid add-on, the same steps show "No Playable Streams".

## Gotchas

- Add-on catalogs can insert placeholder items (AIOStreams error posters); prefer Search over Home positions in scripts.
