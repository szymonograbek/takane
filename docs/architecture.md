# Architecture

```
┌───────────────────────────────────────────────────────────┐
│ UI: app/macOS, app/tvOS (render FeatureStore state)       │
├───────────────────────────────────────────────────────────┤
│ Features: one state machine per behavior (pure reduce)    │
├───────────────────────────────────────────────────────────┤
│ Domain: values, branded ids, ports (protocols) + errors   │
├─────────────────────────────┬─────────────────────────────┤
│ Adapters/Core               │ Adapters/Aether             │
│  CoreRuntime, Core*Service  │  AetherPlaybackEngine:      │
│  CoreClient (only FFI user) │   PlaybackEngine            │
├──────── FFI (C ABI) ────────┤  AetherEngine (SwiftPM)     │
│ Rust bridge crate (core/)   │                             │
│ stremio-core (pinned rev)   │                             │
└─────────────────────────────┴─────────────────────────────┘
```

## Rust bridge

`core/` depends on `stremio-core` with the `derive` and `env-future-send` features, pinned to a commit in `core/Cargo.toml`.

- **Wire format.** JSON in stremio-core's own serde shapes, the same contract `stremio-core-web` uses. Actions are core's `Action` enum; state is a serialized core model; events are core's `RuntimeEvent`. There is no schema to keep in sync by hand. `stremio-core-kotlin`'s protobuf layer was the alternative and costs about 6k lines of mapping.
- **FFI surface.** `core/include/StremioBridge/stremio_bridge.h`. `sb_initialize` (host callbacks + storage directory), `sb_dispatch`, `sb_get_state`, `sb_fetch_resolve` / `sb_fetch_reject`, `sb_bytes_free`. Bytes in, bytes out.
- **Models.** `AppModel` in `core/src/model.rs` lists the core models the app runs: `ctx`, `continue_watching_preview`, `addon_details`, `board` and `search` (two `CatalogsWithExtra`, as in `stremio-core-web`), `meta_details`, `player`. Adding a field there and to `CoreField` in Swift exposes another model. Most fields serialize as core does. `meta_details` adds `watchedVideos`, the ids of the first ready meta item's videos the user has watched, because core leaves its watched bitfield out of the state.
- **Packaging.** `build/StremioBridge.xcframework` with `macos-arm64`, `tvos-arm64` and `tvos-arm64-simulator` slices. `scripts/build-core.sh` builds it. The Xcode targets `StremioBridge_macOS` / `StremioBridge_tvOS` run that script before the app links and refresh only the slice of the platform being built. The simulator slice is arm64 only, so the tvOS target excludes x86_64 for the simulator.
- **Toolchain.** Nightly, pinned in `rust-toolchain.toml`. tvOS targets are tier 3 and build `std` from source (`-Zbuild-std`), which needs the `rust-src` component.

### `Env` implementation

Core's `Env` trait (`src/runtime/env.rs`) is what the host must provide:

| Method | Implementation |
|---|---|
| `fetch` | Call back into Swift; `URLSession` performs the request and answers with `sb_fetch_resolve` / `sb_fetch_reject`. |
| `get_storage` / `set_storage` | In Rust: one JSON file per key in the directory Swift passes to `sb_initialize` (Application Support on macOS, Caches on tvOS). A read or write starts when its future is first polled, so `exec_sequential` orders writes to one key. |
| `exec_concurrent` / `exec_sequential` | Tokio runtime owned by the bridge; sequential futures run in order on one queue. |
| `now` | `chrono::Utc::now()`. |
| `log` | `tracing`, forwarded with all bridge logs to the Swift logger. |
| `flush_analytics` / `analytics_context` | No-op. |

## App architecture

The app is ports and adapters with a state machine per feature. Dependencies point inward: UI → Features → Domain ← Adapters. `app/Shared/App/StremioApp.swift` is the composition root and the only file that names concrete adapters.

### Domain

`app/Shared/Domain` holds what the app talks about, independent of where it comes from.

