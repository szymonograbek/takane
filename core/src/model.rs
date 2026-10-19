//! The stremio-core models this app runs, and how they are created from storage.

use chrono::{DateTime, Duration, Utc};
use futures::try_join;
use serde::Serialize;
use stremio_core::constants::{
    DISMISSED_EVENTS_STORAGE_KEY, LIBRARY_RECENT_STORAGE_KEY, LIBRARY_STORAGE_KEY,
    NOTIFICATIONS_STORAGE_KEY, PROFILE_STORAGE_KEY, SEARCH_HISTORY_STORAGE_KEY,
    STREAMING_SERVER_URLS_STORAGE_KEY, STREAMS_STORAGE_KEY,
};
use stremio_core::models::addon_details::AddonDetails;
use stremio_core::models::calendar::{Calendar, Selected as CalendarSelected};
use stremio_core::models::catalog_with_filters::CatalogWithFilters;
use stremio_core::models::catalogs_with_extra::CatalogsWithExtra;
use stremio_core::models::continue_watching_preview::ContinueWatchingPreview;
use stremio_core::models::ctx::Ctx;
use stremio_core::models::common::{Loadable, ResourceLoadable};
use stremio_core::models::library_with_filters::{LibraryWithFilters, NotRemovedFilter};
use stremio_core::models::link::Link;
use stremio_core::models::meta_details::MetaDetails;
use stremio_core::models::player::Player;
use stremio_core::runtime::{Effects, Env, EnvError};
use stremio_core::types::api::LinkAuthKey;
use stremio_core::types::events::DismissedEventsBucket;
use stremio_core::types::library::LibraryBucket;
use stremio_core::types::notifications::NotificationsBucket;
use stremio_core::types::profile::Profile;
use stremio_core::types::resource::{MetaItem, MetaItemPreview, PosterShape, Video};
use stremio_core::types::search_history::SearchHistoryBucket;
use stremio_core::types::server_urls::ServerUrlsBucket;
use stremio_core::types::streams::StreamsBucket;
use stremio_core::Model;

use crate::env::AppleEnv;

/// Add a field here to expose another core model to the app.
#[derive(Model, Clone)]
#[model(AppleEnv)]
pub struct AppModel {
    pub ctx: Ctx,
    pub continue_watching_preview: ContinueWatchingPreview,
    pub addon_details: AddonDetails,
    /// Home rows: every installed catalog without a required extra.
    pub board: CatalogsWithExtra,
    /// Catalogs that support the `search` extra, loaded with the query.
    pub search: CatalogsWithExtra,
    /// One catalog of one add-on with its extras, such as a genre.
    pub discover: CatalogWithFilters<MetaItemPreview>,
    pub meta_details: MetaDetails,
    pub player: Player,
    /// Sign-in by code: a code to confirm on another device, then the auth key it grants.
    pub link: Link<LinkAuthKey>,
    /// The titles in the library, one type or all, sorted and paged.
    pub library: LibraryWithFilters<NotRemovedFilter>,
    /// The library's shows with their videos, from add-ons that list videos by id.
    pub calendar: Calendar,
}

