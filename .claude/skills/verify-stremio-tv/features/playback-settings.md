# Playback settings

Settings › Playback sets the audio languages streams start with (a first and, once one is set, a second), the skip interval of the back and forward buttons and arrows, when the Up Next card shows and whether the next episode autoplays, and whether unwatched episodes hide spoilers. Settings › Subtitles sets the subtitle languages (a first and, once one is set, a second) and the subtitle style, beside a live preview drawn by the player's overlay. Choices are saved in core's profile settings, so they sync with a signed-in account; Skip Data is the exception, kept on this device.

## Sub-features

- `languages` shows Language under Audio on Playback, and Language on Subtitles, with the current choice; each shows Second Language once a language is set.
- `seekStep` shows Skip Interval on Playback; choosing 30 Seconds makes the player's buttons read Back/Forward 30 Seconds.
- `upNext` shows Up Next Card under Next Episode on Playback (Off, 10, 20, 35 or 60 Seconds Before End) and the Autoplay Next Episode toggle.
- `hideSpoilers` toggles Hide Spoilers under Episodes on Playback; a series' details then show every unwatched episode card with its still blurred and no overview, while watched episodes and the card titles stay as they were.
- `choose` opens a list with a checkmark on the current language and returns after a choice.
- `style` opens a style setting's choices; the preview shows the focused choice, and choosing one saves it and returns.
- `fileStyling` toggles Use File Styling; the preview's second line turns from the text color to light blue.
- `moreOptions` keeps Skip Data and Hide Spoilers on Playback, and Font, Bold, Text, Outline, Opacity and Use File Styling on Subtitles, behind More Options. It starts collapsed, shows the rows below it with focus kept on it, and while collapsed counts the hidden settings changed from their defaults (`2 changed`).
- `notes` puts a one-sentence note in plain words under each section whose rows are not self-evident, on every settings page.
- `reset` (Reset Style) confirms, then restores the default style; it is disabled while the style is the default.
- `persist` writes `audioLanguage` / `secondaryAudioLanguage`, `seekTimeDuration` and `nextVideoNotificationDuration` (milliseconds, 0 for Off), `bingeWatching` (autoplay), `subtitlesLanguage` / `secondarySubtitlesLanguage` with `subtitlesAutoSelect` (false when subtitles are Off), the `subtitles*` style keys, `assSubtitlesStyling` and `hideSpoilers` into the profile.

## How to get to it (user POV)

- Settings › Playback, Settings › Subtitles.

## Driving it with tv.sh

Preconditions:

- Onboarding continued; focus on a tab.

- **Open Playback.** `$T focus gearshape right`, `$T focus settings.playback down`, `$T select`. On a fresh profile the rows read `Language, English`, `Second Language, None`, `Skip Interval, 10 Seconds`, `Up Next Card, 35 Seconds Before End`, `Autoplay Next Episode, On` and `More Options`. Selecting More Options adds `Skip Data, IntroDB` and `Hide Spoilers, Off` below it.
- **Open Subtitles.** From Settings, `$T focus settings.subtitles down`, `$T select`. The rows read `Language, English`, `Second Language, None`, `Size, 100%`, `Position, 5%`, `Background, None`, `More Options` and `Reset Style`. Selecting More Options adds `Font, System`, `Bold, Off`, `Text, White`, `Outline, Black`, `Opacity, 100%` and `Use File Styling, Off` below it.
- **More Options.** `$T focus settings.moreOptions down`, `$T select`; `$T focused` still prints `settings.moreOptions` and the hidden rows follow it. Change two of them (Bold and Use File Styling), `$T focus settings.moreOptions up`, `$T select`: the row reads `More Options, 2 changed` and its raw snapshot value is `Collapsed, 2 changed`. Coming back from a hidden row's list keeps the section open.
- **Choose.** `$T focus subtitles.language down`, `$T select`, focus lands on English; press down 6 times (Polish), `$T select`. The row reads `Language, Polish`.
- **Skip interval.** `$T focus playback.seekStep down`, `$T select`, focus lands on 10 Seconds; press down 2 times (30 Seconds), `$T select`. The row reads `Skip Interval, 30 Seconds`.
- **Up next.** `$T focus playback.upNextNotice down`, `$T select`, press down once (60 Seconds Before End), `$T select`. `$T focus playback.autoplayNext down`, `$T select`: it reads `Autoplay Next Episode, Off`.
- **Hide spoilers.** Open More Options, then `$T focus playback.hideSpoilers down`, `$T select`; the toggle reads on. Open a series' Details as in [Find streams](./find-streams.md), searching for `pioneer one` and focusing `poster.tt1748166`. On a fresh profile nothing is watched, so `$T evidence` shows every episode card's still blurred and only its `1. Earthfall`-style title under it, with no overview. Each `episode.<id>` still takes focus.
- **Style.** Open More Options, then `$T focus subtitles.textColor down`, `$T select`, press down once (Yellow): `$T evidence` shows yellow text in `subtitles.preview` before selecting. `$T select`; the row reads `Text, Yellow`.
- **File styling.** Open More Options, then `$T focus subtitles.fileStyling down`, `$T select`: `$T evidence` shows the preview's second line in light blue; the toggle reads on.
- **Reset.** `$T focus subtitles.reset down`, `$T select`, `$T select` (Reset Style in the confirmation). `Text, White` and `Use File Styling, Off` again; the language stays.
- **Persisted.** `grep -o '"subtitlesLanguage":"[a-z]*"' "$storage/profile.json"` prints `pol`; `grep -o '"subtitlesTextColor":"[^"]*"' "$storage/profile.json"` prints `#FFE600FF`; `grep -o '"assSubtitlesStyling":[a-z]*' "$storage/profile.json"` prints `true`; after Skip interval, `grep -o '"seekTimeDuration":[0-9]*' "$storage/profile.json"` prints `30000`; after Up next, `grep -o '"nextVideoNotificationDuration":[0-9]*\|"bingeWatching":[a-z]*' "$storage/profile.json"` prints `60000` and `false`; after Hide spoilers, `grep -o '"hideSpoilers":[a-z]*' "$storage/profile.json"` prints `"hideSpoilers":true`.

## Gotchas

- `xcrun simctl ui <udid> content_size` is unsupported on the tvOS runtime. For Large Text, open the simulator's Settings app (`agent-device open com.apple.TVSettings`), go to Accessibility › Display & Text Size › Text Size and press right to the end of the slider (4.00); press left back to 0.00 afterwards.

- Skip Data is stored on the device, not the profile, so a fresh profile shows the last run's choice (IntroDB until one was picked); `cleanup` does not reset it.
- Details load once per visit, so an episode watched while its details are open stays blurred until Details opens again.
- Languages are ISO 639-2 codes as Stremio stores them (`eng`, `pol`, `fre`, `ger`).
- A skip interval another Stremio app set that is not 5, 10, 15 or 30 s reads as 10 Seconds and is kept until another is chosen.
- A style value another Stremio app set that matches no preset reads as `Custom`. A font family the app does not know reads as System and is kept until another font is chosen.
