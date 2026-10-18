# Architecture

```
┌───────────────────────────────────────────────────────────┐
│ UI: app/macOS, app/tvOS (render FeatureStore state)       │
├───────────────────────────────────────────────────────────┤
│ Features: one state machine per behavior (pure reduce)    │
├───────────────────────────────────────────────────────────┤
│ Domain: values, branded ids, ports (protocols) + errors   │
├─────────────────────────────┬─────────────────────────────┤
│ Adapters/Core               │ Adapters/MPV                │
│  CoreRuntime, Core*Service  │  MPVEngine: PlaybackEngine  │
│  CoreClient (only FFI user) │                             │
├──────── FFI (C ABI) ────────┤        MPVKit / libmpv      │
│ Rust bridge crate (core/)   │                             │
│ stremio-core (pinned rev)   │                             │
└─────────────────────────────┴─────────────────────────────┘
```

## Rust bridge

`core/` depends on `stremio-core` with the `derive` and `env-future-send` features, pinned to a commit in `core/Cargo.toml`.

- **Wire format.** JSON in stremio-core's own serde shapes, the same contract `stremio-core-web` uses. Actions are core's `Action` enum; state is a serialized core model; events are core's `RuntimeEvent`. There is no schema to keep in sync by hand. `stremio-core-kotlin`'s protobuf layer was the alternative and costs about 6k lines of mapping.
- **FFI surface.** `core/include/stremio_bridge.h`. `sb_initialize` (host callbacks + storage directory), `sb_dispatch`, `sb_get_state`, `sb_fetch_resolve` / `sb_fetch_reject`, `sb_bytes_free`. Bytes in, bytes out.
- **Models.** `AppModel` in `core/src/model.rs` lists the core models the app runs: `ctx`, `continue_watching_preview`, `addon_details`, `board` and `search` (two `CatalogsWithExtra`, as in `stremio-core-web`), `meta_details`, `player`. Adding a field there and to `CoreField` in Swift exposes another model.
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

## App architecture

The app is ports and adapters with a state machine per feature. Dependencies point inward: UI → Features → Domain ← Adapters. `app/Shared/App/StremioApp.swift` is the composition root and the only file that names concrete adapters.

### Domain

`app/Shared/Domain` holds what the app talks about, independent of where it comes from.

- **Values and identifiers.** `PlayableID` (movie, or show plus season and episode), `MediaID` and `ManifestURL` are parsed once, at the boundary, by failable initializers. Inside the app the type proves the value is valid.
- **Ports.** One protocol per capability: `AccountService`, `AddonService`, `CatalogService`, `StreamService`, `LibraryService`, `PreferencesService`, `PlaybackTracker`, `PlaybackEngine`, `SkipSegmentService`. Each has its own error enum (`AccountError`, `AddonError`, `CatalogError` and `DetailsError`, `StreamSourceError`, `PreferencesError`, `PlaybackError`, `SkipSegmentError`) and uses typed throws. Changing state is an `AsyncStream` that yields the current value first, then every change.
- **`Remote<Value, Failure>`** (loading, loaded, failed) for anything fetched, and **`Probe`** (pending, done, failed) for one look at changing state while waiting.
- **`TrackingToken`** is the one opaque value: the stream provider puts what it needs to track playback into the candidate it returns and the tracker reads it back. For core that is the player selection JSON.

Catalogs and metadata come from the user's add-ons only. `CatalogService` has one method per capability: `board()` streams the home rows, `loadMore(_:)` pages a row, `search(_:)` streams results across add-ons, and `details(_:type:)` returns one title with its videos. Every title is keyed by `MediaID`, so a stream lookup matches it. A row is one catalog of one add-on (`CatalogRow`), and an add-on that fails fails its own row. Images are the URLs the add-ons give. "Nothing installed" is a state of its own, distinct from loading and from add-ons that answered with nothing: `Board.noCatalogAddons`, `SearchResults.noSearchAddons` and `DetailsError.noMetaAddons`, so screens can tell the user to install a catalog add-on.

### Features

A `Feature` (`app/Shared/Features/Feature.swift`) is a finite state machine:

```swift
enum StreamsFeature: Feature {
    enum State { case idle, lookingUp(PlayableID, results: StreamResults?) }
    enum Event { case lookUp(PlayableID), resultsChanged(StreamResults) }
    enum Effect { case watch(PlayableID) }
    static func reduce(_ state: inout State, _ event: Event) -> [Effect]   // pure: every rule
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: …) async   // no rules
}
```

`reduce` holds every rule: legal transitions, dropping stale answers (events carry the request they answer), progress throttling. Tests drive it with plain values. `run` performs one effect against the feature's ports and reports back as events. `FeatureStore<F>` is the `@Observable` runtime views read and `send` to; it starts each effect in a task, cancels them when it goes away and offers `until(timeout:onTimeout:probe)` for tests and the smoke test.

Features today: `PlayerFeature` (idle, active session with phase opening/playing/paused/ended, tracks, speed and skip segments, failed), `AccountFeature` (account, sign-in by code or password), `HomeFeature` (continue watching and the board), `AddonsFeature` (install and remove), `StreamsFeature`, `PreferencesFeature` (track languages). `AppContext` holds those app-wide stores. `DetailsFeature` and `SearchFeature` belong to the screen that shows them. `Launch` makes "services are ready" a state: screens exist only in `.ready(AppContext)`, so nothing can send to core before it started.

### Adapters

