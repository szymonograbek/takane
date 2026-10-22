# Install an add-on

In Settings › Add-ons the user picks Install Add-on, types a manifest URL, and core fetches and installs it. The screen returns to the list, which shows the new add-on and its version. Long-pressing a removable add-on offers Remove, after a confirmation. The install persists in the core profile.

## Sub-features

- `install-url` installs from a manifest URL typed on the tvOS keyboard.
- `install-list` shows the new add-on with its version in the add-on list.
- `install-persist` writes the add-on into the profile on disk.
- `install-error` shows core's error text for a bad URL.
- `remove` asks "Remove <name>?" and uninstalls; official add-ons are not removable.
- `move` moves an add-on to the top, up or down from the same menu; the new order persists in the profile.

## How to get to it (user POV)

- Settings › Add-ons › Install Add-on, type the URL, choose done.

## Driving it with tv.sh

Preconditions:

- Fresh run from `$T launch`; AIOStreams is not installed.
- `STREMIO_SMOKE_ADDON_URL` available.

- **Open.** `$T focus welcome.continue right`, `$T select`, `$T focus gearshape right`, `$T focus settings.addons down`, `$T select`, `$T select` (Install Add-on).
- **Type URL.** Run `$T type-env addons.manifestURL down STREMIO_SMOKE_ADDON_URL`. Confirming the keyboard submits the install; `addons.submit` (Install, below the field) does the same.
- **Listed.** Within 15 s the screen is back on the list with focus on Install Add-on; press down 7 times and `$T focused` prints `AIOStreams | ElfHosted, 2.36.0`. After `$T remote menu`, `$T text settings.addons` reads `Add-ons, 7 installed`.
- **Remove.** Selecting a row does nothing. Long-press the focused AIOStreams row (`agent-device tv-remote longpress select --duration-ms 1500 --session stremio-tv-verify`) for a context menu with Remove; `$T select` opens "Remove AIOStreams | ElfHosted?" with **Remove** focused, so a second select uninstalls. `$T remote menu` cancels. The footer reads "… To move or remove one, press and hold it. …"
- **Persisted.** Run `source build/verify/current.env; grep -o '"name":"AIOStreams[^"]*"' "$storage/profile.json"`. Prints `"name":"AIOStreams | ElfHosted"`.
- **Error path.** In Install Add-on, type `https://example.invalid/manifest.json`, wait 3 s, then `$T text addons.status`. It starts `The add-on's manifest could not be loaded:`.
- **Move.** On a fresh profile, focus OpenSubtitles v3 (fifth row) and long-press it. The menu lists Move to Top (focused), Move Up, Move Down and Remove; `$T select` moves it to the top with focus on it. The first row's menu has no Move to Top or Move Up, so `$T focused` prints `arrow.down`. Run `source build/verify/current.env; grep -o '"name":"[^"]*"' "$storage/profile.json" | head -1`. Prints `"name":"OpenSubtitles v3"`.
- **Proof.** Run `$T evidence install-addon`.

## Gotchas

- Do not press select on the field and then type: the press lands on the keyboard's first key and prefixes an `a`. `type`/`type-env` fill the focused field directly, by a ref from a raw snapshot.
- Reading `addons.status` while the keyboard is still closing returns empty; wait a few seconds.
- The keyboard's done button is below the keys; the helper presses down until it is focused.
- Installing an already-installed URL succeeds immediately without a network call.
- The install status is app-wide: reopening Install Add-on shows the last install's status (`Installed AIOStreams | ElfHosted`, or the last error) over an empty field. Read `addons.status` only after typing in this visit.
- The add-on version (2.36.0) is the server's; update the label if AIOStreams upgrades.
