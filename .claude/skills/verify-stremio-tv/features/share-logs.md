# Share logs

Settings › About › Share Logs serves the app's logs over HTTP on the local network while the screen is up. It shows a QR code and the address, such as `http://192.168.1.20:8080/k7fm`, which a phone or computer on the same network opens to download the logs of the chosen time range. Leaving the screen stops sharing.

## Sub-features

- `link` shows the address in `shareLogs.url` and as a QR code. A `GET` of it answers `200` with `Content-Disposition: attachment; filename="takane-logs-<yyyyMMdd-HHmm>.log"` and a body starting `Takane <version> (<build>), Debug build`, then `Last Hour: <start> to <end>`.
- `window` changes the time range; the address stays and the next download's header names the new range.
- `notFound` answers `404` to any other path or method.
- `stop` closes the listener when the screen goes; the address then refuses connections.

## How to get to it (user POV)

- Settings › About › Share Logs.

## Driving it with tv.sh

Preconditions:

- Onboarding continued; focus on a tab.

- **Open.** `$T focus gearshape right`, `$T focus settings.about down`, `$T select`, `$T focus about.shareLogs down`, `$T select`. `$T text shareLogs.url` prints the address. The simulator shares the Mac's network, so `curl -sD - <address>` from the Mac fetches it (outside the command sandbox).
- **Window.** With `shareLogs.window` focused, `$T select`, `$T remote down`, `$T select`. The button reads `Last 6 Hours`; `$T text shareLogs.url` prints the same address, and the next download's second line starts `Last 6 Hours:`.
- **Log key** (Release build only). `shareLogs.key` reads `XXXX-XXXX-XXXX` under a placeholder until `$T focus shareLogs.showKey down`, `$T select`; it then reads the key and the button `Hide Log Key`. Leaving and reopening the screen hides it again. `swift scripts/reveal-log.swift <download> <key>` reveals the download's codes.
- **Not found.** `curl -sD - <address with another path>` prints `HTTP/1.1 404 Not Found`.
- **Stop.** `$T remote menu`. `curl -m 5 <address>` fails with `Couldn't connect to server`.

## Gotchas

- `focus` may report the About and Share Logs rows by their labels instead of their ids; the press still lands on them.
- Archived sessions live in `Library/Caches/Logs/sessions/` beside `app.log`. To prove the time range filters, add a file there whose lines and modification time are two hours old: Last Hour leaves it out, Last 6 Hours includes it.
