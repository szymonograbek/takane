//! The stremio-core models this app runs, and how they are created from storage.

use std::collections::BTreeSet;
use std::sync::{Arc, Mutex, PoisonError};

use chrono::{DateTime, Duration, Utc};
use futures::try_join;
use serde::{Deserialize, Serialize};
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
use stremio_core::runtime::msg::{Action, ActionCtx, Internal, Msg};
use stremio_core::runtime::{
    Effect, Effects, Env, EnvError, Model, RuntimeAction, Update, UpdateWithCtx,
};
use stremio_core::types::addon::Descriptor;
use stremio_core::types::api::LinkAuthKey;
use stremio_core::types::events::DismissedEventsBucket;
use stremio_core::types::library::LibraryBucket;
use stremio_core::types::notifications::NotificationsBucket;
use stremio_core::types::profile::{AuthKey, Profile};
use stremio_core::types::resource::{MetaItem, MetaItemPreview, PosterShape, Video};
use stremio_core::types::search_history::SearchHistoryBucket;
use stremio_core::types::server_urls::ServerUrlsBucket;
use stremio_core::types::streams::StreamsBucket;
use stremio_core::types::watched_bitfield::WatchedBitField;
use url::Url;

use crate::env::AppleEnv;
use crate::open_movies;
use crate::sources::SourceAddons;

/// Where the add-ons switched off on this device are saved. Core never reads it, so the choice
/// stays off the account.
const DISABLED_ADDONS_STORAGE_KEY: &str = "disabled_addons";

