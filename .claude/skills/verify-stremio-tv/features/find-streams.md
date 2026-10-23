# Find streams

Home shows a hero, Continue Watching and one row per add-on catalog. Search finds titles across add-ons. A title opens Details (Play, Resume, seasons and episodes), and Play opens the stream list: each add-on's playable streams under the add-on's name.

## Sub-features

- `home-rows` lists catalog rows titled with their type ("Popular Movies"; a `tv` catalog reads "Channels", such as "Pluto TV Channels"). A live channel in the hero gets Play, like a movie.
- `search` shows results grouped by type as the user types.
- `recent-searches` shows the last searches before anything is typed; selecting one runs it, Clear forgets them all. Steps of typing a longer search ("bre" for "breaking bad") are left out.
- `search-suggestions` offers up to four recent searches that continue what is typed, the typed part dimmed.
- `genres` lists, before anything is typed, the genres of one catalog per type (Cinemeta's Popular: Movies by Genre, Series by Genre); a genre opens a grid of that catalog's titles in it.
- `details` shows logo or title, year, runtime, genres, rating, description, Play and episodes. Each episode card shows its still, its number and name, and its overview; with Hide Spoilers on, unwatched ones blur the still and drop the overview ([Playback settings](./playback-settings.md)).
- `streams` lists playable streams per add-on; torrent-only results are hidden.
- `other-services` lists, for a signed-out account in a build with `RAPIDAPI_KEY`, the streaming services that offer the title in the device's region, below the streams; selecting one opens it on that service.
- `no-streams` explains when nothing is playable.

## How to get to it (user POV)

- Home → a poster → Play; or Search → type → a poster → Play; or Search → a genre → a poster → Play.

## Driving it with tv.sh

Preconditions:

- [Onboarding](./onboarding.md) continued without an account; the debrid add-on is installed ([Install an add-on](./install-addon.md)).

- **Search.** `$T focus magnifyingglass right`, `$T remote down`. Find the search field's ref in a raw snapshot (`type == SearchField`) and run `agent-device fill <ref> "night of the living dead" --session stremio-tv-verify` (it may report a read-back mismatch; the text still lands). `$T wait-text "Night of the Living Dead" 20`.
- **Recent searches.** After the search above, clear the field (or relaunch on the same profile) and the Search tab shows `Recent Searches` with a `search.recent` labeled `night of the living dead`. `$T focus search.recent down 3`, `$T select`: the field fills and "Night of the Living Dead" shows again. `$T focus search.clearRecent right`, `$T select`, then select Clear Recent Searches: the row goes away and "Search Your Add-ons" shows.
- **Suggestions.** With `night of the living dead` in the history, fill the search field with `nig`: the suggestions list `night of the living dead`; selecting it fills the field.
- **Genres.** On a fresh Search (empty field), `$T focus search.genre down 4` lands on the first movie genre (`Action`). `$T select`, wait up to 10 s: `genre.screen` shows posters and `$T focused` prints a `poster.<imdb id>`. `$T remote menu` goes back to Search.
- **Back to the field.** From a result or a genre, `$T remote menu` scrolls Search back up with the search field focused (`$T focused` prints its prompt, `Movies and series`) and the query kept; a second `$T remote menu` focuses the tab bar.
- **Details.** `$T focus poster.tt0063350 down 3`, `$T select`. While Details loads, `loading.cancel` has focus; poll `$T focused` until it prints `details.play` (up to 15 s) before pressing anything, or the presses land on Play. The description (`details.description`) sits above the buttons: up from Play, select opens the full text with `details.descriptionDone`.
- **Streams.** `$T select`, wait up to 15 s. Focus moves to the first `streams.row`; the screenshot shows `AIOStreams | ElfHosted` rows.
- **Other services.** On a fresh profile (signed out, no debrid add-on), open a title from Home that streaming services carry in the simulator's region (Slow Horses, `poster.tt5875444`, in Poland). Focus lands on the first `streams.offer` under Other Services; the app log shows one `GET https://streaming-availability.p.rapidapi.com/shows/<imdb id>`. Select: the simulator has no app for the link, so "Open <service> Yourself" shows. Each lookup spends one of the key's monthly requests.
- **No streams.** Without the debrid add-on, the same steps show "No Playable Streams", unless other services offer the title.

## Gotchas

- Add-on catalogs can insert placeholder items (AIOStreams error posters); prefer Search over Home positions in scripts.
