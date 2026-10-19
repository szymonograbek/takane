# Playback settings

Settings › Playback sets the audio languages streams start with (a first and, once one is set, a second) and the skip interval of the back and forward buttons and arrows. Settings › Subtitles sets the subtitle languages (a first and, once one is set, a second) and the subtitle style, beside a live preview drawn by the player's overlay. Choices are saved in core's profile settings, so they sync with a signed-in account.

## Sub-features

- `languages` shows Language under Audio on Playback, and Language on Subtitles, with the current choice; each shows Second Language once a language is set.
- `seekStep` shows Skip Interval on Playback; choosing 30 Seconds makes the player's buttons read Back/Forward 30 Seconds.
- `choose` opens a list with a checkmark on the current language and returns after a choice.
- `style` opens a style setting's choices; the preview shows the focused choice, and choosing one saves it and returns.
- `fileStyling` toggles Subtitle File Styling; the preview's second line turns from the text color to cyan.
- `persist` writes `audioLanguage` / `secondaryAudioLanguage`, `seekTimeDuration` (milliseconds), `subtitlesLanguage` / `secondarySubtitlesLanguage` with `subtitlesAutoSelect` (false when subtitles are Off), the `subtitles*` style keys and `assSubtitlesStyling` into the profile.

## How to get to it (user POV)

- Settings › Playback, Settings › Subtitles.

## Driving it with tv.sh

Preconditions:

- Onboarding continued; focus on a tab.

- **Open Playback.** `$T focus gearshape right`, press down 3 times, `$T select`. The rows read `Language English`, `Second Language None` and `Skip Interval 10 Seconds` on a fresh profile.
- **Open Subtitles.** From Settings, `$T focus settings.subtitles down`, `$T select`. The rows read `Language English`, `Second Language None`, `Size 100%`, `Text Color White`.
- **Choose.** `$T focus subtitles.language down`, `$T select`, press down 7 times (Polish), `$T select`. The row reads `Language Polish`.
- **Skip interval.** `$T focus playback.seekStep down`, `$T select`, press down 3 times (30 Seconds), `$T select`. The row reads `Skip Interval 30 Seconds`.
- **Style.** `$T focus subtitles.textColor down`, `$T select`, press down once (Yellow): `$T evidence` shows yellow text in `subtitles.preview` before selecting. `$T select`; the row reads `Text Color Yellow`.
- **File styling.** `$T focus subtitles.fileStyling down`, `$T select`: `$T evidence` shows the preview's second line in cyan; the toggle reads on.
- **Persisted.** `grep -o '"subtitlesLanguage":"[a-z]*"' "$storage/profile.json"` prints `pol`; `grep -o '"subtitlesTextColor":"[^"]*"' "$storage/profile.json"` prints `#FFE600FF`; `grep -o '"assSubtitlesStyling":[a-z]*' "$storage/profile.json"` prints `true`; after Skip interval, `grep -o '"seekTimeDuration":[0-9]*' "$storage/profile.json"` prints `30000`.

## Gotchas

- Languages are ISO 639-2 codes as Stremio stores them (`eng`, `pol`, `fre`, `ger`).
- A skip interval another Stremio app set that is not 5, 10, 15 or 30 s reads as 10 Seconds and is kept until another is chosen.
- A style value another Stremio app set that matches no preset reads as `Custom`. A font family the app does not know reads as System and is kept until another font is chosen.
