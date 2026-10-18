# Core status

When the app starts, stremio-core loads the profile and the screen shows core as Ready, the account (anonymous until login exists) and the installed add-ons.

## Sub-features

- `core-ready` shows "Ready" once core has loaded the profile.
- `core-account` shows "Account: anonymous" without a login.
- `core-default-addons` lists the six default add-ons on a fresh profile.

## How to get to it (user POV)

- Open the app. The status is the first thing in the left column.

## Driving it with tv.sh

Preconditions:

- No run is active (`build/verify/current.env` absent).

- **Launch.** Run `$T launch`. Doctor prints `app foreground, core ready` and `profile: fresh (verify-<run-id>)`.
- **Account.** Run `$T wait-text "Account: anonymous" 5`. Prints `found: Account: anonymous`.
- **Default add-ons.** Run `$T wait-text "Cinemeta 3.0.14" 5` and `$T wait-text "Local Files (without catalog support) 1.10.0" 5`. Both found.
- **Proof.** Run `$T evidence core-status`. The screenshot shows Ready with a green check and the add-on list.

## Gotchas

- Add-on versions come from the network on first install of defaults; if Cinemeta updates, the label changes. Match on the version shown in the screenshot and update this file.
- A failed core start shows a red error instead of Ready; read `app.log` for `core failed to start`.
