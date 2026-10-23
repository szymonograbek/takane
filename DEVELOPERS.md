<img src="assets/logo.png" width="64" alt="">

# Developing Takane

Takane is a custom macOS and tvOS client for Stremio, built on [stremio-core](https://github.com/Stremio/stremio-core) and [AetherEngine](https://github.com/superuser404notfound/AetherEngine). Design notes live in [docs/](docs/README.md).

## Requirements

- Xcode 27, macOS 15 or later on Apple silicon
- `rustup` (the nightly toolchain in `rust-toolchain.toml` installs on first build)
- `brew install xcodegen`
- For tvOS: the tvOS simulator runtime (`xcodebuild -downloadPlatform tvOS`)

## Build and run

```sh
scripts/build-app.sh                      # macOS: generates StremioTV.xcodeproj, builds Debug
open build/DerivedData/Build/Products/Debug/Takane.app
scripts/build-app.sh tvos-sim             # tvOS simulator
scripts/build-app.sh tvos-device          # tvOS device, unsigned (compile and link check)
scripts/install-tvos.sh                   # tvOS device: pick a paired Apple TV, build signed, install, launch
```

Or `xcodegen generate`, open `StremioTV.xcodeproj` in Xcode and run the `StremioTV-macOS` or `StremioTV-tvOS` scheme. The `StremioBridge_*` targets rebuild the Rust bridge before every app build. Without an Apple account, macOS builds are signed ad hoc. To sign with your own account (needed to install on an Apple TV), put your team and identity in a git-ignored `Signing.local.xcconfig`, as described in `Signing.xcconfig`. To list other streaming services under the streams while signed out, put a RapidAPI key for the Streaming Availability API in a git-ignored `Secrets.local.xcconfig`, as described in `Secrets.xcconfig`; builds without it leave the list out.

The app is Takane. First launch asks to sign in with Stremio (a link code confirmed on another device, or email and password) or continue without an account. Then five tabs: Home (a featured title, Continue Watching, every add-on catalog), Library, Calendar, Search and Settings (Account, Add-ons, Sources, Playback, Subtitles, About). Sources are the user's own Jellyfin servers and WebDAV folders: their titles show on Home and in Search like an add-on's, and Library browses their folders. A title opens Details, Play lists the add-ons' playable streams, and the player shows only the video until the remote asks for controls: progress, ±10 s, play/pause, subtitles, audio, speed and Skip Intro.

## Releases

Versions follow [Semantic Versioning](https://semver.org) and come from the [Conventional Commits](https://www.conventionalcommits.org/) on `main`. [release-please](https://github.com/googleapis/release-please) runs on every push to `main` (`.github/workflows/release.yml`) and keeps a release PR open. The PR bumps the version in `project.yml` (`CFBundleShortVersionString`) and `version.txt` and adds the commits to `CHANGELOG.md`: `fix` bumps the patch, `feat` the minor, and `!` the major. Merging it tags `vX.Y.Z`, publishes the GitHub release and attaches `Takane.ipa`, built by `scripts/package-ipa.sh` (Release, unsigned). Run the script locally to get the same `.ipa` in `build/`.

## Logs

macOS: `~/Library/Logs/com.ograbek.takane/app.log` (previous run: `app.previous.log`). tvOS simulator: `Library/Caches/Logs/app.log` inside the app's data container (`xcrun simctl get_app_container booted com.ograbek.takane data`). Also in Console.app under subsystem `com.ograbek.takane`. Swift, Rust and AetherEngine logs share the file, tagged by category. `STREMIO_LOG_LEVEL=trace|debug|info|warning|error` sets the threshold.

Release builds replace personal values in their logs with codes (`#k3f9qa`), the same for the same value. A shared log ends with an encrypted legend of its codes. When a user sends you their log key privately (Settings › About › Share Logs, 12 characters such as `K0FM-Q2XD-91NB`), `swift scripts/reveal-log.swift <log-file> <log-key>` prints the log with each code followed by its value, as in `#k3f9qa‹tt0063350›`. Links show only their origin, so no debrid key is revealed. The key may be typed in any case, with or without dashes; the script takes a moment to stretch it. A wrong key fails with "wrong log key". Never post a user's key or a revealed log in an issue.

## Smoke test

`scripts/smoke.sh [--tvos] [type/id]` builds the app, launches it against a fresh core profile, installs an add-on through core, resolves streams, plays the first playable one for 10 s, pauses, and checks the item appears in continue watching with the right progress. It exits 0 on pass and writes `smoke-result.json` and `smoke-export.log` (what Share Logs would send for the last 15 minutes) next to the log, plus `smoke-frame.png` (the engine's frame at the playhead, when its cache holds one) and, on tvOS, `smoke-screen.png` (simulator screenshot). `--tvos` runs on a "Stremio Apple TV" simulator, created on first use.

The add-on URL contains debrid credentials, so it is read from `STREMIO_SMOKE_ADDON_URL` or a git-ignored `.env.smoke`:

```sh
echo 'STREMIO_SMOKE_ADDON_URL=https://…/manifest.json' > .env.smoke
scripts/smoke.sh                       # movie/tt0063350, Night of the Living Dead (1968, public domain)
scripts/smoke.sh series/tt1748166:1:1  # Pioneer One (Creative Commons)
scripts/smoke.sh --tvos
```

UI verification on tvOS (agent-device driving the simulator with remote presses, evidence under `build/verify/`): see `.claude/skills/verify-stremio-tv/SKILL.md` and its feature map.

Unit tests for the domain and feature state machines: `scripts/test.sh`. SwiftLint runs on every build as an Xcode build tool plugin; its warnings fail the build (`.swiftlint.yml`). Architecture and conventions for contributors and agents: [CLAUDE.md](CLAUDE.md) and [docs/architecture.md](docs/architecture.md).

Rust tests: `cd core && rustup run nightly-2026-10-18 cargo test` (the toolchain in `rust-toolchain.toml`; a Homebrew `cargo` on PATH would ignore it).

## Media source servers

`scripts/dev-sources.sh up` runs a Jellyfin server and a WebDAV folder in Docker (OrbStack or Docker Desktop) over the same silent test clips: four Creative Commons films, three episodes of Pioneer One and one home video. The first run generates the clips with ffmpeg and sets up Jellyfin through its API, about 30 s. It prints the URLs and the user and password (`takane` / `takane-dev`): `localhost` for the simulator, the Mac's network address for an Apple TV. `env` prints them again, `down` stops the servers and `reset` deletes their state under `build/dev-sources`.
