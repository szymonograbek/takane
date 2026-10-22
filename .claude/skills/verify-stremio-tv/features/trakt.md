# Trakt

A signed-in user connects Trakt on Settings › Account › Trakt by scanning a QR code with a phone, and disconnects it there. While Trakt is connected, what plays here reaches Trakt through Stremio's servers: a pause or stop saves the position on Trakt, and a play past about 80% lands in its history.

## Sub-features

- `trakt-status` reads Connected or Not Connected on the Account row and the Trakt screen.
- `trakt-scrobble` sends each play, pause and stop to Stremio's API, which passes it to Trakt.
- `trakt-connect` shows the QR code and waits for the account to be linked. Not driven here: it needs a phone.

## How to get to it (user POV)

- Settings › Account › Trakt, signed in.
- Any playback, with Trakt connected.

## Driving it with tv.sh

Preconditions:

- `STREMIO_TEST_EMAIL` and `STREMIO_TEST_PASSWORD` are set (environment or `.env.smoke`), for an account with Trakt linked. Without them, report this feature as not verified (no test account) and skip it.
- `$T launch --account` succeeded and Home shows.

- **Status.** `$T focus house up 4`, `$T focus gearshape right 6`, `$T select`, `$T focus settings.account down 6`, `$T select`, `$T focus settings.trakt down 6`. `$T text settings.trakt` prints `Trakt, Connected`. `$T select`: `$T focused` prints `Status, Connected`, and `trakt.disconnect` is below it. Leave with `$T remote menu` twice.
- **Scrobble.** Play anything as in [Playback](./playback.md) for about 20 s, pause on `player.playPause`, play again, then leave the player. The app log has `scrobble sent event="…"` for `playerPlaying`, `traktPlaying`, `traktPaused`, `playerStopped`, and nothing with `scrobble failed`. `$T trakt-check` prints the title paused at its percentage.

## Gotchas

- Never select `trakt.disconnect` unattended. It unlinks Trakt from the real account, and only a phone can link it again.
- This runs on a real account: playback moves its watch progress and leaves a paused entry on Trakt.
- Trakt numbers some seasons differently from IMDb, so Trakt can name another episode than the app (The Office S4E10 here is S4E6 on Trakt).
- History only gets plays past about 80%; a short test shows up as paused progress.