/// Lists the core models besides `ctx` once. It defines `Models`, with a field per model, and
/// `AppModelField`, which names `ctx` and each model as the app does (`"meta_details"`).
macro_rules! models {
    ($($(#[$attribute:meta])* $field:ident: $model:ty => $variant:ident,)*) => {
        /// The core models besides `ctx`. Each sees the add-ons enabled on this device, then the
        /// user's sources.
        #[derive(Clone, Default)]
        struct Models {
            $($(#[$attribute])* $field: $model,)*
        }

        #[derive(Serialize, Deserialize, Debug, PartialEq, Eq)]
        #[serde(rename_all = "snake_case")]
        pub enum AppModelField {
            Ctx,
            $($variant,)*
        }

        impl Models {
            /// Runs `msg` through every model, or only the one `only` names.
            fn update(&mut self, msg: &Msg, ctx: &Ctx, only: Option<&AppModelField>, changes: &mut Changes) {
                $(if only.is_none_or(|field| *field == AppModelField::$variant) {
                    changes.record(
                        AppModelField::$variant,
                        UpdateWithCtx::<AppleEnv>::update(&mut self.$field, msg, ctx),
                    );
                })*
            }
        }
    };
}

// Add a line here to expose another core model to the app.
models! {
    continue_watching_preview: ContinueWatchingPreview => ContinueWatchingPreview,
    addon_details: AddonDetails => AddonDetails,
    /// Home rows: every installed catalog without a required extra.
    board: CatalogsWithExtra => Board,
    /// Catalogs that support the `search` extra, loaded with the query.
    search: CatalogsWithExtra => Search,
    /// One catalog of one add-on with its extras, such as a genre.
    discover: CatalogWithFilters<MetaItemPreview> => Discover,
    meta_details: MetaDetails => MetaDetails,
    player: Player => Player,
    /// Sign-in by code: a code to confirm on another device, then the auth key it grants.
    link: Link<LinkAuthKey> => Link,
    /// The titles in the library, one type or all, sorted and paged.
    library: LibraryWithFilters<NotRemovedFilter> => Library,
    /// The library's shows with their videos, from add-ons that list videos by id.
    calendar: Calendar => Calendar,
}

/// The core models the app runs, the add-ons switched off on this device and the user's sources.
#[derive(Clone)]
pub struct AppModel {
    ctx: Ctx,
    models: Models,
    disabled_addons: DisabledAddons,
    /// Never saved and never in `ctx`: the app sends them again on each launch.
    source_addons: SourceAddons,
    /// Requests the next update applies.
    addon_requests: Arc<Mutex<Vec<AddonRequest>>>,
}

/// A change to the installed add-ons core has no action for, as the app sends it: `{"<name>": <args>}`.
#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
#[allow(clippy::enum_variant_names, reason = "the variants name the requests the app sends")]
pub enum AddonRequest {
    SetAddonEnabled(SetAddonEnabled),
    SetAddonOrder(SetAddonOrder),
    SetSources(SetSources),
}

/// Switching one add-on on or off on this device.
#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct SetAddonEnabled {
    transport_url: Url,
    enabled: bool,
}

/// Every installed add-on's transport URL, in the order the account should list them. Core asks
/// add-ons in this order, so it orders streams, subtitles and catalogs.
#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct SetAddonOrder {
    transport_urls: Vec<Url>,
}

impl SetAddonOrder {
    /// Puts `addons` in this order and says whether it changed. An order that does not name each
    /// installed add-on once is refused: the list changed since the app read it.
    fn apply(&self, addons: &mut [Descriptor]) -> bool {
        let mut named = self.transport_urls.clone();
        let mut installed: Vec<Url> = addons.iter().map(|addon| addon.transport_url.clone()).collect();
        named.sort();
        installed.sort();
        named.dedup();
        if named != installed || named.len() != self.transport_urls.len() {
            tracing::warn!(named = self.transport_urls.len(), installed = addons.len(), "add-on order refused");
            return false;
        }
        let before: Vec<Url> = addons.iter().map(|addon| addon.transport_url.clone()).collect();
        addons.sort_by_key(|addon| self.transport_urls.iter().position(|url| *url == addon.transport_url));
        addons.iter().map(|addon| &addon.transport_url).ne(before.iter())
    }
}

/// The add-ons of every source the user configured, replacing the ones sent before. A descriptor
/// that is not a source add-on fails the whole request when it is parsed.
#[derive(Deserialize, Debug)]
pub struct SetSources {
    descriptors: SourceAddons,
}

/// Transport URLs of the add-ons switched off on this device. Core never sees them: `ctx` keeps
/// every installed add-on, so syncing, installing and removing work as before, and only the other
/// models run without these.
#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(transparent)]
struct DisabledAddons(BTreeSet<Url>);

impl DisabledAddons {
    /// Whether the set changed.
    fn apply(&mut self, request: SetAddonEnabled) -> bool {
        if request.enabled {
            self.0.remove(&request.transport_url)
        } else {
            self.0.insert(request.transport_url)
        }
    }

    /// Saves in the background, in order with core's own storage writes.
    fn save(&self) {
        let write = AppleEnv::set_storage(DISABLED_ADDONS_STORAGE_KEY, Some(self));
        AppleEnv::exec_sequential(async move {
            if let Err(error) = write.await {
                tracing::error!(error = %error.message(), "saving the disabled add-ons failed");
            }
        });
    }
}

/// What an update changed: the effects to run and the fields to report.
#[derive(Default)]
struct Changes {
    effects: Vec<Effect>,
    fields: Vec<AppModelField>,
}

impl Changes {
    fn record(&mut self, field: AppModelField, effects: Effects) {
        if effects.has_changed && !self.fields.contains(&field) {
            self.fields.push(field);
        }
        self.effects.extend(effects);
    }
}

impl Model<AppleEnv> for AppModel {
    type Field = AppModelField;

    fn update(&mut self, msg: &Msg) -> (Vec<Effect>, Vec<AppModelField>) {
        let mut changes = self.apply_addon_requests();
        changes.record(AppModelField::Ctx, Update::<AppleEnv>::update(&mut self.ctx, msg));
        // Core resets the profile on sign-out and saves it on the `ProfileChanged` that follows.
        if matches!(msg, Msg::Internal(Internal::Logout(_))) && self.ctx.profile.auth.is_none() {
            self.ctx.profile = open_movies::anonymous_profile();
        }
        self.update_models(msg, None, &mut changes);
        (changes.effects, changes.fields)
    }

    fn update_field(&mut self, msg: &Msg, field: &AppModelField) -> (Vec<Effect>, Vec<AppModelField>) {
        let mut changes = self.apply_addon_requests();
        match field {
            AppModelField::Ctx => {
                changes.record(AppModelField::Ctx, Update::<AppleEnv>::update(&mut self.ctx, msg))
            }
            model => self.update_models(msg, Some(model), &mut changes),
        }
        (changes.effects, changes.fields)
    }
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
            disabled_addons,
        ) = try_join!(
            AppleEnv::get_storage::<Profile>(PROFILE_STORAGE_KEY),
            AppleEnv::get_storage::<LibraryBucket>(LIBRARY_RECENT_STORAGE_KEY),
            AppleEnv::get_storage::<LibraryBucket>(LIBRARY_STORAGE_KEY),
            AppleEnv::get_storage::<StreamsBucket>(STREAMS_STORAGE_KEY),
            AppleEnv::get_storage::<ServerUrlsBucket>(STREAMING_SERVER_URLS_STORAGE_KEY),
            AppleEnv::get_storage::<NotificationsBucket>(NOTIFICATIONS_STORAGE_KEY),
            AppleEnv::get_storage::<SearchHistoryBucket>(SEARCH_HISTORY_STORAGE_KEY),
            AppleEnv::get_storage::<DismissedEventsBucket>(DISMISSED_EVENTS_STORAGE_KEY),
            AppleEnv::get_storage::<DisabledAddons>(DISABLED_ADDONS_STORAGE_KEY),
        )?;

        let profile = profile.unwrap_or_else(open_movies::anonymous_profile);
        let disabled_addons = disabled_addons.unwrap_or_default();
        let uid = profile.uid();
        tracing::info!(
            authenticated = profile.auth.is_some(),
            addons = profile.addons.len(),
            disabled_addons = disabled_addons.0.len(),
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
            models: Models { continue_watching_preview, ..Default::default() },
            disabled_addons,
            source_addons: SourceAddons::default(),
            addon_requests: Default::default(),
        };
        Ok((model, continue_watching_effects))
    }

    /// Queues `request` and returns the action that applies it.
    ///
    /// Core's runtime dispatches only core actions and keeps its model lock private, so the
    /// request waits in `addon_requests` and every update applies the waiting ones first. The
    /// returned action, `Unload` aimed at `ctx`, which ctx ignores, makes that update happen now.
    pub fn queue(&self, request: AddonRequest) -> RuntimeAction<AppleEnv, AppModel> {
        self.addon_requests
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .push(request);
        RuntimeAction { field: Some(AppModelField::Ctx), action: Action::Unload }
    }

    /// Applies the waiting requests. A switch is saved, a new order is also synced to the account
    /// as core syncs an install, and the models select again with the add-ons now enabled, in
    /// order and with the new sources, as they do when the profile's add-ons change.
    fn apply_addon_requests(&mut self) -> Changes {
        let requests = std::mem::take(
            &mut *self.addon_requests.lock().unwrap_or_else(PoisonError::into_inner),
        );
        let mut changes = Changes::default();
        let mut switched = false;
        let mut reordered = false;
        let mut sources_changed = false;
        for request in requests {
            match request {
                AddonRequest::SetAddonEnabled(request) => switched |= self.disabled_addons.apply(request),
                AddonRequest::SetAddonOrder(request) if self.ctx.profile.addons_locked => {
                    tracing::warn!(?request, "add-on order refused: the account's add-ons are locked");
                }
                AddonRequest::SetAddonOrder(request) => reordered |= request.apply(&mut self.ctx.profile.addons),
                AddonRequest::SetSources(SetSources { descriptors }) => {
                    sources_changed |= descriptors != self.source_addons;
                    self.source_addons = descriptors;
                }
            }
        }
        if switched {
            self.disabled_addons.save();
        }
        if reordered {
            let mut sync = vec![Msg::Internal(Internal::ProfileChanged)];
            if self.ctx.profile.auth_key().is_some() {
                sync.push(Msg::Action(Action::Ctx(ActionCtx::PushAddonsToAPI)));
            }
            for msg in sync {
                changes.record(AppModelField::Ctx, Update::<AppleEnv>::update(&mut self.ctx, &msg));
            }
        }
        if switched || reordered || sources_changed {
            changes.fields.push(AppModelField::Ctx);
        }
        if switched || reordered || sources_changed {
            self.update_models(&Msg::Internal(Internal::ProfileChanged), None, &mut changes);
        }
        changes
    }

    /// Runs `msg` through the models, all or the one `only` names, while `ctx` holds the add-ons
    /// enabled on this device, then the user's sources. The installed list is back before anything
    /// else reads `ctx`, so `ctx` never saves or syncs a source.
    fn update_models(&mut self, msg: &Msg, only: Option<&AppModelField>, changes: &mut Changes) {
        let enabled = self
            .ctx
            .profile
            .addons
            .iter()
            .filter(|addon| !self.disabled_addons.0.contains(&addon.transport_url))
            .chain(self.source_addons.iter())
            .cloned()
            .collect();
        let installed = std::mem::replace(&mut self.ctx.profile.addons, enabled);
        self.models.update(msg, &self.ctx, only, changes);
        self.ctx.profile.addons = installed;
    }

    /// The signed-in account's API key, if any.
    pub fn auth_key(&self) -> Option<&AuthKey> {
        self.ctx.profile.auth_key()
    }

    pub fn state_json(&self, field: &AppModelField) -> serde_json::Result<Vec<u8>> {
        let models = &self.models;
        match field {
            AppModelField::Ctx => serde_json::to_vec(&CtxState::new(&self.ctx, &self.disabled_addons, &self.source_addons)),
            AppModelField::ContinueWatchingPreview => serde_json::to_vec(&models.continue_watching_preview),
            AppModelField::AddonDetails => serde_json::to_vec(&models.addon_details),
            AppModelField::Board => serde_json::to_vec(&models.board),
            AppModelField::Search => serde_json::to_vec(&models.search),
            AppModelField::Discover => serde_json::to_vec(&models.discover),
            AppModelField::MetaDetails => serde_json::to_vec(&MetaDetailsState::new(&models.meta_details)),
            AppModelField::Player => serde_json::to_vec(&PlayerState::new(&models.player)),
            AppModelField::Link => serde_json::to_vec(&models.link),
            AppModelField::Library => serde_json::to_vec(&models.library),
            AppModelField::Calendar => serde_json::to_vec(&CalendarState::new(&models.calendar, AppleEnv::now())),
        }
    }
}

