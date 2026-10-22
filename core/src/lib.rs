//! C ABI over stremio-core for the Swift app.
//!
//! Data crosses the boundary as JSON in stremio-core's own serde shapes:
//! actions go in through `sb_dispatch`, model state comes out through `sb_get_state`,
//! and runtime events are pushed to the host's `emit` callback.

mod env;
mod executor;
mod fetch;
mod host;
mod logging;
mod model;
mod scrobble;
mod storage;

use std::path::PathBuf;
use std::sync::OnceLock;

use futures::{future, StreamExt};
use serde::Deserialize;
use stremio_core::runtime::msg::Action;
use stremio_core::runtime::{EnvError, Runtime, RuntimeAction, RuntimeEvent};

use crate::env::AppleEnv;
use crate::fetch::FetchOutcome;
use crate::host::{SBBytes, SBHost, SBOwnedBytes};
use crate::model::{AddonRequest, AppModel, AppModelField};
use crate::scrobble::Scrobble;

static RUNTIME: OnceLock<Runtime<AppleEnv, AppModel>> = OnceLock::new();

/// What `sb_dispatch` accepts: a core action for one model field or all (`null`), or a request
/// the bridge handles itself.
#[derive(Deserialize, Debug)]
#[serde(untagged)]
enum DispatchRequest {
    Core {
        action: Box<Action>,
        field: Option<AppModelField>,
    },
    Bridge(AddonRequest),
}

fn initialize(host: SBHost, storage_directory: PathBuf) -> Result<(), String> {
    if !host::install(host) {
        return Err("sb_initialize was already called".to_owned());
    }
    logging::install();
    tracing::info!(version = env!("CARGO_PKG_VERSION"), "initializing stremio bridge");
    storage::install(storage_directory).map_err(|error| error.message())?;

    let (model, effects) = executor::runtime()
        .block_on(AppModel::load())
        .map_err(|error: EnvError| error.message())?;
    let (runtime, events) = Runtime::<AppleEnv, AppModel>::new(model, effects.into_iter().collect(), 1000);
    executor::spawn_concurrent(events.for_each(|event| {
        if let RuntimeEvent::CoreEvent(core_event) = &event {
            if let Some(scrobble) = Scrobble::from_event(core_event) {
                send_scrobble(scrobble);
            }
        }
        match serde_json::to_vec(&event) {
            Ok(json) => host::emit(&json),
            Err(error) => tracing::error!(%error, "runtime event failed to serialize"),
        }
        future::ready(())
    }));
    RUNTIME
        .set(runtime)
        .map_err(|_| "runtime was already initialized".to_owned())?;
    tracing::info!("stremio bridge ready");
    Ok(())
}

/// Sends `scrobble` for the signed-in account. The model lock is released before it is sent.
fn send_scrobble(scrobble: Scrobble) {
    let auth_key = runtime().and_then(|runtime| {
        let model = runtime
            .model()
            .map_err(|error| format!("model lock poisoned: {error}"))?;
        Ok(model.auth_key().cloned())
    });
    match auth_key {
        Ok(Some(auth_key)) => scrobble.send(auth_key),
        Ok(None) => tracing::debug!("scrobble skipped: signed out"),
        Err(message) => tracing::warn!(%message, "scrobble skipped"),
    }
}

fn runtime() -> Result<&'static Runtime<AppleEnv, AppModel>, String> {
    RUNTIME
        .get()
        .ok_or_else(|| "sb_initialize has not completed".to_owned())
}

fn dispatch(request: &[u8]) -> Result<(), String> {
    let request: DispatchRequest = serde_json::from_slice(request)
        .map_err(|error| format!("invalid dispatch request: {error}"))?;
    let runtime = runtime()?;
    let action = match request {
        DispatchRequest::Core { action, field } => RuntimeAction { field, action: *action },
        DispatchRequest::Bridge(request) => runtime
            .model()
            .map_err(|error| format!("model lock poisoned: {error}"))?
            .queue(request),
    };
    runtime.dispatch(action);
    Ok(())
}

