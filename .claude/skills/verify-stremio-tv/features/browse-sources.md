# Browse sources

The user walks a source's folders the way the server arranges them and opens any title from there. Library shows a button per source; a source's page in Settings offers Browse. A Jellyfin source's root lists its libraries, and a library its titles and folders. A WebDAV source's root lists its top folders; a movie's own folder shows as the movie, and a season folder lists its episode files. A title opens its details, an episode file opens its show's details, and from there streams and the player work as anywhere else. Menu goes back one folder at a time.

## Sub-features

- `library-entry` shows `library.source` buttons below Library's filters, one per source.
- `settings-entry` opens the same root from Settings › Sources › a source › Browse.
- `jellyfin` lists Home Videos, Movies and Shows, then a library's titles as posters.
- `webdav` walks Shows › Pioneer One (2010) [imdbid-tt1748166] › Season 01 to the episode files.
- `open` opens a title's or an episode's show's details and plays through streams.
- `failed` shows the error with Try Again when the server does not answer; Try Again lists the folder once it does.
- `back` returns one folder per Menu, to the screen browsing started from.

## How to get to it (user POV)

- Library › a source's button › folders › a title or episode.
- Settings › Sources › a source › Browse.

## Driving it with tv.sh

Preconditions:

- `scripts/dev-sources.sh up` is running, and `$T launch -STREMIO_SOURCES '[…both dev sources…]'` (see `SKILL.md`) added them.

- **Library entry.** `$T focus welcome.continue right`, `$T select`, `$T focus books.vertical right`, press down until `$T focused` prints `library.source`; left and right move between sources. `$T select` opens the source; focus lands on the first `browser.folder` (`Home Videos`).
- **Jellyfin.** On the Jellyfin source, down to `Movies`, select: posters `poster.tt1727587` (Sintel) and the other three films. `$T focus poster.tt1727587 right`, select: Details with `details.play` focused; select, then down to the source's `streams.row` and select. `$T text player.status` reads `… · playing · 1280×720 …`, and the log loads `http://localhost:8196/Videos/9952106a…/stream?static=true…`.
- **WebDAV.** On the WebDAV source, down to `Shows`, select: one folder `Pioneer One (2010) [imdbid-tt1748166]`; select: `Season 01`; select: `browser.episode` rows `S1 E1 · Episode 1` to `S1 E3`. Selecting one pushes `details(series/tt1748166)`, the show's page.
- **Home video.** WebDAV › `Home Videos` lists Beach Day as a poster (`poster.takane-<source>-…`); Details › Play › the `localhost, Beach Day.mp4` row plays.
- **Back.** Menu from each level pops one folder; the log reads `pop to sourceFolder(<source>/<folder>)` down to `pop to sourceFolder(<source>/root)`, then the starting screen.
- **Failed.** `docker compose -f scripts/dev-sources/compose.yml stop webdav`, then `$T relaunch` (a listing read in the last five minutes would still answer). Settings › Sources › `localhost, WebDAV` › `source.browse`: `Couldn't Open localhost`, `The server didn't answer. …`, focus on `browser.retry`. `docker compose -f scripts/dev-sources/compose.yml start webdav`, `$T select`: the folders list.
- **Proof.** `$T evidence browse-<step>` after each step.

## Gotchas

- A source's listing answers for five minutes, so stopping a server shows nothing failed until a relaunch or the listing ages.
- Coming back to a folder restores focus to the row you left, not the first one; read `$T focused` before selecting.
- Season folders list episode files, not posters; the episode file opens the show's page, which has no per-episode focus.
