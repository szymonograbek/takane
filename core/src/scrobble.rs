//! Trakt scrobbling through Stremio's API.
//!
//! Stremio scrobbles to Trakt on its servers, from the analytics events its players send. The
//! bridge sends only those events, and only for accounts linked to Trakt, in the shapes
//! stremio-core-web gives them. Core's own analytics stay off: its debug builds skip the network.

use std::sync::atomic::{AtomicU64, Ordering};

use chrono::{DateTime, Utc};
use serde::Serialize;
use stremio_core::models::player::AnalyticsContext;
use stremio_core::runtime::msg::Event;
use stremio_core::runtime::{Env, EnvError};
use stremio_core::types::api::{fetch_api, APIRequest, APIResult, SuccessResponse};
use stremio_core::types::profile::AuthKey;

use crate::env::AppleEnv;
use crate::sources;

/// Numbers the events this process sends, as `eventNumber`.
static NEXT_EVENT_NUMBER: AtomicU64 = AtomicU64::new(0);

/// A player event Stremio's API scrobbles to Trakt. It serializes as the event's data.
#[derive(Serialize, PartialEq, Debug)]
#[serde(untagged)]
pub enum Scrobble {
    #[serde(rename_all = "camelCase")]
    PlayerPlaying { load_time: i64, player: AnalyticsContext },
    PlayerStopped { player: AnalyticsContext },
    #[serde(rename_all = "camelCase")]
    PlayerEnded {
        player: AnalyticsContext,
        is_binge_enabled: bool,
        is_playing_next_video: bool,
    },
    TraktPlaying { player: AnalyticsContext },
    TraktPaused { player: AnalyticsContext },
}

/// One entry of an `events` request.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ApiEvent {
    #[serde(flatten)]
    scrobble: Scrobble,
    event_name: &'static str,
    event_time: i64,
    event_number: u64,
    app: AppContext,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppContext {
    app_type: &'static str,
    app_version: &'static str,
}

impl Scrobble {
    /// The scrobble `event` asks for, or `None` for any other event, for accounts without Trakt and
    /// for titles found only on the user's own sources, which Trakt cannot know.
    pub fn from_event(event: &Event) -> Option<Self> {
        let scrobble = match event {
            Event::PlayerPlaying { context, load_time } => Scrobble::PlayerPlaying {
                load_time: *load_time,
                player: context.clone(),
            },
            Event::PlayerStopped { context } => Scrobble::PlayerStopped { player: context.clone() },
            Event::PlayerEnded { context, is_binge_enabled, is_playing_next_video } => {
                Scrobble::PlayerEnded {
                    player: context.clone(),
                    is_binge_enabled: *is_binge_enabled,
                    is_playing_next_video: *is_playing_next_video,
                }
            }
            Event::TraktPlaying { context } => Scrobble::TraktPlaying { player: context.clone() },
            Event::TraktPaused { context } => Scrobble::TraktPaused { player: context.clone() },
            _ => return None,
        };
        let player = scrobble.player();
        let local = player.id.as_deref().is_some_and(sources::is_local);
        (player.has_trakt && !local).then_some(scrobble)
    }

    fn player(&self) -> &AnalyticsContext {
        match self {
            Scrobble::PlayerPlaying { player, .. }
            | Scrobble::PlayerStopped { player }
            | Scrobble::PlayerEnded { player, .. }
            | Scrobble::TraktPlaying { player }
            | Scrobble::TraktPaused { player } => player,
        }
    }

