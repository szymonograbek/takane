# Library and calendar

A title's Details page adds it to the user's library or takes it out. The Library tab lists the library's titles as posters, filtered by type and sorted by recently watched, name or unwatched first; a long press on a poster removes it. The Calendar tab lists the upcoming episodes of the library's series, one row per day, titled by how far off the day is.

## Sub-features

- `add-to-library` toggles Details' `details.library` between "Add to Library" and "In Library". Core writes the item to `library_recent.json` (`removed: false`).
- `library-grid` shows every title in the library, most recently watched or added first, or the "Your Library Is Empty" state with the menus still focusable. A type filter with no titles shows "No Movies in Your Library" (or the type's name) with Show All.
- `library-filter` narrows the grid to one type (`library.type`: All Types, then only the types the library holds, such as Movies) and orders it (`library.sort`: Recently Watched, Name, Unwatched First).
- `library-remove` removes a title from a poster's context menu. Core keeps it in `library_recent.json` with `removed: true`.
- `calendar` lists, from today on, the episodes of the library's series by day: "Today", "Tomorrow", "In 2 days (Wednesday)" up to 13 days, "In 3 weeks (Wednesday)" up to 59 days, then "In 2 months (Thursday, January 7)". Each card opens the show. It loads again every time the tab appears, so a title added or removed shows up there. "Nothing Coming Up" when no series in the library has dated episodes ahead.

## How to get to it (user POV)

- Search → a title → Add to Library. Then the Library tab, or the Calendar tab for a series that is still airing.

## Driving it with tv.sh

Preconditions:

- [Onboarding](./onboarding.md) continued without an account. No debrid add-on is needed.

- **Add.** Search for a series still airing (check Cinemeta, `https://v3-cinemeta.strem.io/meta/series/<id>.json`, for `videos` released after today; NCIS `tt0364845` airs weekly in autumn). `$T focus poster.<id> down 6` (the row may need `left`), `$T select`, wait 6 s, `$T focus details.library right 3`, `$T select`. `$T text details.library` prints `In Library`. Select again for `Add to Library`.
- **Library.** From the tab bar, `$T focus books.vertical left 4` (or `right`), `$T remote down`: focus lands on the first poster (on a menu when the library is empty). The ax snapshot lists a `poster.<id>` per title.
- **Filter and sort.** `$T focus library.type up 2`. `$T select` opens the Show list with All Types focused; it lists only the types in the library, so read the row labels before pressing down. `$T remote down` and `$T select` picks the next type (Movies with only a movie added), closes the list and leaves the button focused. `$T text library.type` prints `Movies`. `$T remote right`, `$T select`, `$T remote down`, `$T select` picks Name; `$T text library.sort` prints `Sort: Name`.
- **Remove.** `$T focus poster.<id> down 3`, then `agent-device tv-remote longpress select --duration-ms 1500 --session stremio-tv-verify` opens the context menu with Remove from Library focused; `$T select`. The poster leaves the grid and `grep -o '"removed":[a-z]*' "$storage/library_recent.json"` prints `"removed":true`.
- **Calendar.** `$T focus calendar right 3`, wait up to 8 s. The ax snapshot lists the day labels (`"label":"In 2 days (Wednesday)"`) and an `upcoming.<video id>` per episode. `$T remote down` focuses the first card (label `NCIS, S24 · E3 · <episode name>`); select opens the show's Details.

## Gotchas

- After Remove from Library nothing is focused until the next arrow press; tvOS does not move focus to a neighbor after a context menu's item disappears.
- Calendar labels depend on today's date; read them from the snapshot instead of hard-coding them.