impl AppModel {
    /// Migrates storage, then builds the model from whatever was persisted.
    pub async fn load() -> Result<(AppModel, Effects), EnvError> {
        AppleEnv::migrate_storage_schema().await?;
        let (
            profile,
            recent_library,
            other_library,
            streams,
            server_urls,
            notifications,
            search_history,
            dismissed_events,
        ) = try_join!(
            AppleEnv::get_storage::<Profile>(PROFILE_STORAGE_KEY),
            AppleEnv::get_storage::<LibraryBucket>(LIBRARY_RECENT_STORAGE_KEY),
            AppleEnv::get_storage::<LibraryBucket>(LIBRARY_STORAGE_KEY),
            AppleEnv::get_storage::<StreamsBucket>(STREAMS_STORAGE_KEY),
            AppleEnv::get_storage::<ServerUrlsBucket>(STREAMING_SERVER_URLS_STORAGE_KEY),
            AppleEnv::get_storage::<NotificationsBucket>(NOTIFICATIONS_STORAGE_KEY),
            AppleEnv::get_storage::<SearchHistoryBucket>(SEARCH_HISTORY_STORAGE_KEY),
            AppleEnv::get_storage::<DismissedEventsBucket>(DISMISSED_EVENTS_STORAGE_KEY),
        )?;

        let profile = profile.unwrap_or_default();
        let uid = profile.uid();
        tracing::info!(
            authenticated = profile.auth.is_some(),
            addons = profile.addons.len(),
            "profile loaded"
        );
        let mut library = LibraryBucket::new(uid.clone(), vec![]);
        for bucket in [recent_library, other_library].into_iter().flatten() {
            library.merge_bucket(bucket);
        }
        tracing::info!(items = library.items.len(), "library loaded");

        let notifications =
            notifications.unwrap_or_else(|| NotificationsBucket::new::<AppleEnv>(uid.clone(), vec![]));
        let (continue_watching_preview, continue_watching_effects) =
            ContinueWatchingPreview::new(&library, &notifications);
        let ctx = Ctx::new(
            profile,
            library,
            streams.unwrap_or_else(|| StreamsBucket::new(uid.clone())),
            server_urls.unwrap_or_else(|| ServerUrlsBucket::new::<AppleEnv>(uid.clone())),
            notifications,
            search_history.unwrap_or_else(|| SearchHistoryBucket::new(uid.clone())),
            dismissed_events.unwrap_or_else(|| DismissedEventsBucket::new(uid)),
        );
        let model = AppModel {
            ctx,
            continue_watching_preview,
            addon_details: Default::default(),
            board: Default::default(),
            search: Default::default(),
            discover: Default::default(),
            meta_details: Default::default(),
            player: Default::default(),
            link: Default::default(),
            library: Default::default(),
            calendar: Default::default(),
        };
        Ok((model, continue_watching_effects))
    }

    pub fn state_json(&self, field: &AppModelField) -> serde_json::Result<Vec<u8>> {
        match field {
            AppModelField::Ctx => serde_json::to_vec(&CtxState::new(&self.ctx)),
            AppModelField::ContinueWatchingPreview => serde_json::to_vec(&self.continue_watching_preview),
            AppModelField::AddonDetails => serde_json::to_vec(&self.addon_details),
            AppModelField::Board => serde_json::to_vec(&self.board),
            AppModelField::Search => serde_json::to_vec(&self.search),
            AppModelField::Discover => serde_json::to_vec(&self.discover),
            AppModelField::MetaDetails => serde_json::to_vec(&MetaDetailsState::new(&self.meta_details)),
            AppModelField::Player => serde_json::to_vec(&self.player),
            AppModelField::Link => serde_json::to_vec(&self.link),
            AppModelField::Library => serde_json::to_vec(&self.library),
            AppModelField::Calendar => serde_json::to_vec(&CalendarState::new(&self.calendar, AppleEnv::now())),
        }
    }
}

/// Core's `Ctx` plus the queries searched, which core keeps out of its serialized state.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CtxState<'a> {
    #[serde(flatten)]
    ctx: &'a Ctx,
    search_history: Vec<&'a str>,
}

impl<'a> CtxState<'a> {
    fn new(ctx: &'a Ctx) -> Self {
        CtxState { ctx, search_history: recent_searches(&ctx.search_history) }
    }
}

/// Queries most recent first. The query breaks ties, so the order is stable.
fn recent_searches(history: &SearchHistoryBucket) -> Vec<&str> {
    let mut searches: Vec<_> = history.items.iter().collect();
    searches.sort_by(|(query, searched), (other_query, other_searched)| {
        other_searched.cmp(searched).then_with(|| query.cmp(other_query))
    });
    searches.into_iter().map(|(query, _)| query.as_str()).collect()
}