fn get_state(field: &[u8]) -> Result<Vec<u8>, String> {
    let field: AppModelField = serde_json::from_slice(field)
        .map_err(|error| format!("invalid model field: {error}"))?;
    let model = runtime()?
        .model()
        .map_err(|error| format!("model lock poisoned: {error}"))?;
    let state = model
        .state_json(&field)
        .map_err(|error| format!("{field:?} failed to serialize: {error}"))?;
    tracing::trace!(?field, bytes = state.len(), "get_state");
    Ok(state)
}

/// Writes `result`'s error into `error_out` and reports success as a bool.
///
/// # Safety
/// `error_out` must be null or point to writable memory for one `SBOwnedBytes`.
unsafe fn report(result: Result<(), String>, error_out: *mut SBOwnedBytes) -> bool {
    match result {
        Ok(()) => true,
        Err(message) => {
            tracing::error!(%message, "bridge call failed");
            if !error_out.is_null() {
                error_out.write(SBOwnedBytes::from_vec(message.into_bytes()));
            }
            false
        }
    }
}

/// Starts stremio-core. Blocks until persisted state is loaded. Call once.
///
/// # Safety
/// `storage_directory` must be valid UTF-8 bytes; `error_out` as in [`report`].
#[no_mangle]
pub unsafe extern "C" fn sb_initialize(
    host: SBHost,
    storage_directory: SBBytes,
    error_out: *mut SBOwnedBytes,
) -> bool {
    let result = std::str::from_utf8(storage_directory.as_slice())
        .map_err(|error| format!("storage directory is not UTF-8: {error}"))
        .and_then(|directory| initialize(host, PathBuf::from(directory)));
    report(result, error_out)
}

/// Dispatches `{"action": <core Action>, "field": <model field or null>}`, or a bridge request
/// such as `{"setAddonEnabled": {"transportUrl": <url>, "enabled": <bool>}}`.
///
/// # Safety
/// `request` must be valid for reads; `error_out` as in [`report`].
#[no_mangle]
pub unsafe extern "C" fn sb_dispatch(request: SBBytes, error_out: *mut SBOwnedBytes) -> bool {
    report(dispatch(request.as_slice()), error_out)
}

/// Serializes one model field, named by its JSON string (e.g. `"meta_details"`), into `state_out`.
///
/// # Safety
/// `field` must be valid for reads; `state_out` must be writable; `error_out` as in [`report`].
#[no_mangle]
pub unsafe extern "C" fn sb_get_state(
    field: SBBytes,
    state_out: *mut SBOwnedBytes,
    error_out: *mut SBOwnedBytes,
) -> bool {
    let result = get_state(field.as_slice()).map(|state| {
        state_out.write(SBOwnedBytes::from_vec(state));
    });
    report(result, error_out)
}

/// Completes a host fetch with an HTTP response.
///
/// # Safety
/// `body` must be valid for reads.
#[no_mangle]
pub unsafe extern "C" fn sb_fetch_resolve(request_id: u64, status: u16, body: SBBytes) {
    fetch::complete(
        request_id,
        FetchOutcome::Response {
            status,
            body: body.as_slice().to_vec(),
        },
    );
}

/// Completes a host fetch that failed before producing a response.
///
/// # Safety
/// `message` must be valid for reads.
#[no_mangle]
pub unsafe extern "C" fn sb_fetch_reject(request_id: u64, message: SBBytes) {
    let message = String::from_utf8_lossy(message.as_slice()).into_owned();
    fetch::complete(request_id, FetchOutcome::TransportError(message));
}

/// Releases bytes returned by the bridge.
///
/// # Safety
/// `bytes` must come from the bridge and be freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn sb_bytes_free(bytes: SBOwnedBytes) {
    drop(bytes.into_vec());
}

#[cfg(test)]
mod tests {
    use super::*;

