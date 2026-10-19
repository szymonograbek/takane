# Liquid Glass on tvOS

Liquid Glass (tvOS 26+) is Apple's material for the **functional layer**: controls and navigation floating above the **content layer**. It blurs and refracts what is behind it and reflects the light around it.

## On tvOS

- It appears in navigation (tab bar, sidebar) and system screens (Top Shelf, Control Center).
- Standard buttons, controls and image views **turn to glass when they gain focus**. Custom focusable views match by using the standard focus APIs (`focusable`, `@Environment(\.isFocused)`).
- Only Apple TV 4K (2nd generation) and newer render it; older models keep the tvOS 18 look. Judge design on one of those devices.
- Standard components adopt it when the app is built with the tvOS 26+ SDK. The Info.plist key `UIDesignRequiresCompatibility` keeps the old look.
- The glass APIs are tvOS 26+; gate them with `if #available(tvOS 26, *)` when the app supports older releases.

## Rules

- Glass belongs to the functional layer. The content layer (cards, rows, backgrounds) uses standard materials. Sliders and toggles are the exception: they turn to glass while in use.
- Use it on few custom controls: the most important functional ones.
- **Variants:** `regular` blurs and adjusts brightness for legibility; use it for anything with text. `clear` is highly translucent and only goes over rich media (photos, video); add a 35% dark dimming layer under it when the media is bright. AVKit's own controls bring their own dimming.
- **Color:** glass takes its color from the content behind it. Tint only to emphasize one primary action, on the background rather than the label. Over colorful content keep labels monochrome; keep label colors distinct from the content's.
- Bars, tab views, navigation stacks and sheets use the system background: remove custom backgrounds there, since they fight the glass and the scroll edge effect.
- Nested corners are **concentric** with their container: `ConcentricRectangle`, `.rect(corners:isUniform:)`, or (tvOS 27) `GeometryProxy.concentricCornerRadii`.
- People can change the glass look, Reduce Transparency, Increase Contrast and Reduce Motion; check custom glass under each.

## Standard materials (content layer)

| Material | Use for |
|---|---|
| `.ultraThinMaterial` | Full-screen views, light color scheme |
| `.thinMaterial` | Overlays partly covering content, light color scheme |
| `.regularMaterial` | Overlays partly covering content |
| `.thickMaterial` | Overlays partly covering content, dark color scheme |

Pick a material by role, not by the color it appears to give, and use vibrant system colors on top of it.

## SwiftUI

| Need | API |
|---|---|
| Glass button | `.buttonStyle(.glass)`; `.buttonStyle(.glassProminent)` for the one primary action (accent tint) |
| Glass on a custom view | `.glassEffect()` (regular, capsule), `.glassEffect(.regular.tint(color).interactive(), in: .rect(cornerRadius:))`. Apply it after the modifiers that change appearance |
| Several glass shapes | Wrap them in `GlassEffectContainer(spacing:)`, which renders them together faster and lets them blend. `glassEffectUnion(id:namespace:)` joins shapes at rest |
| Morph on change | `glassEffectID(_:in:)` with `@Namespace`, plus `glassEffectTransition(.matchedGeometry)` (nearby) or `.materialize` (far) |
| Bordered buttons | `.buttonBorderShape(_:)`, `.buttonSizing(.flexible)` instead of spacers or infinite frames in the label |
| Custom control sizes | `.controlSize(_:)`, now honored on tvOS |
| Art under a sidebar | `.backgroundExtensionEffect()` mirrors and blurs edge-to-edge art beneath it |
| Custom bar over scrolling content | `.scrollEdgeEffectStyle(_:for:)`, `.safeAreaBar(edge:)` |
| Search tab | `Tab(role: .search)` |

Many glass views on screen cost frames: keep them in containers and few in number.

## Sources

HIG [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars); [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass), [Meet Liquid Glass (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/219/).
