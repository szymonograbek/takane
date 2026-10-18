# stremio-apple-tv

SwiftUI macOS and tvOS client over stremio-core (Rust bridge in `core/`) with mpv playback. The design, with its reasons, is in [docs/architecture.md](docs/architecture.md). Read its **App architecture** section before adding a screen, a service or a provider.

## Layers

Dependencies point inward: UI → Features → Domain ← Adapters. The composition root (`app/Shared/App/StremioApp.swift`) is the only code that knows every layer.

- **Domain** (`app/Shared/Domain`) holds values, branded identifiers, ports and their errors. A port is a protocol named for a capability (`StreamService`, `PlaybackEngine`), never for a provider. Foundation, CoreGraphics and QuartzCore only.
- **Features** (`app/Shared/Features`) holds one finite state machine per behavior: a `Feature` with `State`, `Event`, `Effect`, a pure `reduce` and a policy-free `run`. Features see ports, never adapters.
- **Adapters** (`app/Shared/Adapters/<Provider>`) implement ports: `Core` over stremio-core, `MPV` over libmpv. Wire formats, FFI and provider quirks stay inside the adapter folder.
- **UI** (`app/macOS`, `app/tvOS`) renders `FeatureStore.state` and calls `send`. Views parse user input into domain types (`ManifestURL(text)`, `PlayableID(text)`) before sending.

The test target compiles Domain and Features without the bridge or mpv, so an import of an adapter from those layers fails the build. Keep it that way.

## Rules

- **Typed errors.** Each port has its own error enum and throws it with `throws(PortError)`. Adapters translate provider failures into it. A failure the UI shows lives in feature state (`case failed(…, AddonError)`), not in a thrown error or a `String`.
- **State machines.** Model behavior as an enum `State` and handle it with an exhaustive `switch (state, event)`. List the ignored combinations by name instead of using `default`, so a new state or event forces a decision. Events carry the identity they answer (`installFinished(ManifestURL, …)`), and `reduce` drops answers for a request that is no longer current.
- **One effect per ordered sequence.** The store starts each effect in its own task. Calls that must happen in order belong in one effect (`PlayerFeature.Effect.begin`).
- **Branded values.** Give every identifier and validated primitive its own type, built by a failable or throwing initializer at the boundary. Inside, trust the type.
- **Core owns its state.** Read core data through a port's `AsyncStream` and keep no copy outside the feature state that renders it. Waiting on core uses `CoreRuntime.request` (subscribe, dispatch, probe), which also means a probe checks that the state it sees answers this request.
- **Strictness.** Swift 6 with complete concurrency checking, `ExistentialAny`, warnings as errors and SwiftLint in strict mode (`.swiftlint.yml`) on every build. Force unwraps, force casts, `try!`, `@unchecked Sendable`, `nonisolated(unsafe)` and `assumeIsolated` fail the build. When one is truly unavoidable (C pointers, non-Sendable SDK types), disable the rule on that line and give the reason in the declaration's doc comment.

## Recipes

**New screen or behavior.** Write the `Feature` in `app/Shared/Features`, with tests in `app/Tests` that drive `reduce` and assert states and effects. Create its `FeatureStore` in `AppContext` (app-wide) or in the view that owns it (screen-lifetime), then render it per platform.

**New capability** (metadata, artwork, search…). Add the port, its values and its error enum to `app/Shared/Domain`, implement it in an adapter, and add it to `Services`.

**New provider for an existing port** (TMDB for metadata, say). Add `app/Shared/Adapters/<Provider>/` with a type that conforms to the port. Point the port at it in `Services.live`. Features, views and other adapters stay untouched.

## Commits

Write [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary` in the imperative, lowercase, no trailing period, at most 72 characters. Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`. Scope names the area touched: `domain`, `features`, `core`, `mpv`, `ui`, `bridge` (Rust), `scripts`. Mark breaking changes with `!` after the scope. One logical change per commit.

## Commands

- `scripts/test.sh` runs the unit tests (lint included).
- `scripts/build-app.sh [macos|tvos-sim|tvos-device]` builds the app.
- `scripts/smoke.sh [--tvos] [type/id]` runs the end-to-end smoke journey. Run it after changing adapters, the player or the composition root.
- The **verify-stremio-tv** skill drives the tvOS UI. Use it before claiming a UI change works.
- `xcodegen generate` after adding or moving files; the Xcode project is generated from `project.yml`.
