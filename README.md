<img src="assets/logo.png" width="64" alt="">

# Takane

Custom macOS and tvOS client for Stremio, built on [stremio-core](https://github.com/Stremio/stremio-core) and [MPVKit](https://github.com/mpvkit/MPVKit). Design notes live in [docs/](docs/README.md).

## Requirements

- Xcode 27, macOS 15 or later on Apple silicon
- `rustup` (the nightly toolchain in `rust-toolchain.toml` installs on first build)
- `brew install xcodegen`
- For tvOS: the tvOS simulator runtime (`xcodebuild -downloadPlatform tvOS`)

## Build and run

```sh
scripts/build-app.sh                      # macOS: generates StremioTV.xcodeproj, builds Debug
open build/DerivedData/Build/Products/Debug/StremioTV.app
scripts/build-app.sh tvos-sim             # tvOS simulator
scripts/build-app.sh tvos-device          # tvOS device, unsigned (compile and link check)
```

Or `xcodegen generate`, open `StremioTV.xcodeproj` in Xcode and run the `StremioTV-macOS` or `StremioTV-tvOS` scheme. The `StremioBridge_*` targets rebuild the Rust bridge before every app build. Signing uses the personal team (`F43U35GPD2`) with the `Apple Development: szymon@ograbek.com` identity.

The app is Takane. First launch asks to sign in with Stremio (a link code confirmed on another device, or email and password) or continue without an account. Then three tabs: Home (a featured title, Continue Watching, every add-on catalog), Settings (Account, Add-ons, Playback, About) and Search. A title opens Details, Play lists the add-ons' playable streams, and the player shows only the video until the remote asks for controls: progress, ±10 s, play/pause, subtitles, audio, speed and Skip Intro.

## Logs

macOS: `~/Library/Logs/com.ograbek.stremio-tv/app.log` (previous run: `app.previous.log`). tvOS simulator: `Library/Caches/Logs/app.log` inside the app's data container (`xcrun simctl get_app_container booted com.ograbek.stremio-tv data`). Also in Console.app under subsystem `com.ograbek.stremio-tv`. Swift, Rust and mpv logs share the file, tagged by category. `STREMIO_LOG_LEVEL=trace|debug|info|warning|error` sets the threshold.

## Smoke test

`scripts/smoke.sh [--tvos] [type/id]` builds the app, launches it against a fresh core profile, installs an add-on through core, resolves streams, plays the first playable one for 10 s, pauses, and checks the item appears in continue watching with the right progress. It exits 0 on pass and writes `smoke-result.json` next to the log, plus `smoke-frame.png` (mpv frame, macOS) or `smoke-screen.png` (simulator screenshot, tvOS). `--tvos` runs on a "Stremio Apple TV" simulator, created on first use.

The add-on URL contains debrid credentials, so it is read from `STREMIO_SMOKE_ADDON_URL` or a git-ignored `.env.smoke`:

```sh
echo 'STREMIO_SMOKE_ADDON_URL=https://…/manifest.json' > .env.smoke
scripts/smoke.sh                       # movie/tt0111161
scripts/smoke.sh series/tt0944947:1:1
scripts/smoke.sh --tvos
```

UI verification on tvOS (agent-device driving the simulator with remote presses, evidence under `build/verify/`): see `.claude/skills/verify-stremio-tv/SKILL.md` and its feature map.

Unit tests for the domain and feature state machines: `scripts/test.sh`. SwiftLint runs on every build as an Xcode build tool plugin; its warnings fail the build (`.swiftlint.yml`). Architecture and conventions for contributors and agents: [CLAUDE.md](CLAUDE.md) and [docs/architecture.md](docs/architecture.md).

Rust tests: `cd core && rustup run nightly-2026-10-18 cargo test` (the toolchain in `rust-toolchain.toml`; a Homebrew `cargo` on PATH would ignore it).