- **Core account.** `CoreAccountService` signs in through core's `link` model (create a code, poll `ReadData` every 3 s, then `Authenticate` with the key) or with email and password. Core replaces the profile's add-ons on sign-in, so the adapter reinstalls the ones added while signed out; watch progress is the account's. Authentication failures arrive as core `Error` events, which `CoreRuntime.events()` streams. `Authenticate` dispatches and core events are logged with credentials redacted.
- **Core.** `CoreClient` is the only code that touches the FFI. `CoreRuntime` turns core's protocol (dispatch an action, later receive `NewState` naming the changed fields) into async APIs: `states`/`observe` stream a field's state (current first), and `request` subscribes, dispatches and waits until a probe accepts a state. No polling. Because the current state is probed first, every probe checks that the state answers its own request (transport URL, selected stream path). `CoreAddonService`, `CoreCatalogService`, `CoreStreamService`, `CoreLibraryService` and `CorePlaybackTracker` implement the ports. `CoreAction.swift` encodes actions; `CoreWire.swift` decodes only the fields the adapters read. Core keeps one `meta_details` selection, so a new stream lookup replaces the previous one and finishes its stream.
- **Core catalogs.** `CoreCatalogService` loads `board` with every catalog without a required extra and `search` with every catalog that accepts the `search` extra. These are core's rules, and the adapter does not repeat them. Once core holds the selection, an empty `catalogs` list means no add-on offers one. Core lists catalogs without fetching them, on load and again when the profile's add-ons change, so the adapter asks for them with `LoadRange`. That is how an install shows up on the board without another load. `details` loads `meta_details` with no stream path. A stream lookup for the same title, such as an episode of that show, reuses the metadata it loaded. A details call replaces a running stream lookup. `scripts/smoke.sh --no-addons` starts core without its default add-ons (`EMPTY_OFFICIAL_ADDONS=1`) and checks the empty states, then installs Cinemeta and checks that the open board stream fills.
- **SkipDB.** `SkipDBSkipSegmentService` conforms to `SkipSegmentService` over the open SkipDB API (skipdb.tv, no key): recap, intro, outro and preview ranges for an IMDb id, fitted to the stream's duration and clamped to it. It shares `URLSession.json` (`Adapters/HTTP`) for requests, logging and the `HTTPFailure` it maps to `SkipSegmentError`. The `StremioTVAdapterTests` target tests it against recorded responses through a `URLProtocol` stub; set `TEST_RUNNER_STREMIO_LIVE_TESTS=1` to run its live tests too.
- **MPV.** `MPVEngine` conforms to `PlaybackEngine`: it translates mpv events into `PlaybackEvent` on its event queue, renders into a `CAMetalLayer`, and runs commands on the main actor.

### Adding a provider

A provider is a folder under `app/Shared/Adapters/` with types that conform to ports. `Adapters/SkipDB/` is the example: `SkipDBSkipSegmentService` and its private response types, HTTP and decoding failures mapped to `SkipSegmentError`, and one line in `Services.live`. Features and views do not change. A provider for a port keyed by titles keeps results keyed by the same `MediaID`, so stream lookups still match.

### Strictness

Swift 6 with complete concurrency checking, `ExistentialAny` and warnings as errors. SwiftLint runs as a build tool plugin on every app and test build in strict mode (`.swiftlint.yml`). Force unwraps, force casts, `try!`, `@unchecked Sendable`, `nonisolated(unsafe)` and `assumeIsolated` fail the build unless disabled on the line with a reason. The `StremioTVTests` target compiles Domain and Features without the bridge or mpv, so those layers cannot import an adapter.

### Platforms

`app/Shared` is compiled into both apps, including the screens in `app/Shared/UI`. They differ by platform only where input differs (`#if os(tvOS)` for focus sections, card buttons and the remote's commands). `VideoSurfaceView` exists per platform (`app/macOS`, `app/tvOS`) for `NSView` versus `UIView` hosting of the engine's layer. Views parse text input into domain types before sending events.

### UI

`Theme.swift` holds the colors (`Palette`: canvas, surface, burgundy, red, text, secondary) and the sizes that differ between the TV and a window (`Metrics`). Nothing else names a color value. The shared pieces are `AppLogo`, `Artwork` (an add-on image with a placeholder), `ProgressLine`, `PosterCard`, `ContinueCard`, `Shelf` (a titled sideways row), `SettingsPage` (an emblem beside a list) and the player's `PlayerControls`. Icons are SF Symbols; empty and error states use `ContentUnavailableView`. The logo (`AppLogo`, asset `Logo`) and the macOS and tvOS app icons, including the tvOS layered icon and Top Shelf images, are generated from `assets/logo.png` by `swift scripts/make-icons.swift assets/logo.png`; rerun it when the logo changes. Navigation is three tabs, each a `NavigationStack` driven by `Route` (`details`, `streams`).

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

MPVKit renders video with `vo=gpu-next` through MoltenVK into a `CAMetalLayer` (`app/Shared/Adapters/MPV/MPVEngine.swift`), the same path MPVKit's macOS and tvOS demos use. Hardware decoding uses VideoToolbox; the tvOS simulator falls back to software decoding. Reading frames back from mpv (`snapshot`) crashes the simulator's Metal driver, so it is disabled in simulators. Core's `player` model owns playback state (progress, watched, next episode); `PlayerFeature` reports time (once per second), pause and end to it through `CorePlaybackTracker`. Core copies progress into the library (and so continue watching) on pause, unload and every 180 s, not on every time update.

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

External subtitles from add-ons (core's subtitle resources) are added with mpv's `sub-add`; not wired yet. Embedded audio and subtitle tracks come from mpv's `track-list` (`MPVTrackList`) and are chosen with `aid` and `sid`. Speed is mpv's `speed`. A load sets `start` (the saved position), `alang` and `slang` (the preferred languages from `PreferencesService`) before `loadfile`.
