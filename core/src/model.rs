//! The stremio-core models this app runs, and how they are created from storage.

use futures::try_join;
use stremio_core::constants::{
    DISMISSED_EVENTS_STORAGE_KEY, LIBRARY_RECENT_STORAGE_KEY, LIBRARY_STORAGE_KEY,
    NOTIFICATIONS_STORAGE_KEY, PROFILE_STORAGE_KEY, SEARCH_HISTORY_STORAGE_KEY,
    STREAMING_SERVER_URLS_STORAGE_KEY, STREAMS_STORAGE_KEY,
};
use stremio_core::models::addon_details::AddonDetails;
use stremio_core::models::catalogs_with_extra::CatalogsWithExtra;
use stremio_core::models::continue_watching_preview::ContinueWatchingPreview;
use stremio_core::models::ctx::Ctx;
use stremio_core::models::meta_details::MetaDetails;
use stremio_core::models::player::Player;
use stremio_core::runtime::{Effects, Env, EnvError};
use stremio_core::types::events::DismissedEventsBucket;
use stremio_core::types::library::LibraryBucket;
use stremio_core::types::notifications::NotificationsBucket;
use stremio_core::types::profile::Profile;
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
    pub meta_details: MetaDetails,
    pub player: Player,
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
            meta_details: Default::default(),
            player: Default::default(),
        };
        Ok((model, continue_watching_effects))
    }

    pub fn state_json(&self, field: &AppModelField) -> serde_json::Result<Vec<u8>> {
        match field {
            AppModelField::Ctx => serde_json::to_vec(&self.ctx),
            AppModelField::ContinueWatchingPreview => serde_json::to_vec(&self.continue_watching_preview),
            AppModelField::AddonDetails => serde_json::to_vec(&self.addon_details),
            AppModelField::Board => serde_json::to_vec(&self.board),
            AppModelField::Search => serde_json::to_vec(&self.search),
            AppModelField::MetaDetails => serde_json::to_vec(&self.meta_details),
            AppModelField::Player => serde_json::to_vec(&self.player),
        }
    }
}