    /// These literals are what the Swift `CoreAction` encoder produces.
    /// If core changes an action's shape, this test fails before the app does.
    #[test]
    fn swift_action_shapes_parse_as_core_actions() {
        let requests = [
            r#"{"field":"addon_details","action":{"action":"Load","args":{"model":"AddonDetails","args":{"transportUrl":"https://example.com/manifest.json"}}}}"#,
            r#"{"field":"meta_details","action":{"action":"Load","args":{"model":"MetaDetails","args":{"metaPath":{"resource":"meta","type":"movie","id":"tt0111161","extra":[]},"streamPath":{"resource":"stream","type":"movie","id":"tt0111161","extra":[]},"guessStream":false}}}}"#,
            r#"{"field":"meta_details","action":{"action":"Load","args":{"model":"MetaDetails","args":{"metaPath":{"resource":"meta","type":"series","id":"tt0944947","extra":[]},"guessStream":false}}}}"#,
            r#"{"field":"board","action":{"action":"Load","args":{"model":"CatalogsWithExtra","args":{"type":null,"extra":[]}}}}"#,
            r#"{"field":"search","action":{"action":"Load","args":{"model":"CatalogsWithExtra","args":{"type":null,"extra":[["search","shawshank"]]}}}}"#,
            r#"{"field":"board","action":{"action":"CatalogsWithExtra","args":{"action":"LoadRange","args":{"start":0,"end":12}}}}"#,
            r#"{"field":"discover","action":{"action":"Load","args":{"model":"CatalogWithFilters","args":{"request":{"base":"https://v3-cinemeta.strem.io/manifest.json","path":{"resource":"catalog","type":"movie","id":"top","extra":[["genre","Action"]]}}}}}}"#,
            r#"{"field":"board","action":{"action":"CatalogsWithExtra","args":{"action":"LoadNextPage","args":3}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"Authenticate","args":{"type":"Login","email":"a@b.c","password":"x","facebook":false}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"TimeChanged","args":{"time":1000,"duration":60000,"device":"macos"}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"Seek","args":{"time":30000,"duration":60000,"device":"tvos"}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"VideoParamsChanged","args":{"videoParams":{"hash":"8e245d9679d31e12","size":12909756,"filename":"movie.mkv"}}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"VideoParamsChanged","args":{"videoParams":{"filename":"movie.mkv"}}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"StreamStateChanged","args":{"state":{"subtitleDelay":250,"subtitleTrack":{"id":"https://subs.example/1.srt","embedded":false,"language":"pol"},"audioTrack":{"id":"2","language":"eng"},"playbackSpeed":1.25}}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"StreamStateChanged","args":{"state":{}}}}}"#,
            r#"{"field":"player","action":{"action":"Player","args":{"action":"NextVideo"}}}"#,
            r#"{"field":"player","action":{"action":"Unload"}}"#,
            r#"{"field":"link","action":{"action":"Load","args":{"model":"Link"}}}"#,
            r#"{"field":"link","action":{"action":"Link","args":{"action":"ReadData"}}}"#,
            r#"{"field":"link","action":{"action":"Unload"}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"Authenticate","args":{"type":"LoginWithToken","token":"key"}}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"Logout"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"LibraryItemMarkAsWatched","args":{"id":"tt0111161","is_watched":true}}}}"#,
            r#"{"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"MarkAsWatched","args":false}}}"#,
            r#"{"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"MarkVideoAsWatched","args":[{"id":"tt0944947:1:1","title":"Winter Is Coming","released":"2011-04-17T00:00:00.000Z","season":1,"episode":1},true]}}}"#,
            r#"{"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"MarkSeasonAsWatched","args":[1,false]}}}"#,
            r#"{"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"Rate","args":"liked"}}}"#,
            r#"{"field":"meta_details","action":{"action":"MetaDetails","args":{"action":"Rate","args":null}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"DismissNotificationItem","args":"tt0944947"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"PullNotifications"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"PullUserFromAPI","args":{}}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"PullAddonsFromAPI"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"InstallTraktAddon"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"LogoutTrakt"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"SyncLibraryWithAPI"}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"ClearSearchHistory"}}}"#,
            r#"{"field":"library","action":{"action":"Load","args":{"model":"LibraryWithFilters","args":{"request":{"type":null,"sort":"lastwatched"}}}}}"#,
            r#"{"field":"library","action":{"action":"Load","args":{"model":"LibraryWithFilters","args":{"request":{"type":"series","sort":"notwatched"}}}}}"#,
            r#"{"field":"library","action":{"action":"LibraryWithFilters","args":{"action":"LoadNextPage"}}}"#,
            r#"{"field":"calendar","action":{"action":"Unload"}}"#,
            r#"{"field":"calendar","action":{"action":"Load","args":{"model":"Calendar","args":null}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"AddToLibrary","args":{"id":"tt0944947","type":"series","name":"Game of Thrones","poster":"https://images.example/poster.jpg","posterShape":"poster"}}}}"#,
            r#"{"field":null,"action":{"action":"Ctx","args":{"action":"RemoveFromLibrary","args":"tt0944947"}}}"#,
        ];
        for request in requests {
            let parsed = serde_json::from_str::<DispatchRequest>(request);
            assert!(matches!(parsed, Ok(DispatchRequest::Core { .. })), "{request}\n{parsed:?}");
        }
    }