/// Core's `MetaDetails` plus the ids of the shown title's videos the user has watched, which
/// core keeps out of its serialized state.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MetaDetailsState<'a> {
    #[serde(flatten)]
    model: &'a MetaDetails,
    watched_videos: Vec<&'a str>,
}

impl<'a> MetaDetailsState<'a> {
    /// Core computes `watched` for the first ready meta item, so the ids come from that one.
    fn new(model: &'a MetaDetails) -> Self {
        let meta_item = model.meta_items.iter().find_map(|meta_item| match &meta_item.content {
            Some(Loadable::Ready(meta_item)) => Some(meta_item),
            _ => None,
        });
        let watched_videos = match (meta_item, &model.watched) {
            (Some(meta_item), Some(watched)) => meta_item
                .videos
                .iter()
                .filter(|video| watched.get_video(&video.id))
                .map(|video| video.id.as_str())
                .collect(),
            _ => vec![],
        };
        MetaDetailsState { model, watched_videos }
    }
}

/// Core's `Calendar` cut to what the app shows: each show without the videos released before
/// `now - 24h`. Core holds every video of each show and repeats this month's in `items`, which
/// would make every state read large.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CalendarState<'a> {
    /// The month core loaded for, or none while unloaded.
    selected: &'a Option<CalendarSelected>,
    meta_items: Vec<ResourceLoadable<Vec<UpcomingShow<'a>>>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UpcomingShow<'a> {
    id: &'a str,
    r#type: &'a str,
    name: &'a str,
    poster: Option<&'a url::Url>,
    poster_shape: &'a PosterShape,
    background: Option<&'a url::Url>,
    logo: Option<&'a url::Url>,
    videos: Vec<&'a Video>,
}

impl<'a> CalendarState<'a> {
    /// The day before `now` keeps today's earlier releases in every time zone; the app drops the
    /// ones before the viewer's local today.
    fn new(model: &'a Calendar, now: DateTime<Utc>) -> Self {
        let since = now - Duration::hours(24);
        let meta_items = model
            .meta_items
            .iter()
            .map(|resource| ResourceLoadable {
                request: resource.request.clone(),
                content: resource.content.as_ref().map(|content| match content {
                    Loadable::Loading => Loadable::Loading,
                    Loadable::Ready(shows) => {
                        Loadable::Ready(shows.iter().map(|show| UpcomingShow::new(show, since)).collect())
                    }
                    Loadable::Err(error) => Loadable::Err(error.clone()),
                }),
            })
            .collect();
        CalendarState { selected: &model.selected, meta_items }
    }
}

