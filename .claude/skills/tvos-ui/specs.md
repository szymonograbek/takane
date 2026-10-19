# tvOS specs

Exact values from the HIG. The screen is 1920×1080 pt.

## Text styles

Sizes at the default text size; from tvOS 27 they scale with Large Text. Bold is the emphasized weight for every style except Subtitle 1, which uses Medium.

| Style | Weight | Size / leading (pt) |
|---|---|---|
| Title 1 | Medium | 76 / 96 |
| Title 2 | Medium | 57 / 66 |
| Title 3 | Medium | 48 / 56 |
| Headline | Medium | 38 / 46 |
| Subtitle 1 | Regular | 38 / 46 |
| Callout | Medium | 31 / 38 |
| Body | Medium | 29 / 36 |
| Caption 1 | Medium | 25 / 32 |
| Caption 2 | Medium | 23 / 30 |

The system font is SF Pro; New York is also available.

## Grids

All use 40 pt horizontal spacing and at least 100 pt vertical spacing between unfocused items.

| Columns | Unfocused width (pt) |
|---|---|
| 2 | 860 |
| 3 | 560 |
| 4 | 410 |
| 5 | 320 |
| 6 | 260 |
| 7 | 217 |
| 8 | 184 |
| 9 | 160 |

## Fixed metrics

| Item | Value |
|---|---|
| Safe area | 60 pt top and bottom, 80 pt sides |
| Control size | 66×66 pt default, 56×56 pt minimum |
| Tab bar | 68 pt tall, top edge 46 pt from the screen top (fixed) |
| Text size | 29 pt default, 23 pt minimum |

## Images

- Ship @1x and @2x.
- **Layered images** (2–5 layers) give focused images parallax: text in the foreground layer, an opaque background layer, subtle depth, essential content inside a safe zone. Images downloaded at runtime are `.lcr` files made with `layerutil`. Standard views and `FocusState` apply parallax automatically.
- **App icon:** layered and required, 800×480 px, a rectangle with concentric rounded corners, with a safe zone because focus crops the foreground layers most.

## Top Shelf

Feature new or in-progress content with a direct path to play it; keep ads and prices out.

| Layout | Size (pt, @1x; double for @2x) |
|---|---|
| Static fallback (not focusable, so it must not look interactive) | 2320×720 |
| Sectioned row, poster 2:3 | 404×608 actual, 380×570 focused, 333×570 unfocused |
| Sectioned row, square | 608×608 actual, 570×570 focused, 500×500 unfocused |
| Sectioned row, 16:9 | 908×512 actual, 852×479 focused, 782×440 unfocused |
| Scrolling inset banner (3–8 images, text baked in and repeated in the accessibility label) | 1940×692 actual, 1740×620 focused, 1740×560 unfocused |

A sectioned row needs enough images to fill the screen width and at least one label. Mixed sizes scale up to the tallest. The carousel layouts (actions, details) pair full-screen video with a Play button and a More Info button.

## Sources

HIG [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Images](https://developer.apple.com/design/human-interface-guidelines/images), [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Top Shelf](https://developer.apple.com/design/human-interface-guidelines/top-shelf), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).
