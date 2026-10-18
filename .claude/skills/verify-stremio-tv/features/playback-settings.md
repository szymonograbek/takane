# Playback settings

Settings › Playback sets the subtitle and audio languages streams start with. The choice is saved in core's profile settings, so it syncs with a signed-in account.

## Sub-features

- `languages` shows Subtitles and Audio with the current choice.
- `choose` opens a list with a checkmark on the current language and returns after a choice.
- `persist` writes `subtitlesLanguage` / `audioLanguage` into the profile.

## How to get to it (user POV)

- Settings › Playback.

## Driving it with tv.sh

Preconditions:

- Onboarding continued; focus on a tab.

- **Open.** `$T focus gearshape right`, press down 3 times, `$T select`. The rows read `Subtitles English`, `Audio English` on a fresh profile.
- **Choose.** `$T select`, press down 7 times (Polish), `$T select`. The row reads `Subtitles Polish`.
- **Persisted.** `grep -o '"subtitlesLanguage":"[a-z]*"' "$storage/profile.json"` prints `pol`.

## Gotchas

- Languages are ISO 639-2 codes as Stremio stores them (`eng`, `pol`, `fre`, `ger`).