impl<'a> UpcomingShow<'a> {
    fn new(show: &'a MetaItem, since: DateTime<Utc>) -> Self {
        let preview = &show.preview;
        UpcomingShow {
            id: &preview.id,
            r#type: &preview.r#type,
            name: &preview.name,
            poster: preview.poster.as_ref(),
            poster_shape: &preview.poster_shape,
            background: preview.background.as_ref(),
            logo: preview.logo.as_ref(),
            videos: show
                .videos
                .iter()
                .filter(|video| video.released.is_some_and(|released| released >= since))
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use stremio_watched_bitfield::WatchedBitField;

    #[test]
    fn recent_searches_are_most_recent_first() {
        let history: SearchHistoryBucket = serde_json::from_value(serde_json::json!({
            "uid": null,
            "items": {
                "twin peaks": "2026-10-01T10:00:00Z",
                "breaking bad": "2026-10-03T10:00:00Z",
                "dune": "2026-10-02T10:00:00Z",
                "alien": "2026-10-02T10:00:00Z",
            },
        }))
        .unwrap();

        assert_eq!(recent_searches(&history), ["breaking bad", "alien", "dune", "twin peaks"]);
    }

    #[test]
    fn meta_details_state_lists_the_watched_videos() {
        let meta_item = serde_json::from_value(serde_json::json!({
            "id": "tt0944947",
            "type": "series",
            "name": "Game of Thrones",
            "videos": [
                {"id": "tt0944947:1:1", "title": "Winter Is Coming", "season": 1, "episode": 1},
                {"id": "tt0944947:1:2", "title": "The Kingsroad", "season": 1, "episode": 2},
            ],
        }))
        .unwrap();
        let request = serde_json::from_value(serde_json::json!({
            "base": "https://example.com/manifest.json",
            "path": {"resource": "meta", "type": "series", "id": "tt0944947", "extra": []},
        }))
        .unwrap();
        let model = MetaDetails {
            meta_items: vec![ResourceLoadable { request, content: Some(Loadable::Ready(meta_item)) }],
            watched: Some(WatchedBitField::construct_from_array(
                vec![true, false],
                vec!["tt0944947:1:1".to_owned(), "tt0944947:1:2".to_owned()],
            )),
            ..Default::default()
        };

        let state = serde_json::to_value(MetaDetailsState::new(&model)).unwrap();

        assert_eq!(state["watchedVideos"], serde_json::json!(["tt0944947:1:1"]));
        assert_eq!(state["metaItems"][0]["content"]["content"]["name"], "Game of Thrones");
    }

    #[test]
    fn calendar_state_keeps_each_shows_videos_from_the_day_before_now() {
        let show = serde_json::from_value(serde_json::json!({
            "id": "tt0944947",
            "type": "series",
            "name": "Game of Thrones",
            "poster": "https://images.example/poster.jpg",
            "description": "Left out of the state.",
            "videos": [
                {"id": "tt0944947:1:1", "title": "Last Month", "released": "2026-09-19T01:00:00Z", "season": 1, "episode": 1},
                {"id": "tt0944947:1:2", "title": "Yesterday Evening", "released": "2026-10-18T20:00:00Z", "season": 1, "episode": 2},
                {"id": "tt0944947:1:3", "title": "Next Week", "released": "2026-10-26T01:00:00Z", "season": 1, "episode": 3},
                {"id": "tt0944947:1:4", "title": "Undated", "season": 1, "episode": 4},
            ],
        }))
        .unwrap();
        let request: stremio_core::types::addon::ResourceRequest = serde_json::from_value(serde_json::json!({
            "base": "https://example.com/manifest.json",
            "path": {"resource": "catalog", "type": "series", "id": "calendar-videos", "extra": [["calendarVideosIds", "tt0944947"]]},
        }))
        .unwrap();
        let model = Calendar {
            meta_items: vec![
                ResourceLoadable { request: request.clone(), content: Some(Loadable::Ready(vec![show])) },
                ResourceLoadable { request, content: Some(Loadable::Loading) },
            ],
            selected: Some(CalendarSelected { month: 10, year: 2026 }),
            ..Default::default()
        };
        let now = DateTime::parse_from_rfc3339("2026-10-19T12:00:00Z").unwrap().with_timezone(&Utc);

        let state = serde_json::to_value(CalendarState::new(&model, now)).unwrap();

        assert_eq!(
            state["metaItems"][0]["content"]["content"][0],
            serde_json::json!({
                "id": "tt0944947",
                "type": "series",
                "name": "Game of Thrones",
                "poster": "https://images.example/poster.jpg",
                "posterShape": "poster",
                "background": null,
                "logo": null,
                "videos": [
                    {"id": "tt0944947:1:2", "title": "Yesterday Evening", "released": "2026-10-18T20:00:00Z", "overview": null, "thumbnail": null, "streams": [], "season": 1, "episode": 2, "trailerStreams": []},
                    {"id": "tt0944947:1:3", "title": "Next Week", "released": "2026-10-26T01:00:00Z", "overview": null, "thumbnail": null, "streams": [], "season": 1, "episode": 3, "trailerStreams": []},
                ],
            })
        );
        assert_eq!(state["metaItems"][1]["content"], serde_json::json!({"type": "Loading"}));
        assert_eq!(state["selected"], serde_json::json!({"month": 10, "year": 2026}));
    }
}
