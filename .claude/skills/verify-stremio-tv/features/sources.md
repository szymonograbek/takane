# Media sources

In Settings › Sources the user adds their own Jellyfin server or WebDAV folder by typing its address and login. The app signs in before it keeps the source, shows a failed sign-in under the form, and goes back to the list once it succeeds. Each source's libraries become rows on Home, and its files show in stream lists labeled with the source's name. A source's page renames it, changes its address or login, and removes it after a confirmation. Sources live in this device's Keychain, apart from the Stremio account, so they survive a relaunch and show signed in or out.

## Sub-features

- `list` shows each source as `<name>, <kind>` above the two add rows; with none, only the add rows and the note show.
- `add` signs in to a Jellyfin server or WebDAV folder and lists it; its libraries become Home rows.
- `add-error` shows the failure under the form, with focus kept on Save: wrong login, an address that is not the chosen kind, no answer.
- `rename` sets the name on Edit; stream lists label the source's files with it.
- `remove` asks "Remove <name>?" and removes the source; its Home rows and streams go.
- `persist` keeps the sources across a relaunch.
- `folder-kinds` shows a WebDAV source's top-level folders with what each holds (Movies, Shows, Other Videos), suggested from its videos until the user picks one. Titles are looked up by name only in Movies and Shows; a home video named like a film stays local in Other Videos. Changing a kind lists the source again, and the choice survives a relaunch.
- `nfo` names a title from a Kodi `.nfo` file beside it (`movie.nfo`, `tvshow.nfo`, `<video>.nfo`) before its tag or name.

## How to get to it (user POV)

- Settings › Sources › Add Jellyfin Server or Add WebDAV Folder, fill the address, username and password, then Save.
- Settings › Sources › a source › Edit or Remove.

## Driving it with tv.sh

Preconditions:

- `scripts/dev-sources.sh up` is running: Jellyfin at `http://localhost:8196`, WebDAV at `http://localhost:8197`, login `takane` / `takane-dev`.
- No stored sources: `xcrun simctl keychain "$(scripts/tvos-simulator.sh)" reset` before `$T launch` (no `-STREMIO_SOURCES`).

- **Open.** `$T focus welcome.continue right`, `$T select`, `$T focus gearshape right`, `$T focus settings.sources down`. `$T text settings.sources` reads `Sources, None`. `$T select`; focus lands on `sources.addJellyfin`.
- **Add Jellyfin.** `$T select`, then `$T type sourceForm.url down http://localhost:8196`. Done on the address keyboard opens the username keyboard, and its next opens the password keyboard (see Gotchas): type `takane`, press down until `$T focused` prints `next`, select; type `takane-dev`, press down to `done`, select. `$T focus sourceForm.save down`, `$T select`. Within 5 s the list is back with focus on Add Jellyfin Server, and the first `sources.row` reads `7a9996a9a971, Jellyfin` (the dev server's name is its container id).
- **Home rows.** `$T remote menu` twice, `$T focus house left`, press down: Home Videos (Beach Day) and Movies (Sintel, `poster.tt1727587`) rows follow the add-on rows. The log reads `listed 1 source add-ons in core, [3] catalogs`.
- **Wrong password.** On Sources, `$T focus sources.addWebDAV down`, `$T select`, type `http://localhost:8197`, `takane`, `wrong`, Save. `$T text sourceForm.error` reads `The username or password is incorrect.` and `$T focused` prints `sourceForm.save`. `$T type sourceForm.password up takane-dev`, Save: the list shows `localhost, WebDAV`.
- **Wrong kind.** Add WebDAV Folder with `http://localhost:8196`: `This address answers, but not as a WebDAV folder. Check the address and its port.`
- **Saving.** Address `http://10.255.255.1:8197`: right after Save, `sourceForm.save` holds a spinner and keeps focus, then `The server didn't answer. …`.
- **Rename.** Select the Jellyfin row, `$T focus source.edit down`, `$T select`; focus lands on `sourceForm.name`. `$T type sourceForm.name down "Home Server"`, then `$T remote menu` to leave the address keyboard it chains to. Save goes back to the source page; `$T text source.name` reads `Name, Home Server`. Sintel's stream list (Home › Movies › Sintel › Play) has a `streams.row` labeled `Home Server, Sintel (2010).mkv …`.
- **Remove.** Select the WebDAV row, `$T focus source.remove down`, `$T select`: "Remove localhost?" with Remove focused. `$T select` goes back to the list with only Home Server. Sintel's stream list no longer has a `localhost, …` row, and the log reads `removed source <id>` then `listed 1 source add-ons`.
- **Persisted.** `$T relaunch`, then Settings: `Sources, 1 source`, and the list shows `Home Server, Jellyfin`.
- **Nfo.** With only the WebDAV source (`$T launch -STREMIO_SOURCES '[{"kind":"webdav",…}]'`), Home › Movies › `poster.tt2285752` › Play lists `localhost, Tears of Steel.mkv` (named only by `Movies/Tears of Steel/movie.nfo`) beside `localhost, Tears of Steel (2012).mkv`, and it plays. The log reads `GET Movies/Tears of Steel/movie.nfo` once per launch, not again when the source is listed again.
- **Folder kinds.** Settings › Sources › `localhost, WebDAV` › `source.folders`: `sourceFolders.row` rows read `Home Videos, Other Videos`, `Movies, Movies`, `Shows, Shows`, `Untagged Shows, Shows`, focus on the first. Browse › Home Videos shows `Night of the Living Dead` as `poster.takane-<source>-…`, with the add-on's own details. Back on Folders, select Home Videos, press up twice to `Movies`, select: the row reads `Home Videos, Movies` and the log `source <id> holds movies in Home Videos`, then `listed 1 source add-ons in core, [4] catalogs`. Browse › Home Videos now shows `poster.tt0063350`, whose streams list `localhost, Night of the Living Dead (1968).mp4` and `localhost, Night.of.the.Living.Dead.1968.720p.mkv`. Choosing Other Videos again makes it local again. `$T relaunch`: Folders still reads the chosen kind.
- **Proof.** `$T evidence sources-<step>` after each step.

## Gotchas

- tvOS chains the form's keyboards: done or next on one field opens the next field's keyboard. `$T type` handles only the first; type the rest with `agent-device type <text> --session stremio-tv-verify`, then press down until `$T focused` prints `next` or `done` and select. `$T remote menu` leaves a chained keyboard without changing its field.
- `$T type` replaces a field's text, so retyping a password after a failure needs no clearing.
- Sources stay in the simulator's Keychain across runs and `cleanup`; reset it before a run that starts from none.
- rclone caches folder listings for five minutes; after `scripts/dev-sources.sh up` adds media, `docker restart takane-dev-sources-webdav-1` makes it list them at once.
- The source rows on Home share library names (Movies, Home Videos, Shows) across servers; tell sources apart by the stream labels.
