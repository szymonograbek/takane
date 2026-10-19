# Playback settings

Settings › Playback sets the audio languages streams start with (a first and, once one is set, a second), the skip interval of the back and forward buttons and arrows, and whether unwatched episodes hide spoilers. Settings › Subtitles sets the subtitle languages (a first and, once one is set, a second) and the subtitle style, beside a live preview drawn by the player's overlay. Choices are saved in core's profile settings, so they sync with a signed-in account.

## Sub-features

- `languages` shows Language under Audio on Playback, and Language on Subtitles, with the current choice; each shows Second Language once a language is set.
- `seekStep` shows Skip Interval on Playback; choosing 30 Seconds makes the player's buttons read Back/Forward 30 Seconds.
- `hideSpoilers` toggles Hide Spoilers under Episodes on Playback; a series' details then show every unwatched episode card with its still blurred and no overview, while watched episodes and the card titles stay as they were.
- `choose` opens a list with a checkmark on the current language and returns after a choice.
- `style` opens a style setting's choices; the preview shows the focused choice, and choosing one saves it and returns.
- `fileStyling` toggles Use File Styling; the preview's second line turns from the text color to cyan.
- `persist` writes `audioLanguage` / `secondaryAudioLanguage`, `seekTimeDuration` (milliseconds), `subtitlesLanguage` / `secondarySubtitlesLanguage` with `subtitlesAutoSelect` (false when subtitles are Off), the `subtitles*` style keys, `assSubtitlesStyling` and `hideSpoilers` into the profile.

## How to get to it (user POV)

- Settings › Playback, Settings › Subtitles.

## Driving it with tv.sh

Preconditions:

- Onboarding continued; focus on a tab.

- **Open Playback.** `$T focus gearshape right`, press down 3 times, `$T select`. The rows read `Language English`, `Second Language None`, `Skip Interval 10 Seconds` and `Hide Spoilers` off on a fresh profile.
- **Open Subtitles.** From Settings, `$T focus settings.subtitles down`, `$T select`. The rows read `Language English`, `Second Language None`, `Font System`, `Size 100%`, `Text White`.
- **Choose.** `$T focus subtitles.language down`, `$T select`, press down 7 times (Polish), `$T select`. The row reads `Language Polish`.
- **Skip interval.** `$T focus playback.seekStep down`, `$T select`, press down 3 times (30 Seconds), `$T select`. The row reads `Skip Interval 30 Seconds`.
- **Hide spoilers.** `$T focus playback.hideSpoilers down`, `$T select`; the toggle reads on. Open a series' Details as in [Find streams](./find-streams.md), searching for `game of thrones` and focusing `poster.tt0944947`. On a fresh profile nothing is watched, so `$T evidence` shows every episode card's still blurred and only its `1. Winter Is Coming`-style title under it, with no overview. Each `episode.<id>` still takes focus.
- **Style.** `$T focus subtitles.textColor down`, `$T select`, press down once (Yellow): `$T evidence` shows yellow text in `subtitles.preview` before selecting. `$T select`; the row reads `Text Yellow`.
- **File styling.** `$T focus subtitles.fileStyling down`, `$T select`: `$T evidence` shows the preview's second line in cyan; the toggle reads on.
- **Persisted.** `grep -o '"subtitlesLanguage":"[a-z]*"' "$storage/profile.json"` prints `pol`; `grep -o '"subtitlesTextColor":"[^"]*"' "$storage/profile.json"` prints `#FFE600FF`; `grep -o '"assSubtitlesStyling":[a-z]*' "$storage/profile.json"` prints `true`; after Skip interval, `grep -o '"seekTimeDuration":[0-9]*' "$storage/profile.json"` prints `30000`; after Hide spoilers, `grep -o '"hideSpoilers":[a-z]*' "$storage/profile.json"` prints `"hideSpoilers":true`.

## Gotchas

- Details load once per visit, so an episode watched while its details are open stays blurred until Details opens again.
- Languages are ISO 639-2 codes as Stremio stores them (`eng`, `pol`, `fre`, `ger`).
- A skip interval another Stremio app set that is not 5, 10, 15 or 30 s reads as 10 Seconds and is kept until another is chosen.
- A style value another Stremio app set that matches no preset reads as `Custom`. A font family the app does not know reads as System and is kept until another font is chosen.
