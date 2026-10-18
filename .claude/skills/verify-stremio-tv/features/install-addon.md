# Install an add-on

The user types an add-on manifest URL; core fetches the manifest, installs the add-on, and the add-on appears in the list with a confirmation message. The install persists in the core profile.

## Sub-features

- `install-url` installs from a manifest URL typed on the tvOS keyboard.
- `install-list` shows the new add-on with its version in the add-on list.
- `install-persist` writes the add-on into the profile on disk.
- `install-error` shows core's error text for a bad URL.

## How to get to it (user POV)

- Focus the "Manifest URL" field under the add-on list (focused at launch), press select, type, choose done.

## Driving it with tv.sh

Preconditions:

- Fresh run from `$T launch`; AIOStreams is not installed.
- `STREMIO_SMOKE_ADDON_URL` available.

- **Type URL.** Run `$T type-env addons.manifestURL left STREMIO_SMOKE_ADDON_URL`. Prints `focused addons.manifestURL` and `typed <n> chars`.
- **Confirmation.** Run `$T wait-text "Installed AIOStreams | ElfHosted" 30`. Found.
- **Listed.** Run `$T wait-text "AIOStreams | ElfHosted 2.36.0" 5`. Found.
- **Persisted.** Run `source build/verify/current.env; grep -o '"name":"AIOStreams[^"]*"' "$storage/profile.json"`. Prints `"name":"AIOStreams | ElfHosted"`.
- **Error path.** Run `$T type addons.manifestURL left "https://example.invalid/manifest.json"`, wait 3 s, then `$T text addons.status`. Observed `manifest failed: {"code":1,"message":"Failed to fetch: A server with the specified hostname could not be found."}`.
- **Proof.** Run `$T evidence install-addon`.

## Gotchas

- Do not press select on the field and then type: the press lands on the keyboard's first key and prefixes an `a`. `type`/`type-env` fill the focused field directly, by a ref from a raw snapshot.
- Reading `addons.status` while the keyboard is still closing returns empty; wait a few seconds.
- The keyboard's done button is below the keys; the helper presses down until it is focused.
- Installing an already-installed URL succeeds immediately without a network call.
- The add-on version (2.36.0) is the server's; update the label if AIOStreams upgrades.