    fn name(&self) -> &'static str {
        match self {
            Scrobble::PlayerPlaying { .. } => "playerPlaying",
            Scrobble::PlayerStopped { .. } => "playerStopped",
            Scrobble::PlayerEnded { .. } => "playerEnded",
            Scrobble::TraktPlaying { .. } => "traktPlaying",
            Scrobble::TraktPaused { .. } => "traktPaused",
        }
    }

    /// The `events` request that reports this scrobble as event number `number`, sent at `time`.
    fn request(
        self,
        auth_key: AuthKey,
        time: DateTime<Utc>,
        number: u64,
    ) -> serde_json::Result<APIRequest> {
        let event = ApiEvent {
            event_name: self.name(),
            scrobble: self,
            event_time: time.timestamp_millis(),
            event_number: number,
            app: AppContext {
                app_type: "takane",
                app_version: env!("CARGO_PKG_VERSION"),
            },
        };
        Ok(APIRequest::Events {
            auth_key,
            events: vec![serde_json::to_value(event)?],
        })
    }

    /// Sends this scrobble to Stremio's API in the background. Best effort: a failure is logged.
    pub fn send(self, auth_key: AuthKey) {
        let name = self.name();
        let number = NEXT_EVENT_NUMBER.fetch_add(1, Ordering::Relaxed);
        let request = match self.request(auth_key, AppleEnv::now(), number) {
            Ok(request) => request,
            Err(error) => {
                tracing::warn!(event = name, %error, "scrobble failed to serialize");
                return;
            }
        };
        AppleEnv::exec_concurrent(async move {
            let result: Result<APIResult<SuccessResponse>, EnvError> =
                fetch_api::<AppleEnv, _, _, _>(&request).await;
            match result {
                Ok(APIResult::Ok(_)) => tracing::debug!(event = name, "scrobble sent"),
                Ok(APIResult::Err(error)) => {
                    tracing::warn!(event = name, error = %error.message, "scrobble rejected")
                }
                Err(error) => {
                    tracing::warn!(event = name, error = %error.message(), "scrobble failed")
                }
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn player(has_trakt: bool) -> AnalyticsContext {
        AnalyticsContext {
            id: Some("tt0944947".to_owned()),
            r#type: Some("series".to_owned()),
            name: Some("Game of Thrones".to_owned()),
            video_id: Some("tt0944947:1:1".to_owned()),
            time: Some(60_000),
            duration: Some(3_600_000),
            has_trakt,
            ..Default::default()
        }
    }

    fn event_json(event: Event) -> Option<serde_json::Value> {
        let time = DateTime::from_timestamp_millis(1_700_000_000_000)?;
        let request = Scrobble::from_event(&event)?
            .request(AuthKey("key".to_owned()), time, 7)
            .ok()?;
        let APIRequest::Events { auth_key, mut events } = request else {
            panic!("not an events request: {request:?}");
        };
        assert_eq!(auth_key, AuthKey("key".to_owned()));
        assert_eq!(events.len(), 1);
        events.pop()
    }

    #[test]
    fn trakt_playing_reports_the_player_context() {
        let event = event_json(Event::TraktPlaying { context: player(true) }).expect("a scrobble");
        assert_eq!(event["eventName"], "traktPlaying");
        assert_eq!(event["eventTime"], 1_700_000_000_000_i64);
        assert_eq!(event["eventNumber"], 7);
        assert_eq!(event["app"], json!({"appType": "takane", "appVersion": env!("CARGO_PKG_VERSION")}));
        assert_eq!(event["player"]["libItemID"], "tt0944947");
        assert_eq!(event["player"]["libItemVideoID"], "tt0944947:1:1");
        assert_eq!(event["player"]["libItemTimeOffset"], 60_000);
        assert_eq!(event["player"]["hasTrakt"], true);
    }

    #[test]
    fn accounts_without_trakt_send_nothing() {
        let events = [
            Event::PlayerPlaying { context: player(false), load_time: 1200 },
            Event::PlayerStopped { context: player(false) },
            Event::PlayerEnded {
                context: player(false),
                is_binge_enabled: true,
                is_playing_next_video: false,
            },
            Event::TraktPlaying { context: player(false) },
            Event::TraktPaused { context: player(false) },
        ];
        for event in events {
            assert_eq!(Scrobble::from_event(&event), None, "{event:?}");
        }
    }

    #[test]
    fn player_events_carry_their_data_as_stremio_web_sends_it() {
        let playing = event_json(Event::PlayerPlaying { context: player(true), load_time: 1200 })
            .expect("a scrobble");
        assert_eq!(playing["eventName"], "playerPlaying");
        assert_eq!(playing["loadTime"], 1200);

        let ended = event_json(Event::PlayerEnded {
            context: player(true),
            is_binge_enabled: true,
            is_playing_next_video: false,
        })
        .expect("a scrobble");
        assert_eq!(ended["eventName"], "playerEnded");
        assert_eq!(ended["isBingeEnabled"], true);
        assert_eq!(ended["isPlayingNextVideo"], false);
        assert_eq!(ended["player"]["libItemID"], "tt0944947");

        let stopped = event_json(Event::PlayerStopped { context: player(true) }).expect("a scrobble");
        assert_eq!(stopped["eventName"], "playerStopped");
        let paused = event_json(Event::TraktPaused { context: player(true) }).expect("a scrobble");
        assert_eq!(paused["eventName"], "traktPaused");
    }

    #[test]
    fn titles_found_only_on_the_users_sources_send_nothing() {
        let local = AnalyticsContext {
            id: Some("takane-ab12cd34-0ae5".to_owned()),
            r#type: Some("movie".to_owned()),
            video_id: Some("takane-ab12cd34-0ae5".to_owned()),
            ..player(true)
        };
        let events = [
            Event::PlayerPlaying { context: local.clone(), load_time: 1200 },
            Event::PlayerStopped { context: local.clone() },
            Event::PlayerEnded { context: local.clone(), is_binge_enabled: true, is_playing_next_video: false },
            Event::TraktPlaying { context: local.clone() },
            Event::TraktPaused { context: local },
        ];
        for event in events {
            assert_eq!(Scrobble::from_event(&event), None, "{event:?}");
        }
    }

    #[test]
    fn other_events_send_nothing() {
        let event = Event::PlayerNextVideo {
            context: player(true),
            is_binge_enabled: true,
            is_playing_next_video: true,
        };
        assert_eq!(Scrobble::from_event(&event), None);
    }
}