/// Core's `Ctx` plus the queries searched, which core keeps out of its serialized state, and what
/// core does not know about: the add-ons switched off on this device and the user's sources, which
/// the other models list after the enabled add-ons.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CtxState<'a> {
    #[serde(flatten)]
    ctx: &'a Ctx,
    search_history: Vec<&'a str>,
    disabled_addons: &'a DisabledAddons,
    source_addons: &'a SourceAddons,
}

impl<'a> CtxState<'a> {
    fn new(ctx: &'a Ctx, disabled_addons: &'a DisabledAddons, source_addons: &'a SourceAddons) -> Self {
        CtxState { ctx, search_history: recent_searches(&ctx.search_history), disabled_addons, source_addons }
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
        let meta_item = model.meta_items.iter().find_map(|meta_item| ready(&meta_item.content));
        MetaDetailsState { model, watched_videos: watched_videos(meta_item, model.watched.as_ref()) }
    }
}

/// Core's `Player` plus the ids of the playing title's videos the user has watched, which core
/// keeps out of its serialized state.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PlayerState<'a> {
    #[serde(flatten)]
    model: &'a Player,
    watched_videos: Vec<&'a str>,
}

impl<'a> PlayerState<'a> {
    fn new(model: &'a Player) -> Self {
        let meta_item = model.meta_item.as_ref().and_then(|meta_item| ready(&meta_item.content));
        PlayerState { model, watched_videos: watched_videos(meta_item, model.watched.as_ref()) }
    }
}

