# Feasibility

Verdict: feasible. Nothing required is private. The only closed piece, the streaming server, is out of scope because the app plays debrid streams only.

Findings checked on 2026-10-18.

## Dependencies

| Piece | Availability | License | Role |
|---|---|---|---|
| [`Stremio/stremio-core`](https://github.com/Stremio/stremio-core) | Public, actively maintained | MIT | All app logic: auth, library, add-ons, catalogs, search, player state, settings. |
| [`Stremio/stremio-core-kotlin`](https://github.com/Stremio/stremio-core-kotlin) → `stremio-core-protobuf` | Public | MIT (crate `LICENSE.md`) | Reference for the Rust ↔ native bridge (protobuf messages over FFI). |
| `Stremio/stremio-core-swift` | Not public (404) | — | Official iOS bridge. We write our own. |
| `api.strem.io` | Public, undocumented | — | Account and sync backend. Used only through stremio-core, never directly. |
| [MPVKit](https://github.com/mpvkit/MPVKit) | Public, supports iOS, macOS, tvOS, visionOS | LGPL-3.0 | Player. Same engine family as the official desktop shell (`stremio-shell-ng` uses mpv). |
| Stremio streaming server (`server.js`) | Only a minified webpack bundle inside `stremio-shell-ng`; no source repo | Unclear | **Not used.** |

### Player alternatives considered

- **VLCKit** (LGPL-2.1, supports tvOS): fallback if MPVKit has issues.
- **KSPlayer** (GPL-3.0): rejected because of the license.
- **AVPlayer** alone: rejected; no MKV and limited subtitle formats.

## stremio-core coverage

Feature to core model (`src/models/`):

| Feature | Model |
|---|---|
| Account, library, add-on sync, settings | `ctx` |
| Continue watching | `continue_watching_preview` |
| Home / discover rows | `catalogs_with_extra` |
| Discover with filters | `catalog_with_filters` |
| Item detail and stream list | `meta_details` |
| Search | `local_search` and add-on search catalogs |
| Playback progress, watched state, next episode | `player` |
| TV login by code / QR | `link` |

Player settings already exist in `src/types/profile/settings.rs` and sync to the account: `audio_language`, `secondary_audio_language`, `subtitles_language`, `secondary_subtitles_language`, `subtitles_auto_select`, `subtitles_size`, `subtitles_font`, `subtitles_bold`, `subtitles_offset`, `subtitles_text_color`, `subtitles_background_color`, `subtitles_outline_color`, `subtitles_opacity`, `ass_subtitles_styling`, `hardware_decoding`, `frame_rate_matching_strategy`, `audio_passthrough`, `binge_watching`, `seek_time_duration`.

Add-on parity comes from core: the add-on protocol, catalog aggregation and stream resolution all live there.

## Debrid without a streaming server

Core has no debrid code. Debrid is handled by add-ons (Torrentio, Comet, MediaFusion, AIOStreams, …) that return a plain HTTPS URL from the debrid provider. Core models it as `StreamSource::Url` (`src/types/resource/stream.rs`). The app gives that URL to the player. No server needed.

Edge cases:

- **Proxy headers.** Streams with `behaviorHints.proxyHeaders` are rewritten into a streaming-server proxy URL only when a server is configured. Without a server, pass the request headers to mpv (`http-header-fields`).
- **Unsupported sources.** `Torrent`, `Rar`, `Zip`, `Tgz`, `Tar`, `Nzb` (and similar archive variants) require the server. Hide them from the stream list.
- **Add-on configuration.** Debrid add-ons are configured on their own web pages; the API key ends up in the install URL. On TV, install by syncing add-ons from another Stremio client or by entering the URL from another device.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Rust tvOS targets (`aarch64-apple-tvos`, `aarch64-apple-tvos-sim`) are likely Tier 3 | Need nightly and `-Zbuild-std` | Accepted. Pin the toolchain in `rust-toolchain.toml`. Re-check the current tier when setting up. |
| `api.strem.io` is undocumented | Backend changes can break the app | Follow upstream stremio-core; fixes arrive with core updates. |
| No official Swift bridge | Bridge is ours to write and maintain | Mirror `stremio-core-protobuf`'s structure to keep merges simple. |
| Some playback features only show on hardware | HDR, Dolby Vision, passthrough, frame-rate matching untestable in the simulator | Verify on a real Apple TV. |

## Decisions

- Debrid / HTTP streams only. No torrent engine, no bundled server.
- Sideload only. App Store rules do not apply.
- Nightly Rust is acceptable.
