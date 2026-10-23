//! The user's own media sources, as add-ons the app answers itself, and the guard that keeps their
//! titles on this device.
//!
//! Swift sends every source's descriptor with `SetSources` on launch and whenever the list
//! changes. The bridge keeps them out of `ctx`, so core never saves them, never pushes them to the
//! account with `addonCollectionSet`, and a pull from the account cannot drop them. Their URLs are
//! under the reserved `.invalid` domain, so the host answers their requests in the app.
//!
//! A title found only on a source has a local id (`takane-…`). Its library item, progress and
//! watched state stay on this device: [`guard_egress`] removes it from each Stremio request that
//! names a library item. The others carry no library item id: `datastoreGet` asks only for ids the
//! account already has, `datastoreMeta` sends none, ratings are read only for `tt`, `tmdb` and
//! `kitsu` ids, and core's analytics `events` are never sent (the bridge sends only scrobbles,
//! which `scrobble` keeps to titles that are not local). Requests to add-ons are not Stremio's: an
//! add-on that declares no id prefixes may still be asked for streams or sent events of a local id.

use serde::Deserialize;
use serde_json::Value;
use stremio_core::types::addon::{Descriptor, ManifestResource};

use crate::fetch::{FetchOutcome, FetchRequest};

/// Every local id starts with this. Swift mints ids with the same literal, and each source
/// add-on's id prefixes besides `tt` must start with it, so the two cannot drift apart unnoticed.
pub const LOCAL_ID_PREFIX: &str = "takane-";

/// The domain each source add-on's transport URL is under: `https://<source id>.source.invalid/manifest.json`.
const SOURCE_DOMAIN: &str = ".source.invalid";

/// The source add-ons, each checked when it is parsed: a transport URL under `.source.invalid` and
/// id prefixes that are `tt` or local.
#[derive(Clone, Default, PartialEq, Debug, Deserialize)]
#[serde(try_from = "Vec<Descriptor>")]
pub struct SourceAddons(Vec<Descriptor>);

impl TryFrom<Vec<Descriptor>> for SourceAddons {
    type Error = String;

    fn try_from(descriptors: Vec<Descriptor>) -> Result<Self, Self::Error> {
        for descriptor in &descriptors {
            check(descriptor)?;
        }
        Ok(SourceAddons(descriptors))
    }
}

impl SourceAddons {
    pub fn iter(&self) -> impl Iterator<Item = &Descriptor> {
        self.0.iter()
    }
}

fn check(descriptor: &Descriptor) -> Result<(), String> {
    let url = &descriptor.transport_url;
    let source_id = url.host_str().and_then(|host| host.strip_suffix(SOURCE_DOMAIN));
    let source_url = url.scheme() == "https"
        && source_id.is_some_and(|id| !id.is_empty() && !id.contains('.'))
        && url.port().is_none()
        && url.username().is_empty()
        && url.password().is_none()
        && url.path() == "/manifest.json"
        && url.query().is_none()
        && url.fragment().is_none();
    if !source_url {
        return Err(format!("source add-on {url} is not https://<source id>{SOURCE_DOMAIN}/manifest.json"));
    }
    let manifest = &descriptor.manifest;
    let resource_prefixes = manifest.resources.iter().filter_map(|resource| match resource {
        ManifestResource::Short(_) => None,
        ManifestResource::Full { id_prefixes, .. } => id_prefixes.as_ref(),
    });
    let foreign = manifest
        .id_prefixes
        .iter()
        .chain(resource_prefixes)
        .flatten()
        .find(|prefix| *prefix != "tt" && !prefix.starts_with(LOCAL_ID_PREFIX));
    match foreign {
        Some(prefix) => Err(format!("source add-on {url} declares id prefix {prefix:?}, neither tt nor {LOCAL_ID_PREFIX}…")),
        None => Ok(()),
    }
}

pub fn is_local(id: &str) -> bool {
    id.starts_with(LOCAL_ID_PREFIX)
}

const LIBRARY_PUT_URL: &str = "https://api.strem.io/api/datastorePut";

/// What Stremio's API answers a request that succeeded with nothing to return.
const SUCCESS: &str = r#"{"result":{"success":true}}"#;

