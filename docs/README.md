# Documentation

Custom Apple TV / macOS client for Stremio accounts, built on [stremio-core](https://github.com/Stremio/stremio-core).

- [Feasibility](feasibility.md) — what is open, what is not, and the scope decisions that follow.
- [Architecture](architecture.md) — layers, the Rust ↔ Swift bridge, stream handling, player.
- [tvOS UI guidelines](../.claude/skills/tvos-ui/SKILL.md) — Apple's tvOS UX rules and the SwiftUI APIs that implement them (an agent skill).
- [Roadmap](roadmap.md) — build order and how each step is verified.
- [App Review](app-review.md) — how to submit to the App Store, and why similar apps were removed.

## Scope at a glance

| In scope | Out of scope |
|---|---|
| Home: continue watching, discover | Torrent playback |
| Add-ons with stremio-core parity | Stremio streaming server |
| Search | Archive / Usenet streams |
| Player with subtitle and audio track selection | |
| Player settings (languages, subtitle style) | |
| Debrid / HTTP streams | |
| The user's Jellyfin server and WebDAV folders | |

Distribution is sideload today. The App Store is the goal, with sideloading as the fallback. Nightly Rust is acceptable.
