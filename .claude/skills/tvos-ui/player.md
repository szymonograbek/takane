# Video player UX

Apple's preferred player is the system one: `AVPlayerViewController` (UIKit) or `VideoPlayer` (SwiftUI). A custom player **mirrors** it, because people bring the same habits to every app. Each rule below holds for both.

## Behavior

- Play/Pause plays and pauses. Click then swipe scrubs. Back leaves the player. Space on a keyboard plays and pauses.
- Taps from a resting thumb do nothing during playback; presses act.
- Video keeps its original aspect ratio. Fill the screen for 2:1–2.40:1 video; fit it for 16:9 and other ratios up to 2:1, and for anything wider than 2.40:1.
- **Resume** silently from the last position.
- **Loading:** go straight into content. When loading takes over 2 s, show a black screen with a centered spinner and minimal branding, and start playback once enough is buffered.
- **Arriving from the TV app:** it fades to black and skips your launch screen; show black, then content, with no splash or detail screen in between. When the request names a profile, switch to it first.
- **Exit:** show the title's detail screen with a resume option (or the menu listing it). Prepare that screen as playback starts, in case people leave at once.
- Transport controls carry only the most useful actions, each one or two steps deep. Supporting content goes in tabs below them (Info, Episodes, Chapters).
- Overlays on video stay small and short-lived, preferably translucent SDR (some TVs retain images). Pause at least 0.5 s before showing an interactive overlay, and give it a clear way to dismiss it and resume.
- When switching modes such as Picture in Picture, only one audio source plays.
- Subtitles and alternate audio are reachable from the transport bar.

## System player features to match

| Feature | AVKit API |
|---|---|
| Title and subtitle above the transport bar; Info tab | `AVPlayerItem.externalMetadata` (title, subtitle, artwork, description, genre, rating); hide with `transportBarIncludesTitleView = false` |
| Custom transport bar controls | `transportBarCustomMenuItems` (`UIAction` / `UIMenu`) |
| Content tabs | `customInfoViewControllers` (the tab title is the view controller's `title`; size it with `preferredContentSize`) |
| Info tab actions (up to 2) | `infoViewActions` (default: Play from beginning) |
| Skip Intro and other timed buttons | `contextualActions`, set and cleared from a periodic time observer |
| Up Next | `AVPlayerItem.nextContentProposal` (`AVContentProposal`) + delegate |
| Chapters and markers | `navigationMarkerGroups` (`AVNavigationMarkersGroup`) |
| Unskippable ads or legal notices | `interstitialTimeRanges` (`AVInterstitialTimeRange`) |
| Picture in Picture, Siri ("What did they say?", "Skip ahead 15 seconds") | Built in |

Clear Liquid Glass over video needs a dimming layer unless the controls provide one ([liquid-glass.md](liquid-glass.md)).

## Sources

HIG [Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video), [Remotes](https://developer.apple.com/design/human-interface-guidelines/remotes); [Customizing the tvOS playback experience](https://developer.apple.com/documentation/avkit/customizing-the-tvos-playback-experience), [AVPlayerViewController](https://developer.apple.com/documentation/avkit/avplayerviewcontroller).