- **Values and identifiers.** `PlayableID` (movie, or show plus season and episode), `MediaID` and `ManifestURL` are parsed once, at the boundary, by failable initializers. Inside the app the type proves the value is valid.
- **Ports.** One protocol per capability: `AccountService`, `AddonService`, `CatalogService`, `StreamService`, `LibraryService`, `PreferencesService`, `PlaybackTracker`, `PlaybackEngine`, `SkipSegmentService`, `SubtitleService`. Each has its own error enum (`AccountError`, `AddonError`, `CatalogError` and `DetailsError`, `StreamSourceError`, `PreferencesError`, `PlaybackError`, `SkipSegmentError`, `SubtitleSourceError`) and uses typed throws. Changing state is an `AsyncStream` that yields the current value first, then every change.
- **`Remote<Value, Failure>`** (loading, loaded, failed) for anything fetched, and **`Probe`** (pending, done, failed) for one look at changing state while waiting.
- **`TrackingToken`** is the one opaque value: the stream provider puts what it needs to track playback into the candidate it returns and the tracker reads it back. For core that is the player selection JSON.

Catalogs and metadata come from the user's add-ons only. `CatalogService` has one method per capability: `board()` streams the home rows, `loadMore(_:)` pages a row, `search(_:)` streams results across add-ons, and `details(_:type:)` returns one title with its videos, each marked watched or not. The details screen loads them once, so an episode watched during the visit still reads as unwatched until the screen opens again. Every title is keyed by `MediaID`, so a stream lookup matches it. A row is one catalog of one add-on (`CatalogRow`), and an add-on that fails fails its own row. Images are the URLs the add-ons give. "Nothing installed" is a state of its own, distinct from loading and from add-ons that answered with nothing: `Board.noCatalogAddons`, `SearchResults.noSearchAddons` and `DetailsError.noMetaAddons`, so screens can tell the user to install a catalog add-on.

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

Features today: `PlayerFeature` (idle, active session with phase opening/playing/paused/ended, tracks, add-on subtitles, speed, skip segments and timeline scans, failed), `AccountFeature` (account, sign-in by code or password), `HomeFeature` (continue watching and the board), `AddonsFeature` (install and remove), `StreamsFeature`, `PreferencesFeature` (track languages, subtitle style, seek step and hiding spoilers). `AppContext` holds those app-wide stores. `DetailsFeature` and `SearchFeature` belong to the screen that shows them. `Launch` makes "services are ready" a state: screens exist only in `.ready(AppContext)`, so nothing can send to core before it started.

### Adapters

