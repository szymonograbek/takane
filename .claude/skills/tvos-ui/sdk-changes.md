# tvOS 26 and 27 SDK changes

Behavior that changes when an app is rebuilt with a newer SDK, from the release notes. Check these after upgrading Xcode, or when a view changes without a code change.

## tvOS 26 SDK (Xcode 26)

- Liquid Glass styling applies to standard components ([liquid-glass.md](liquid-glass.md)). It only appears on Apple TV 4K (2nd generation) and newer.
- Views beside a `sidebarAdaptable` `TabView` or `NavigationSplitView` are inset by the sidebar's width and can draw under it, outside their safe area.
- SwiftUI gestures no longer take priority over existing UIKit gesture recognizers; use `highPriorityGesture` to win, or `simultaneousGesture` to share.
- `.controlSize` works on tvOS for custom views; `.buttonBorderShape` and `.buttonSizing(.flexible)` shape and size bordered buttons.
- `NavigationLink` produces a single view. Move `containerValue` modifiers outside the link.
- `Text` + `Text` concatenation is deprecated; use interpolation.
- `URLSession` defaults to TLS 1.2 as the minimum version.

## tvOS 27 SDK (Xcode 27, WWDC26)

- **Large Text:** Dynamic Type now works on tvOS. Fixed point sizes and fixed widths truncate and clip text; adapt as in [SKILL.md](SKILL.md#layout-and-type). Apps can declare Larger Text support in their Accessibility Nutrition Labels.
- **Button tint:** buttons no longer use the asset catalog's accent color for their labels. Set `.tint` where the color matters.
- **`@State` is a macro** and evaluates its initial value once. Give a property an initial value either at its declaration or in `init`, not both. The macro removes the synthesized private memberwise init, and combining `@State` with other wrappers is not supported.
- `AsyncImage` caches by HTTP headers; customize it with the `URLRequest` initializers or `.asyncImageURLSession(_:)`.
- `containerRelativeFrame` inside a `ScrollView` now includes the safe-area insets of the axis that doesn't scroll. Recheck shelf and hero sizes.
- `controlSize`, `buttonSizing`, `buttonRepeatBehavior`, `menuIndicatorVisibility` and `ButtonBorderShape` reset to defaults inside sheets and popovers.
- `LabeledContent` in a `Menu` becomes the item's subtitle. `TabsPickerStyle` looks like `.segmented` on tvOS.
- Alert and confirmation-dialog modifiers that take a data item or an error now back-deploy to tvOS 15.
- UIKit apps must use the scene-based life cycle.
- On Demand Resources are deprecated; use Background Assets.

## Sources

[tvOS 26 release notes](https://developer.apple.com/documentation/tvos-release-notes/tvos-26-release-notes), [tvOS 27 release notes](https://developer.apple.com/documentation/tvos-release-notes/tvos-27-release-notes), [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui). Newer releases: the index at `https://developer.apple.com/tutorials/data/documentation/tvos-release-notes.json`.