    /// These literals are what the Swift `BridgeRequest` encoder produces.
    #[test]
    fn swift_bridge_request_shapes_parse_as_bridge_requests() {
        let requests = [
            r#"{"setAddonEnabled":{"transportUrl":"https://example.com/manifest.json","enabled":false}}"#,
            r#"{"setAddonEnabled":{"transportUrl":"https://example.com/manifest.json","enabled":true}}"#,
            r#"{"setAddonOrder":{"transportUrls":["https://two.example/manifest.json","https://example.com/manifest.json"]}}"#,
        ];
        for request in requests {
            let parsed = serde_json::from_str::<DispatchRequest>(request);
            assert!(
                matches!(parsed, Ok(DispatchRequest::Bridge(_))),
                "{request}\n{parsed:?}"
            );
        }
    }

    /// The app reads `Player.stream_state` and sends it back with the track and speed keys changed.
    #[test]
    fn serialized_stream_state_matches_the_swift_shape() {
        use stremio_core::types::streams::{AudioTrack, StreamItemState, SubtitleTrack};
        let state = StreamItemState {
            subtitle_track: Some(SubtitleTrack {
                id: "3".to_owned(),
                embedded: true,
                language: Some("eng".to_owned()),
            }),
            audio_track: Some(AudioTrack {
                id: "1".to_owned(),
                language: None,
            }),
            subtitle_delay: Some(250),
            playback_speed: Some(1.25),
            ..Default::default()
        };
        let expected = serde_json::json!({
            "subtitleTrack": {"id": "3", "embedded": true, "language": "eng"},
            "audioTrack": {"id": "1"},
            "subtitleDelay": 250,
            "playbackSpeed": 1.25,
        });
        assert_eq!(serde_json::to_value(&state).unwrap(), expected);
        assert_eq!(serde_json::from_value::<StreamItemState>(expected).unwrap(), state);
    }

    /// The app updates settings by sending back the settings it read with a few keys changed.
    #[test]
    fn serialized_settings_parse_as_update_settings() {
        let settings = serde_json::to_value(stremio_core::types::profile::Settings::default()).unwrap();
        let request = serde_json::json!({
            "field": null,
            "action": {"action": "Ctx", "args": {"action": "UpdateSettings", "args": settings}},
        });
        let parsed = serde_json::from_value::<DispatchRequest>(request);
        assert!(matches!(parsed, Ok(DispatchRequest::Core { .. })), "{parsed:?}");
    }
}