- **Core account.** `CoreAccountService` signs in through core's `link` model (create a code, poll `ReadData` every 3 s, then `Authenticate` with the key) or with email and password. Core replaces the profile's add-ons on sign-in, so the adapter reinstalls the ones added while signed out; watch progress is the account's. Authentication failures arrive as core `Error` events, which `CoreRuntime.events()` streams. `Authenticate` dispatches and core events are logged with credentials redacted.
- **Core.** `CoreClient` is the only code that touches the FFI. `CoreRuntime` turns core's protocol (dispatch an action, later receive `NewState` naming the changed fields) into async APIs: `states`/`observe` stream a field's state (current first), and `request` subscribes, dispatches and waits until a probe accepts a state. No polling. Because the current state is probed first, every probe checks that the state answers its own request (transport URL, selected stream path). `CoreAddonService`, `CoreCatalogService`, `CoreStreamService`, `CoreLibraryService`, `CorePlaybackTracker` and `CoreSubtitleService` implement the ports. `CoreAction.swift` encodes actions; `CoreWire.swift` decodes only the fields the adapters read. Core keeps one `meta_details` selection, so a new stream lookup replaces the previous one and finishes its stream.
- **Core catalogs.** `CoreCatalogService` loads `board` with every catalog without a required extra and `search` with every catalog that accepts the `search` extra. These are core's rules, and the adapter does not repeat them. Once core holds the selection, an empty `catalogs` list means no add-on offers one. Core lists catalogs without fetching them, on load and again when the profile's add-ons change, so the adapter asks for them with `LoadRange`. That is how an install shows up on the board without another load. `details` loads `meta_details` with no stream path. A stream lookup for the same title, such as an episode of that show, reuses the metadata it loaded. A details call replaces a running stream lookup. `scripts/smoke.sh --no-addons` starts core without its default add-ons (`EMPTY_OFFICIAL_ADDONS=1`) and checks the empty states, then installs Cinemeta and checks that the open board stream fills.
- **SkipDB.** `SkipDBSkipSegmentService` conforms to `SkipSegmentService` over the open SkipDB API (skipdb.tv, no key): recap, intro, outro and preview ranges for an IMDb id, fitted to the stream's duration and clamped to it. It shares `URLSession.json` (`Adapters/HTTP`) for requests, logging and the `HTTPFailure` it maps to `SkipSegmentError`. The `StremioTVAdapterTests` target tests it against recorded responses through a `URLProtocol` stub; set `TEST_RUNNER_STREMIO_LIVE_TESTS=1` to run its live tests too.
- **Aether.** `AetherPlaybackEngine` conforms to `PlaybackEngine` over [AetherEngine](https://github.com/superuser404notfound/AetherEngine). Everything runs on the main actor. It turns the engine's published state into `PlaybackEvent`s, each once per change, and owns the load task. The engine draws into its own view, so the port has no surface: the composition root hands `AetherPlayerSurface` to the UI as `Services.videoSurface`.

### Adding a provider

A provider is a folder under `app/Shared/Adapters/` with types that conform to ports. `Adapters/SkipDB/` is the example: `SkipDBSkipSegmentService` and its private response types, HTTP and decoding failures mapped to `SkipSegmentError`, and one line in `Services.live`. Features and views do not change. A provider for a port keyed by titles keeps results keyed by the same `MediaID`, so stream lookups still match.

### Strictness

Swift 6 with complete concurrency checking, `ExistentialAny` and warnings as errors. SwiftLint runs as a build tool plugin on every app and test build in strict mode (`.swiftlint.yml`). Force unwraps, force casts, `try!`, `@unchecked Sendable`, `nonisolated(unsafe)` and `assumeIsolated` fail the build unless disabled on the line with a reason. The `StremioTVTests` target compiles Domain and Features without the bridge or AetherEngine, so those layers cannot import an adapter.

### Platforms

`app/Shared` is compiled into both apps, including the screens in `app/Shared/UI`. They differ by platform only where input differs (`#if os(tvOS)` for focus sections, card buttons and the remote's commands). The platform folders hold only assets. Views parse text input into domain types before sending events.

### UI

`Theme.swift` holds the colors (`Palette`: canvas, surface, burgundy, red, text, secondary, and the subtitle preview's scene) and the sizes that differ between the TV and a window (`Metrics`). Nothing else names a color value. The shared pieces are `AppLogo`, `Artwork` (an add-on image with a placeholder), `ProgressLine`, `PosterCard`, `ContinueCard`, `Shelf` (a titled sideways row), `SettingsPage` (an emblem beside a list), `SubtitlePreview` (the overlay over a sample scene, the emblem of Settings › Subtitles and of each style choice, where it shows the focused choice), `ValueRow` (a settings row that shows a value and still takes focus) and the player's `PlayerControls`, whose subtitles, audio and speed choices open in an `OptionsPanel` rather than a system `Menu`, which on tvOS leaves nothing focused for over a second after it closes, and `SubtitleOverlay`. The overlay draws the session's visible `SubtitleCue`s above the video and below the controls: text in the user's `SubtitleStyle` (size, font, weight, colors, outline, backing, opacity), sized and raised as fractions of the picture's height so the preview matches the player; bitmaps scaled to the fitted picture where the stream places them. Icons are SF Symbols; empty and error states use `ContentUnavailableView`. The logo (`AppLogo`, asset `Logo`) and the macOS and tvOS app icons, including the tvOS layered icon and Top Shelf images, are generated from `assets/logo.png` by `swift scripts/make-icons.swift assets/logo.png`; rerun it when the logo changes. Navigation is three tabs (Home, Search, Settings), each a `NavigationStack` driven by `Route` (`details`, `streams`).

## Logging

`Log` (`app/Shared/Logging/Log.swift`) writes every line to the unified log (subsystem `com.ograbek.stremio-tv`, one category per area) and to `app.log`: `~/Library/Logs/com.ograbek.stremio-tv/` on macOS, `Library/Caches/Logs/` in the app container on tvOS. Long tokens (debrid keys, add-on configs) are masked. The previous session is kept as `app.previous.log`. Debug builds also echo to stderr. Rust `tracing` output and panics arrive as category `rust:<module>`; AetherEngine's own log (`EngineLog.handler`) arrives under `player` at debug level. Set `STREMIO_LOG_LEVEL` (`trace`, `debug`, `info`, `warning`, `error`) to change the threshold; the default is `debug`.

## Streams

`CoreStreamResults` maps `meta_details` to one source per add-on. It holds the streams the add-on embeds in its metadata for the video (`metaStreams`) first, then its answer to the stream request. Each candidate's player selection carries the stream's request and the metadata request of the first meta add-on that answered, or of the first one while none has. Core's `player` model loads the metadata from it and records progress against it, so a stream picked before the metadata arrives is still tracked. The mapping is tested in `StremioTVAdapterTests`.

Before display, filter the streams to supported sources:

| Source | Handling |
|---|---|
| `Url` | Play. If `proxyHeaders.request` is set, pass the headers to the engine (`LoadOptions.httpHeaders`). |
| `YouTube` | Out of scope for now. |
| `Torrent`, archives, `Nzb` | Hidden. |
| `External`, `PlayerFrame` | Hidden. |

## Player

AetherEngine demuxes each stream with FFmpeg and remuxes it into fMP4 for AVPlayer (route `loopback`), so VideoToolbox decodes, HDR and Dolby Vision reach the display, and Atmos passes through. Codecs fMP4 cannot carry are bridged (DTS and TrueHD to E-AC-3 or FLAC). What AVPlayer cannot play, and anything in the tvOS simulator, decodes in software (route `software`). Only the package's default traits are on. Core's `player` model owns playback state (progress, watched, next episode); `PlayerFeature` reports time (once per second), seeks, pause and end to it through `CorePlaybackTracker`. Core counts the time between two time reports as watched, so every engine seek, whatever started it, goes to core as `Seek` when it begins, before the position moves to its target. Until the seek lands the engine's clock can still read the old position, so `AetherPlaybackEngine` lets only the target through until then. Core copies progress into the library (and so continue watching) on pause, unload and every 180 s, not on every time update.

The progress bar takes focus. A tap of left or right jumps one seek step (`SeekStep`, 10 s unless Settings › Playback says 5, 15 or 30), and quick taps in one direction jump one step further each, up to 60 s. The back and forward buttons, and left and right on the bare video, jump one step (`.jump`). `.begin` reads the step with the languages and sends it back as `.preferencesRead` for its candidate, so the session holds it. Holding one scans at 2×: `PlayerFeature` pauses the engine and moves its own playhead (`Scan`, in `PlayerTimeline.swift`) every 0.25 s with an absolute seek, until select, play/pause or slowing below 2× resumes playback. Each press in the scan's direction doubles its rate up to 32× and each press against it halves it. The UI only tells a tap from a hold (0.5 s); on tvOS a UIKit view reads the arrows' press and release, which SwiftUI does not report for the Siri Remote.

`AetherPlaybackEngine` (`app/Shared/Adapters/Aether/`) maps the port onto the engine:

| Port | AetherEngine |
|---|---|
| `load` | `load(url:startPosition:options:)` in a task the adapter owns; a newer load or `stop` cancels it. `LoadOptions` carries the request headers and the preferred audio and subtitle languages. A cancelled load is not a failure; a failed one is reported once, from `state` |
| `setPaused`, `seek`, `setSpeed`, `stop` | `play`/`pause`, `seek(to:)` (relative seeks start from a seek still landing), `setRate`, `stop` |
| `select`, `turnOffSubtitles`, `addSubtitles` | `selectAudioTrack(index:)`, `selectSubtitleTrack(index:)`, `clearSubtitle()`, `addExternalSubtitleTrack`; `MediaTrack.ID.number` is the engine's track id |
| `loaded`, `paused`, `buffering`, `ended`, `stopped`, `failed` | `$playbackPhase` |
| `position`, `subtitles` | `clock.$currentTime`; cues from `$subtitleCues` whose PTS range holds `clock.$sourceTime` |
| `duration`, `videoSize`, `decoder`, `tracks` | `$duration`, the probed size times its pixel aspect, `$activeVideoDecoder`, the track lists and active indices |
| `diagnostics`, `snapshot` | route, decoders, audio delivery and `diagnostics.liveTelemetry`; `scrubThumbnail`, which decodes from the session's cache so a single-connection debrid link is not asked twice |

Subtitles come from two places, kept apart in the player's subtitles panel: the stream's own tracks ("Built-in") and the files the user's subtitle add-ons offer, one page per add-on grouped by language. Add-on subtitles are add-on driven only; the app calls no subtitle provider itself. A candidate's player selection carries a `subtitlesPath`, so core's `player` model asks every add-on with the `subtitles` resource. Core adds the file's `filename`, `videoSize` and `videoHash` from the stream's hints or from `VideoParamsChanged`, which `CoreSubtitleService` sends once it has fingerprinted the stream: the OpenSubtitles hash of the first and last 64 KiB, read with two range requests to the stream's host (`URLSession.fingerprint`). Add-ons that time subtitles to the file, such as Subtitle Sync, need these to tell this copy apart. A chosen file is registered with `addExternalSubtitleTrack` and selected; the adapter remembers which track id came from which URL, since the engine's track list does not say, and reports it as `MediaTrack.externalFile`.

Subtitles are drawn by the app. Text cues arrive as styled runs (`SubtitleText`): libavcodec turns SRT, WebVTT and ASS tags into the same runs, so bold, italic, underline and strikethrough always show. With file styling on (`SubtitleStyle.usesFileStyling`), a run's color and font replace the user's, and a cue's ASS `\an` / `\pos` placement puts it at an edge, corner or point of the picture; otherwise every text cue joins one block above the bottom edge. A run's ASS font size is ignored, so text keeps the user's size. Bitmap cues (PGS) keep their position.

Wired from core's settings: `audio_language` and `secondary_audio_language`, `subtitles_language` and `secondary_subtitles_language` (as `TrackLanguages`, each a `PreferredLanguages` or nil), `subtitles_auto_select` (off reads as no subtitle languages; choosing Off writes it false), `seek_time_duration` (as `SeekStep`; a value no step matches reads as 10 s and is kept until the user picks another), the subtitle style (`subtitles_size`, `subtitles_font`, `subtitles_bold`, `subtitles_offset`, the colors, `subtitles_opacity` and `ass_subtitles_styling`, as `SubtitleStyle`), and `hide_spoilers` (as `Preferences.hidesSpoilers`; on, each unwatched episode card blurs its still and leaves out its overview), mapped in `CoreGeneralSettings` (audio, seek and spoilers) and `CoreSubtitleSettings`, both tested in `StremioTVAdapterTests`. A font name the app does not know reads as the system font and is kept until the user picks another. Not wired: `seek_short_time_duration` (a keyboard shortcut with no remote equivalent) and `hardware_decoding` (the engine picks the route itself).