/// Stremio requests that name one library item: the URL, the body field holding the item's id,
/// and the reply core gets instead when that item is local.
const ONE_ITEM_REQUESTS: &[(&str, &str, &str)] = &[
    ("https://api.strem.io/api/seekLog", "itemId", SUCCESS),
    ("https://api.strem.io/api/getSkipGaps", "itemId", r#"{"result":{"accuracy":"","gaps":{}}}"#),
    ("https://likes.stremio.com/api/send", "mediaId", r#"{"message":"kept on this device"}"#),
];

/// Keeps local library items out of `request` when it is bound for Stremio: a `datastorePut` of
/// library items loses the local ones, and a request about one local item is not sent. Returns the
/// reply core gets instead when nothing is left to send.
pub fn guard_egress(request: &mut FetchRequest) -> Option<FetchOutcome> {
    if request.url == LIBRARY_PUT_URL {
        return keep_local_items_out(request);
    }
    let (url, id_field, local_reply) = ONE_ITEM_REQUESTS.iter().find(|(url, ..)| request.url == *url)?;
    let body: Value = serde_json::from_str(request.body.as_deref()?).ok()?;
    if !body[id_field].as_str().is_some_and(is_local) {
        return None;
    }
    tracing::info!(url, "request about a local title kept on this device");
    Some(reply(local_reply))
}

/// Drops the local items from a `datastorePut` of library items.
fn keep_local_items_out(request: &mut FetchRequest) -> Option<FetchOutcome> {
    let mut body: Value = serde_json::from_str(request.body.as_deref()?).ok()?;
    if body["collection"] != stremio_core::constants::LIBRARY_COLLECTION_NAME {
        return None;
    }
    let changes = body.get_mut("changes")?.as_array_mut()?;
    let before = changes.len();
    changes.retain(|item| !item["_id"].as_str().is_some_and(is_local));
    let kept = changes.len();
    if kept == before {
        return None;
    }
    tracing::info!(kept, dropped = before - kept, "local library items kept off the account");
    if kept == 0 {
        return Some(reply(SUCCESS));
    }
    request.body = Some(body.to_string());
    None
}

fn reply(body: &str) -> FetchOutcome {
    FetchOutcome::Response { status: 200, body: body.as_bytes().to_vec() }
}

#[cfg(test)]
mod tests {
    use std::marker::PhantomData;

    use futures::FutureExt;
    use serde_json::json;
    use stremio_core::constants::LIBRARY_COLLECTION_NAME;
    use stremio_core::runtime::Env;
    use stremio_core::types::api::{
        fetch_api, APIRequest, APIResult, DatastoreCommand, DatastoreRequest, SeekLogRequest,
        SkipGapsRequest, SkipGapsResponse, SuccessResponse,
    };
    use stremio_core::types::library::LibraryItem;
    use stremio_core::types::profile::AuthKey;
    use stremio_core::types::rating::{Rating, RatingSendRequest, RatingSendRequestBody, RatingSendResponse};
    use stremio_core::types::resource::{MetaItemPreview, SeriesInfo};

    use super::*;
    use crate::env::AppleEnv;
    use crate::host::recording;

    const LOCAL: &str = "takane-ab12cd34-0ae5";

    fn library_item(id: &str) -> LibraryItem {
        let preview: MetaItemPreview =
            serde_json::from_value(json!({"id": id, "type": "movie", "name": id})).unwrap();
        LibraryItem::from((&preview, PhantomData::<AppleEnv>))
    }

    fn put(auth_key: &str, ids: &[&str]) -> DatastoreRequest {
        DatastoreRequest {
            auth_key: AuthKey(auth_key.to_owned()),
            collection: LIBRARY_COLLECTION_NAME.to_owned(),
            command: DatastoreCommand::Put { changes: ids.iter().map(|id| library_item(id)).collect() },
        }
    }

    fn sent_ids(fetch: &recording::Fetch) -> Vec<&str> {
        fetch.body["changes"].as_array().unwrap().iter().map(|item| item["_id"].as_str().unwrap()).collect()
    }

    #[test]
    fn a_library_put_sends_only_the_items_that_are_not_local() {
        recording::install();
        let response = fetch_api::<AppleEnv, _, _, SuccessResponse>(&put("mixed-put", &["tt1727587", LOCAL]));

        let fetches = recording::fetches_with("authKey", "mixed-put");
        assert_eq!(fetches.len(), 1);
        assert_eq!(fetches[0].url, LIBRARY_PUT_URL);
        assert_eq!(fetches[0].body["collection"], LIBRARY_COLLECTION_NAME);
        assert_eq!(sent_ids(&fetches[0]), ["tt1727587"]);

        crate::fetch::complete(fetches[0].id, reply(SUCCESS));
        assert!(matches!(response.now_or_never(), Some(Ok(APIResult::Ok(_)))));
    }

    #[test]
    fn a_library_put_of_only_local_items_is_answered_with_success_and_not_sent() {
        recording::install();
        let response = fetch_api::<AppleEnv, _, _, SuccessResponse>(&put("local-put", &[LOCAL, "takane-ab12cd34-1bf6"]));

        assert!(recording::fetches_with("authKey", "local-put").is_empty());
        assert!(matches!(response.now_or_never(), Some(Ok(APIResult::Ok(_)))));
    }

    #[test]
    fn a_library_put_without_local_items_is_sent_as_core_built_it() {
        recording::install();
        let request = put("remote-put", &["tt1727587", "tt0944947"]);
        let _response = fetch_api::<AppleEnv, _, _, SuccessResponse>(&request);

        let fetches = recording::fetches_with("authKey", "remote-put");
        assert_eq!(fetches.len(), 1);
        assert_eq!(fetches[0].body, serde_json::to_value(&request).unwrap());
    }

    fn seek_log(item_id: &str, stream_name_hash: &str) -> APIRequest {
        APIRequest::SeekLog(SeekLogRequest {
            os_hash: "8e245d9679d31e12".to_owned(),
            item_id: item_id.to_owned(),
            series_info: SeriesInfo { season: 0, episode: 0 },
            stream_name_hash: stream_name_hash.to_owned(),
            duration: 60_000,
            seek_history: vec![],
            skip_outro: vec![],
        })
    }

    fn skip_gaps(item_id: &str, auth_key: &str) -> APIRequest {
        APIRequest::SkipGaps(SkipGapsRequest {
            auth_key: AuthKey(auth_key.to_owned()),
            os_hash: "8e245d9679d31e12".to_owned(),
            item_id: item_id.to_owned(),
            series_info: SeriesInfo { season: 0, episode: 0 },
            stream_name_hash: "hash".to_owned(),
        })
    }

    fn watched(meta_item_id: &str, auth_key: &str) -> http::Request<RatingSendRequestBody> {
        RatingSendRequest {
            auth_key: AuthKey(auth_key.to_owned()),
            meta_item_id: meta_item_id.to_owned(),
            meta_item_type: "movie".to_owned(),
            rating: Some(Rating::Watched),
        }
        .into()
    }

    #[test]
    fn requests_about_one_local_title_are_answered_here() {
        recording::install();
        let seek_log = fetch_api::<AppleEnv, _, _, SuccessResponse>(&seek_log(LOCAL, "local-seek-log"));
        let skip_gaps = fetch_api::<AppleEnv, _, _, SkipGapsResponse>(&skip_gaps(LOCAL, "local-skip-gaps"));
        let watched = AppleEnv::fetch::<_, RatingSendResponse>(watched(LOCAL, "local-watched"));

        assert!(recording::fetches_with("stHash", "local-seek-log").is_empty());
        assert!(recording::fetches_with("authKey", "local-skip-gaps").is_empty());
        assert!(recording::fetches_with("authToken", "local-watched").is_empty());
        assert!(matches!(seek_log.now_or_never(), Some(Ok(APIResult::Ok(_)))));
        assert!(matches!(skip_gaps.now_or_never(), Some(Ok(APIResult::Ok(gaps))) if gaps.gaps.is_empty()));
        assert!(matches!(watched.now_or_never(), Some(Ok(_))));
    }

    #[test]
    fn requests_about_one_title_that_is_not_local_are_sent() {
        recording::install();
        let _seek_log = fetch_api::<AppleEnv, _, _, SuccessResponse>(&seek_log("tt1727587", "remote-seek-log"));
        let _skip_gaps = fetch_api::<AppleEnv, _, _, SkipGapsResponse>(&skip_gaps("tt1727587", "remote-skip-gaps"));
        let _watched = AppleEnv::fetch::<_, RatingSendResponse>(watched("tt1727587", "remote-watched"));

        let sent = |field, value| recording::fetches_with(field, value).into_iter().map(|fetch| fetch.url).collect::<Vec<_>>();
        assert_eq!(sent("stHash", "remote-seek-log"), ["https://api.strem.io/api/seekLog"]);
        assert_eq!(sent("authKey", "remote-skip-gaps"), ["https://api.strem.io/api/getSkipGaps"]);
        assert_eq!(sent("authToken", "remote-watched"), ["https://likes.stremio.com/api/send"]);
    }
}