fn ready<T, E>(content: &Option<Loadable<T, E>>) -> Option<&T> {
    match content {
        Some(Loadable::Ready(content)) => Some(content),
        _ => None,
    }
}

/// The ids of `meta_item`'s videos that `watched` marks.
fn watched_videos<'a>(meta_item: Option<&'a MetaItem>, watched: Option<&WatchedBitField>) -> Vec<&'a str> {
    match (meta_item, watched) {
        (Some(meta_item), Some(watched)) => meta_item
            .videos
            .iter()
            .filter(|video| watched.get_video(&video.id))
            .map(|video| video.id.as_str())
            .collect(),
        _ => vec![],
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
    use crate::host::recording;
    use crate::{executor, storage};
    use stremio_core::runtime::Runtime;
    use stremio_core::types::api::APIRequest;

    const ONE: &str = "https://one.example/manifest.json";
    const TWO: &str = "https://two.example/manifest.json";

    fn addon(transport_url: &str) -> Descriptor {
        serde_json::from_value(serde_json::json!({
            "transportUrl": transport_url,
            "manifest": {
                "id": transport_url,
                "version": "1.0.0",
                "name": "Example",
                "types": ["movie"],
                "resources": ["catalog"],
                "catalogs": [{"type": "movie", "id": "top"}],
            },
        }))
        .unwrap()
    }

    fn model_with(addons: Vec<Descriptor>) -> AppModel {
        AppModel {
            ctx: Ctx::new(
                Profile { addons, ..Default::default() },
                LibraryBucket::default(),
                StreamsBucket::default(),
                ServerUrlsBucket::new::<AppleEnv>(None),
                NotificationsBucket::new::<AppleEnv>(None, vec![]),
                SearchHistoryBucket::default(),
                DismissedEventsBucket::default(),
            ),
            models: Models::default(),
            disabled_addons: DisabledAddons::default(),
            source_addons: SourceAddons::default(),
            addon_requests: Default::default(),
        }
    }

    fn set_enabled(model: &AppModel, transport_url: &str, enabled: bool) -> RuntimeAction<AppleEnv, AppModel> {
        model.queue(AddonRequest::SetAddonEnabled(SetAddonEnabled { transport_url: transport_url.parse().unwrap(), enabled }))
    }

    fn set_order(model: &AppModel, transport_urls: &[&str]) -> RuntimeAction<AppleEnv, AppModel> {
        let transport_urls = transport_urls.iter().map(|url| url.parse().unwrap()).collect();
        model.queue(AddonRequest::SetAddonOrder(SetAddonOrder { transport_urls }))
    }

    /// The add-ons the board lists catalogs of, which are the ones core asks for them.
    fn board_addons(model: &AppModel) -> Vec<String> {
        let mut addons: Vec<String> = model
            .models
            .board
            .catalogs
            .iter()
            .filter_map(|catalog| catalog.first())
            .map(|page| page.request.base.to_string())
            .collect();
        addons.dedup();
        addons
    }

    fn ctx_state(model: &AppModel) -> serde_json::Value {
        serde_json::from_slice(&model.state_json(&AppModelField::Ctx).unwrap()).unwrap()
    }

    fn installed_addons(ctx: &serde_json::Value) -> Vec<&str> {
        ctx["profile"]["addons"]
            .as_array()
            .unwrap()
            .iter()
            .map(|addon| addon["transportUrl"].as_str().unwrap())
            .collect()
    }

    /// What the next launch reads under `key`, once the writes queued before it have finished.
    fn saved(key: &str) -> serde_json::Value {
        let (sender, receiver) = std::sync::mpsc::channel();
        executor::spawn_sequential(async move { sender.send(()).unwrap() });
        receiver.recv().unwrap();
        futures::executor::block_on(AppleEnv::get_storage(key)).unwrap().unwrap()
    }

    #[test]
    fn a_disabled_addon_gets_no_board_requests_until_enabled_again() {
        storage::install_temporary();
        let model = model_with(vec![addon(ONE), addon(TWO)]);
        let (runtime, _events) = Runtime::<AppleEnv, AppModel>::new(model, vec![], 1000);
        let load_board = serde_json::from_value(serde_json::json!({
            "action": "Load",
            "args": {"model": "CatalogsWithExtra", "args": {"type": null, "extra": []}},
        }))
        .unwrap();
        runtime.dispatch(RuntimeAction { field: Some(AppModelField::Board), action: load_board });
        assert_eq!(board_addons(&runtime.model().unwrap()), [ONE, TWO]);

        let disable = set_enabled(&runtime.model().unwrap(), ONE, false);
        runtime.dispatch(disable);
        assert_eq!(board_addons(&runtime.model().unwrap()), [TWO]);
        let ctx = ctx_state(&runtime.model().unwrap());
        assert_eq!(installed_addons(&ctx), [ONE, TWO]);
        assert_eq!(ctx["disabledAddons"], serde_json::json!([ONE]));
        assert_eq!(saved(DISABLED_ADDONS_STORAGE_KEY), serde_json::json!([ONE]));

        let enable = set_enabled(&runtime.model().unwrap(), ONE, true);
        runtime.dispatch(enable);
        assert_eq!(board_addons(&runtime.model().unwrap()), [ONE, TWO]);
        assert_eq!(ctx_state(&runtime.model().unwrap())["disabledAddons"], serde_json::json!([]));
        assert_eq!(saved(DISABLED_ADDONS_STORAGE_KEY), serde_json::json!([]));
    }

    #[test]
    fn a_new_order_lists_the_addons_and_asks_them_in_it() {
        storage::install_temporary();
        let model = model_with(vec![addon(ONE), addon(TWO)]);
        let (runtime, _events) = Runtime::<AppleEnv, AppModel>::new(model, vec![], 1000);
        let load_board = serde_json::from_value(serde_json::json!({
            "action": "Load",
            "args": {"model": "CatalogsWithExtra", "args": {"type": null, "extra": []}},
        }))
        .unwrap();
        runtime.dispatch(RuntimeAction { field: Some(AppModelField::Board), action: load_board });

        let reorder = set_order(&runtime.model().unwrap(), &[TWO, ONE]);
        runtime.dispatch(reorder);

        assert_eq!(installed_addons(&ctx_state(&runtime.model().unwrap())), [TWO, ONE]);
        assert_eq!(board_addons(&runtime.model().unwrap()), [TWO, ONE]);
        assert_eq!(installed_addons(&serde_json::json!({"profile": saved(PROFILE_STORAGE_KEY)})), [TWO, ONE]);
    }

    #[test]
    fn an_order_that_does_not_name_each_addon_once_is_refused() {
        for order in [&[ONE][..], &[TWO, TWO], &[TWO, ONE, ONE], &[TWO, "https://three.example/manifest.json"]] {
            let mut model = model_with(vec![addon(ONE), addon(TWO)]);
            let RuntimeAction { field, action } = set_order(&model, order);

            let (effects, fields) = model.update_field(&Msg::Action(action), &field.unwrap());

            assert!(effects.is_empty(), "{order:?}");
            assert_eq!(fields, [], "{order:?}");
            assert_eq!(installed_addons(&serde_json::from_slice(&model.state_json(&AppModelField::Ctx).unwrap()).unwrap()), [ONE, TWO]);
        }
    }

    const SOURCE: &str = "https://ab12cd34.source.invalid/manifest.json";

    fn set_sources(model: &AppModel, transport_urls: &[&str]) -> RuntimeAction<AppleEnv, AppModel> {
        let descriptors = transport_urls.iter().map(|url| addon(url)).collect::<Vec<_>>();
        model.queue(AddonRequest::SetSources(SetSources { descriptors: descriptors.try_into().unwrap() }))
    }

    /// The one request to `endpoint` the account `auth_key` sent.
    fn api_fetch(auth_key: &str, endpoint: &str) -> recording::Fetch {
        let mut fetches: Vec<_> = recording::fetches_with("authKey", auth_key)
            .into_iter()
            .filter(|fetch| fetch.url == format!("https://api.strem.io/api/{endpoint}"))
            .collect();
        assert_eq!(fetches.len(), 1, "{endpoint}");
        fetches.remove(0)
    }

    /// Runs the model without a runtime, feeding it core's messages by hand: the effects are not
    /// run, so nothing is saved to the storage the tests share, but each request still reaches the host.
    #[test]
    fn sources_reach_the_models_but_never_the_account() {
        recording::install();
        let mut model = model_with(vec![addon(ONE)]);
        let auth_key = AuthKey("sources-account".to_owned());
        model.ctx.profile.auth = Some(
            serde_json::from_value(serde_json::json!({
                "key": auth_key,
                "user": {
                    "_id": "user",
                    "email": "a@b.c",
                    "lastModified": "2026-10-01T00:00:00Z",
                    "dateRegistered": "2026-10-01T00:00:00Z",
                    "premium_expire": null,
                    "gdpr_consent": {"tos": true, "privacy": true, "marketing": false, "from": null},
                },
            }))
            .unwrap(),
        );
        let load_board = serde_json::from_value(serde_json::json!({
            "action": "Load",
            "args": {"model": "CatalogsWithExtra", "args": {"type": null, "extra": []}},
        }))
        .unwrap();
        model.update_field(&Msg::Action(load_board), &AppModelField::Board);

        let RuntimeAction { field, action } = set_sources(&model, &[SOURCE]);
        model.update_field(&Msg::Action(action), &field.unwrap());
        assert_eq!(board_addons(&model), [ONE, SOURCE]);
        assert_eq!(installed_addons(&ctx_state(&model)), [ONE]);
        assert_eq!(ctx_state(&model)["sourceAddons"][0]["transportUrl"], SOURCE);

        model.update(&Msg::Action(Action::Ctx(ActionCtx::PushAddonsToAPI)));
        let pushed = api_fetch("sources-account", "addonCollectionSet");
        assert_eq!(installed_addons(&serde_json::json!({"profile": pushed.body})), [ONE]);

        model.update(&Msg::Action(Action::Ctx(ActionCtx::PullAddonsFromAPI)));
        api_fetch("sources-account", "addonCollectionGet");
        let pulled = APIRequest::AddonCollectionGet { auth_key, update: true };
        model.update(&Msg::Internal(Internal::AddonsAPIResult(pulled, Ok(vec![addon(TWO)]))));
        model.update(&Msg::Internal(Internal::ProfileChanged));
        assert_eq!(board_addons(&model), [TWO, SOURCE]);
        assert_eq!(installed_addons(&ctx_state(&model)), [TWO]);

        let RuntimeAction { field, action } = set_sources(&model, &[]);
        model.update_field(&Msg::Action(action), &field.unwrap());
        assert_eq!(board_addons(&model), [TWO]);
    }

    #[test]
    fn enabling_an_enabled_addon_changes_nothing() {
        let mut model = model_with(vec![addon(ONE)]);
        let RuntimeAction { field, action } = set_enabled(&model, ONE, true);

        let (effects, fields) = model.update_field(&Msg::Action(action), &field.unwrap());

        assert!(effects.is_empty());
        assert_eq!(fields, []);
    }

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
    fn player_state_lists_the_watched_videos() {
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
        let model = Player {
            meta_item: Some(ResourceLoadable { request, content: Some(Loadable::Ready(meta_item)) }),
            watched: Some(WatchedBitField::construct_from_array(
                vec![false, true],
                vec!["tt0944947:1:1".to_owned(), "tt0944947:1:2".to_owned()],
            )),
            ..Default::default()
        };

        let state = serde_json::to_value(PlayerState::new(&model)).unwrap();

        assert_eq!(state["watchedVideos"], serde_json::json!(["tt0944947:1:2"]));
        assert_eq!(state["metaItem"]["content"]["content"]["videos"][1]["title"], "The Kingsroad");
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
