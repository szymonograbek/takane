# Architecture

```
┌──────────────────────────────────────────────┐
│ SwiftUI app: app/macOS, app/tvOS (views)     │
│  app/Shared/App (entry, smoke test)          │
├──────────────────────────────────────────────┤
│ Swift core client (app/Shared/Core)          │
│  CoreStore: observable model state           │
│  CoreClient: dispatch / state / events       │
│  Host callbacks: URLSession fetch, logging   │
├──────────────── FFI (C ABI) ─────────────────┤
│ Rust bridge crate (core/)                    │
│  AppleEnv · AppModel · JSON in and out       │
├──────────────────────────────────────────────┤
│ stremio-core (development branch, pinned rev)│
└──────────────────────────────────────────────┘
                     │
          MPVKit ◄───┘ stream URL + headers (app/Shared/Player)
```

## Rust bridge

`core/` depends on `stremio-core` with the `derive` and `env-future-send` features, pinned to a commit in `core/Cargo.toml`.

- **Wire format.** JSON in stremio-core's own serde shapes, the same contract `stremio-core-web` uses. Actions are core's `Action` enum; state is a serialized core model; events are core's `RuntimeEvent`. There is no schema to keep in sync by hand. `stremio-core-kotlin`'s protobuf layer was the alternative and costs about 6k lines of mapping.
- **FFI surface.** `core/include/stremio_bridge.h`. `sb_initialize` (host callbacks + storage directory), `sb_dispatch`, `sb_get_state`, `sb_fetch_resolve` / `sb_fetch_reject`, `sb_bytes_free`. Bytes in, bytes out.
- **Models.** `AppModel` in `core/src/model.rs` lists the core models the app runs: `ctx`, `continue_watching_preview`, `addon_details`, `meta_details`, `player`. Adding a field there and to `CoreField` in Swift exposes another model.
- **Packaging.** `build/StremioBridge.xcframework` with `macos-arm64`, `tvos-arm64` and `tvos-arm64-simulator` slices. `scripts/build-core.sh` builds it. The Xcode targets `StremioBridge_macOS` / `StremioBridge_tvOS` run that script before the app links and refresh only the slice of the platform being built. The simulator slice is arm64 only, so the tvOS target excludes x86_64 for the simulator.
- **Toolchain.** Nightly, pinned in `rust-toolchain.toml`. tvOS targets are tier 3 and build `std` from source (`-Zbuild-std`), which needs the `rust-src` component.

### `Env` implementation

Core's `Env` trait (`src/runtime/env.rs`) is what the host must provide:

| Method | Implementation |
|---|---|
| `fetch` | Call back into Swift; `URLSession` performs the request and answers with `sb_fetch_resolve` / `sb_fetch_reject`. |
| `get_storage` / `set_storage` | In Rust: one JSON file per key in the directory Swift passes to `sb_initialize` (Application Support on macOS, Caches on tvOS). |
| `exec_concurrent` / `exec_sequential` | Tokio runtime owned by the bridge; sequential futures run in order on one queue. |
| `now` | `chrono::Utc::now()`. |
| `log` | `tracing`, forwarded with all bridge logs to the Swift logger. |
| `flush_analytics` / `analytics_context` | No-op. |

## Swift layer

- `CoreClient` is the only code that touches the FFI. `CoreAction` encodes actions; `CoreState.swift` decodes only the fields the app reads. Values the app hands back to core untouched (addon descriptors, streams) are kept as raw JSON.
- `CoreStore` is the main-actor mirror of core state. On each `NewState` event it re-reads the changed fields.
- `CoreWorkflows.swift` holds multi-step flows (install an addon, load streams) shared by the UI and the smoke test.
- `app/Shared` is compiled into both apps. Only `RootView` and `MPVVideoView` exist per platform (`app/macOS`, `app/tvOS`): `NSView` versus `UIView` hosting of mpv's layer, and pointer versus focus/remote UI.

## Logging

`Log` (`app/Shared/Logging/Log.swift`) writes every line to the unified log (subsystem `com.ograbek.stremio-tv`, one category per area) and to `app.log`: `~/Library/Logs/com.ograbek.stremio-tv/` on macOS, `Library/Caches/Logs/` in the app container on tvOS. Long tokens (debrid keys, add-on configs) are masked. The previous session is kept as `app.previous.log`. Debug builds also echo to stderr. Rust `tracing` output and panics arrive as category `rust:<module>`; mpv's own log arrives under `player`. Set `STREMIO_LOG_LEVEL` (`trace`, `debug`, `info`, `warning`, `error`) to change the threshold; the default is `debug`.

## Streams

Before display, filter `meta_details` streams to supported sources:

| Source | Handling |
|---|---|
| `Url` | Play. If `proxyHeaders.request` is set, pass headers to mpv. |
| `YouTube` | Out of scope for now. |
| `Torrent`, archives, `Nzb` | Hidden. |
| `External`, `PlayerFrame` | Hidden. |

## Player

MPVKit renders video with `vo=gpu-next` through MoltenVK into a `CAMetalLayer` (`app/Shared/Player/MPVEngine.swift`), the same path MPVKit's macOS and tvOS demos use. Hardware decoding uses VideoToolbox; the tvOS simulator falls back to software decoding. Reading frames back from mpv (`snapshot`) crashes the simulator's Metal driver, so it is disabled in simulators. Core's `player` model owns playback state (progress, watched, next episode); `PlaybackSession` forwards time, pause and end events to it. Core copies progress into the library (and so continue watching) on pause, unload and every 180 s, not on every time update.

Settings map to mpv options:

| Core setting | mpv |
|---|---|
| `subtitles_language` / `secondary_subtitles_language` | `slang` |
| `audio_language` / `secondary_audio_language` | `alang` |
| `subtitles_size` | `sub-scale` |
| `subtitles_font` | `sub-font` |
| `subtitles_bold` | `sub-bold` |
| `subtitles_offset` | `sub-pos` |
| `subtitles_text_color` | `sub-color` |
| `subtitles_background_color` | `sub-back-color` (with `sub-border-style`) |
| `subtitles_outline_color` | `sub-border-color` |
| `ass_subtitles_styling` | `sub-ass-override` |
| `hardware_decoding` | `hwdec` |

External subtitles from add-ons (core's subtitle resources) are added with mpv's `sub-add`. Embedded audio and subtitle tracks come from mpv's track list.
