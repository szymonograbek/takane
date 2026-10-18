# Roadmap

Each step ends with a check that proves it works before moving on.

**Status (2026-10-18).** The macOS foundation is in place: Rust bridge, Swift core client, MPVKit playback and logging. `scripts/smoke.sh` proves it end to end: install an add-on through core, resolve streams, play a debrid stream, see progress in continue watching. The CLI from step 1 was replaced by that in-app smoke test, and login is not wired yet. The tvOS app builds from the same sources and passes the same smoke test in the simulator (`scripts/smoke.sh --tvos`); the device build links but has not run on hardware. Step 3's real screens are next.

## 1. Rust bridge and CLI

Build the bridge crate and a small CLI on top of it.

- Log in, load library and continue watching.
- Install or sync a debrid add-on, open an item, resolve streams.

**Verify:** CLI prints library items and playable `Url` streams from a real account. Rust unit tests use core's `TestEnv`.

## 2. XCFramework and Swift client

Package the bridge for macOS, tvOS device and tvOS simulator. Generate Swift protobuf types and the core client.

**Verify:** a Swift test or minimal macOS target logs in and reads library state through the FFI.

## 3. macOS app

Home (continue watching + catalog rows), discover, search, detail with filtered stream list, MPVKit playback with progress reporting.

**Verify:** run locally; play a debrid stream, switch audio and subtitle tracks, confirm progress appears in continue watching on another Stremio client.

## 4. tvOS port

Focus navigation, TV layout, code / QR login via `link`.

**Verify:** drive the tvOS simulator with the remote and capture screenshots of each screen and the playback flow.

## 5. Settings

Settings screen bound to core profile settings; applied to mpv on playback start.

**Verify:** change subtitle language and style, start playback, confirm the selected track and styling; confirm settings sync to another Stremio client.

## 6. Hardware pass

Sideload to a real Apple TV.

**Verify:** HDR / Dolby Vision output, audio passthrough, frame-rate matching, remote ergonomics.
