# tvOS components (SwiftUI)

Patterns from Apple's *Creating a tvOS media catalog app in SwiftUI* sample (WWDC24 session 10207) and the HIG. Sizes are in [specs.md](specs.md).

## Lockups

A **lockup** is a focusable piece of content with a header and footer that grow together on focus. Kinds: poster (image, title shown on focus), card (dense info on a platter), caption button (image or text with a title below), monogram (circular photo of a cast member, initials only when no photo exists).

- Posters: `.buttonStyle(.borderless)`. It gives the first `Image` in the label the highlight effect (lift, specular shine, gimbal motion) and moves the title out of the way. Put a separate `Image` and `Text` in the label; a `Label` lays out horizontally. Add `.hoverEffect(.highlight)` to the subview that should lift, e.g. an SF Symbol together with its background.
- Dense lockups (search results, wide cards): `.buttonStyle(.card)`, with padded containers as the label. A custom `LabelStyle` keeps call sites clean.
- Lockups in a row or group share one size.
- Caption buttons tilt with the swipe: up and down in a column, left and right in a row, both in a grid.

## Shelves

A **shelf** is a titled horizontal row of lockups: a `LazyHStack` in a horizontal `ScrollView`.

- `.scrollClipDisabled()` so focused lockups can grow past the scroll view.
- One lockup style per shelf; set the button style on the shelf container.
- `.containerRelativeFrame(.horizontal, count:spacing:)` sizes lockups so the first and last align with the safe area. On a borderless lockup, attach it to the `Image`.
- `.focusSection()` on each shelf.
- Leave space between a row's title and the row above it, and between the title and its items.

## Landing page (hero above the fold)

- A header stack sized with `containerRelativeFrame` to a share of the screen, marked `.focusSection()` so focus moving up from anywhere below reaches it.
- `onScrollVisibilityChange(threshold:)` detects when the header is half off screen (below the fold).
- Background: full-screen art under a material masked by a `LinearGradient`. Animate the gradient stops' opacity between above and below the fold rather than swapping the mask.
- Snap at the fold with a custom `ScrollTargetBehavior` that moves targets crossing the fold to the top of the page or of the first shelf.

## Detail (product) page

- The title's art, blurred, as the background, with the same gradient and fold snapping.
- Stacked `.bordered` buttons of equal width: give the label content a `frame(maxWidth:)` (or `.buttonSizing(.flexible)` on tvOS 26+), because the platter is the label's background.
- Description: truncated, inside a `.plain` `Button` that opens the full text in a `fullScreenCover`.
- Exiting playback returns here with a resume option ([player.md](player.md)).

## Search

- `.searchable(text:placement:prompt:)` + `.searchSuggestions`. On tvOS this is a keyboard screen with results below.
- Before anything is typed, show genres or categories (as the Apple TV app does) and recent searches. Let people remove recent searches.
- Suggestions complete what is typed. Keep them few and mark which part was typed.
- Results: a `LazyVGrid` of landscape lockups, 3–5 per row, in a stable order.
- No matches: `ContentUnavailableView.search`.

## Navigation

- `TabView` with a few single-word tabs. On tvOS 18+, `.tabViewStyle(.sidebarAdaptable)` adds a sidebar with `TabSection`s, at most two levels deep. Use `Tab(role: .search)` for search; the system moves it to the trailing end.
- Tabs navigate; actions live in the content. Every tab stays visible and enabled; an empty section explains why it is empty.
- The tab bar is 68 pt tall, 46 pt from the top, and these values are fixed. It scrolls away with single-view content and stays pinned over split views.
- Live TV apps order tabs: live, then recorded, then other.

## Modals

- Alerts: a title, optional message and up to three buttons. Back cancels. Buttons are specific verbs ("Delete"); the cancel button reads "Cancel". The destructive style marks only actions the person did not deliberately choose.
- Sheets are always modal. Pair a Done button with Cancel or Back.
- Page controls belong only to a set of full-screen peer pages.
- Collections use the standard row or grid layout. Lists suit text-heavy content.

## Sources

[Creating a tvOS media catalog app in SwiftUI](https://developer.apple.com/documentation/swiftui/creating-a-tvos-media-catalog-app-in-swiftui), HIG [Lockups](https://developer.apple.com/design/human-interface-guidelines/lockups), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Collections](https://developer.apple.com/design/human-interface-guidelines/collections), [Design intuitive search experiences (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/292/).
