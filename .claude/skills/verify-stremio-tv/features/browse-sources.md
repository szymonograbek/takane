# Browse sources

Library lists a source's titles once it is picked, and the user walks its folders the way the server arranges them and opens any title from there. Library's Browse Folders (with a source picked) and Browse on a source's page in Settings open the folders. Home lists the sources' rows first, each with its 20 newest titles and See All. A Jellyfin source's root lists its libraries, and a library its titles and folders. A WebDAV source's root lists its top folders; a movie's own folder shows as the movie, and a season folder lists its episode files. A title opens its details, an episode file opens its show's details, and from there streams and the player work as anywhere else. Menu goes back one folder at a time.

## Sub-features

- `library-picker` lists Your Library, then each source by name (`library.picker`). A source shows all its titles, movies and series from every library or folder, Recently Added first, 100 at a time: scrolling past the 100th loads the next page. `library.type` narrows to Movies or Series, `library.sort` orders by Recently Added, Name or Year.
- `home-rows` puts each source's rows above the add-ons' rows, each with at most 20 titles, newest first, then `shelf.seeAll`, which pushes Library with that source picked; Menu returns to Home.
- `library-entry` shows `library.browse` after the menus while a source is picked.
- `settings-entry` opens the same root from Settings › Sources › a source › Browse.
- `jellyfin` lists Home Videos, Movies and Shows, then a library's titles as posters.
- `webdav` walks Shows › Pioneer One (2010) [imdbid-tt1748166] › Season 01 to the episode files.
- `open` opens a title's or an episode's show's details and plays through streams.
- `failed` shows the error with Try Again when the server does not answer; Try Again lists the folder once it does.
- `back` returns one folder per Menu, to the screen browsing started from.

## How to get to it (user POV)

- Library › the picker › a source › Browse Folders › folders › a title or episode.
- Home › a source's row › See All.
- Settings › Sources › a source › Browse.

## Driving it with tv.sh

Preconditions:

- `scripts/dev-sources.sh up` is running, and `$T launch -STREMIO_SOURCES '[…both dev sources…]'` (see `SKILL.md`) added them.

- **Home rows.** After Welcome, press down from the hero: the first rows are the sources' (the dev WebDAV folder's Home Videos, Movies, Paging Test, Shows, Untagged Shows, and the Jellyfin server's Home Videos, Movies, Shows, in the order the sources were added), then Free Movies and the add-ons' rows. On Paging Test, `$T focus shelf.seeAll right 25`: the poster before it is Test Clip 131 (150 down to 131). `$T select` logs `push library(<source>)`; `$T text library.picker` prints the source's name and `library.sort` `Sort: Recently Added`.
- **Library picker.** `$T focus books.vertical right`, `$T remote down` (focus lands on a menu while Your Library is empty), `$T focus library.picker left 3`, `$T select`: the list reads Your Library, then each source. Down and select picks one; the grid fills with its titles. Press down about 20 times through the WebDAV source's grid: posters past the 100th (Test Clip 033 and below) load as you go, and the log reads `LibraryFeature ← loadMore`. Pick Your Library again for the menus and sorts it had before.
- **Library entry.** With a source picked, `$T focus library.browse right 3`, `$T select` opens the source; focus lands on the first `browser.folder` (`Home Videos`).
- **Jellyfin.** On the Jellyfin source, down to `Movies`, select: posters `poster.tt1727587` (Sintel) and the other three films. `$T focus poster.tt1727587 right`, select: Details with `details.play` focused; select, then down to the source's `streams.row` and select. `$T text player.status` reads `… · playing · 1280×720 …`, and the log loads `http://localhost:8196/Videos/9952106a…/stream?static=true…`.
- **WebDAV.** On the WebDAV source, down to `Shows`, select: one folder `Pioneer One (2010) [imdbid-tt1748166]`; select: `Season 01`; select: `browser.episode` rows `S1 E1 · Episode 1` to `S1 E3`. Selecting one pushes `details(series/tt1748166)`, the show's page.
- **Home video.** WebDAV › `Home Videos` lists Beach Day as a poster (`poster.takane-<source>-…`); Details › Play › the `localhost, Beach Day.mp4` row plays.
- **Back.** Menu from each level pops one folder; the log reads `pop to sourceFolder(<source>/<folder>)` down to `pop to sourceFolder(<source>/root)`, then the starting screen.
- **Failed.** `docker compose -f scripts/dev-sources/compose.yml stop webdav`, then `$T relaunch` (a listing read in the last five minutes would still answer). Settings › Sources › `localhost, WebDAV` › `source.browse`: `Couldn't Open localhost`, `The server didn't answer. …`, focus on `browser.retry`. `docker compose -f scripts/dev-sources/compose.yml start webdav`, `$T select`: the folders list.
- **Proof.** `$T evidence browse-<step>` after each step.

## Gotchas

- Up from Library's grid lands on `library.picker`, and up again on the tab bar; reach `library.type`, `library.sort` and `library.browse` with right from the picker. On a short row, down from Home's hero can land on `shelf.seeAll`, the card under the focused column.
- The dev servers name both sources `localhost` (WebDAV) and the Jellyfin container's id; the picker lists them in the order they were added.
- A source's listing answers for five minutes, so stopping a server shows nothing failed until a relaunch or the listing ages.
- Coming back to a folder restores focus to the row you left, not the first one; read `$T focused` before selecting.
- Season folders list episode files, not posters; the episode file opens the show's page, which has no per-episode focus.
