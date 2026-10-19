---
name: tvos-ui
description: Apple's tvOS ten-foot UI rules (HIG + SwiftUI): focus engine, Siri Remote, layout, lockups and shelves, Liquid Glass, Large Text, video player UX. Use when building, reviewing or restyling a tvOS screen, component or player.
---

# tvOS ten-foot UI

Apple's official tvOS guidance, current to tvOS 27 (WWDC26). Everything here is a **ten-foot UI**: read from 8+ feet away, driven indirectly by a remote that moves focus, never touched. Project conventions in `CLAUDE.md` refine these rules; follow both.

## Building or reviewing a screen

1. Read the reference for your branch:
   - Lockups, shelves, hero, detail page, search, tabs, alerts: [components.md](components.md)
   - Glass, materials, color on controls, tvOS 26+ restyling: [liquid-glass.md](liquid-glass.md)
   - Anything that plays video: [player.md](player.md)
   - Exact sizes (text styles, grid columns, icons, Top Shelf): [specs.md](specs.md)
   - Upgrading the SDK, or behavior changed after a rebuild: [sdk-changes.md](sdk-changes.md)
2. Build with the rules below.
3. Walk the screen with the remote (simulator arrows, or the project's verify skill). Done when **every** item holds:
   - Every element is reachable with up, down, left and right alone, including from the far ends of each row.
   - Focus lands on a chosen element when the screen appears, and again when async content arrives.
   - Each focusable item has distinct unfocused, focused, pressed, selected and disabled looks, and focused items overlap nothing.
   - Back opens the parent screen; Play/Pause controls any media.
   - Text uses text styles and stays readable at Accessibility text sizes.

## Focus engine

- Focus moves on user input only. When the focused item disappears, focus goes to a neighbor one swipe away.
- Selection is a separate press. Focusing an item highlights it; clicking opens it.
- Show focus with the system effects: lift, scale, specular highlight, parallax, and on tvOS 26+ Liquid Glass. Scale and motion carry focus; color is a supporting signal.
- Focused items grow. Supply artwork at the focused size and space items so the grown item clears its neighbors and captions.
- Full-screen content shows no focus; swipes act on the content itself.
- Navigation is by focus, with no on-screen pointer.

| Need | SwiftUI |
|---|---|
| Custom focusable view | `.focusable()`; `.focusable(interactions: .activate)` for activate-only |
| Read or drive focus | `@FocusState` + `.focused($value, equals:)` |
| Catch focus crossing empty space | `.focusSection()` on each row, column and hero. Without it the engine searches in a straight line, so moving up from the end of a shelf misses or jumps to the tab bar |
| Initial focus | `.defaultFocus($value, target)` (runs on first appearance; `priority: .userInitiated` also applies it during navigation), or `.prefersDefaultFocus(_:in:)` inside `.focusScope(namespace)` |
| Return to default | `@Environment(\.resetFocus)` with the scope's namespace |
| Style by focus | `@Environment(\.isFocused)` inside the focusable view |
| Replace the system effect | `.focusEffectDisabled()`, paired with your own focused look |

## Siri Remote

| Input | Expected behavior |
|---|---|
| Swipe | Moves focus, with momentum. Swiping along the edge scrolls fast |
| Click | Activates the item or goes deeper. Click, then swipe, scrubs video |
| Back | Opens the parent in the app's hierarchy (Home at the top level). In a tab view it returns focus to the tab bar. Holding it goes Home |
| Play/Pause | Plays, pauses, resumes |

- Use the standard gestures; custom gestures belong in games.
- Act on presses. Taps come from thumbs resting on or picking up the remote, so playback ignores them.
- Directional edge taps get behavior only where it is intuitive and discoverable.
- SwiftUI: `.onExitCommand` (Back), `.onPlayPauseCommand`, `.onMoveCommand` (edge taps, arrows). `.onMoveCommand` swallows the arrows its focusable children need, so attach it to a view with no focusable children.

## Layout and type

- **Safe area:** main content inset 60 pt top and bottom, 80 pt left and right. Backgrounds bleed to the edges.
- Scroll views have no indicators; the system scrolls to keep focus visible. Content cut off at the screen edges is cut equally on both sides.
- Use the built-in text styles (Body is 29 pt; the minimum is 23 pt). Keep copy short.
- **Large Text (tvOS 27):** text scales up to Accessibility XXXL. Use text styles, flexible frames (`maxWidth: .infinity`) and, at `@Environment(\.dynamicTypeSize).isAccessibilitySize`, fewer cards per row or an `AnyLayout` that swaps `HStackLayout` for `VStackLayout`.
- Controls: 66×66 pt default, 56×56 pt minimum.
- Text entry is slow on a TV: offer choices, suggestions and recent values first, and the matching keyboard type when typing is needed.
- Colors: a small palette tied to the logo; content leads. Give each custom color dark and Increase Contrast variants.
- Give icons and artwork accessibility labels, and test with Reduce Transparency, Increase Contrast and Reduce Motion.

## Sources

[Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos), [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection), [Remotes](https://developer.apple.com/design/human-interface-guidelines/remotes), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [focusSection()](https://developer.apple.com/documentation/swiftui/view/focussection()), [defaultFocus](https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:)), [About focus interactions for Apple TV](https://developer.apple.com/documentation/uikit/about-focus-interactions-for-apple-tv), [Prepare your tvOS apps for Dynamic Type (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/221/). Apple's pages render with JavaScript; fetch `https://developer.apple.com/tutorials/data/<path>.json` (e.g. `design/human-interface-guidelines/layout`) for their content.
