//! `AppleEnv`: stremio-core's view of the platform.

use std::collections::BTreeMap;
use std::future::Future;

use chrono::{DateTime, Utc};
use futures::{future, FutureExt};
use http::{Method, Request};
use serde::{Deserialize, Serialize};
use stremio_core::models::ctx::Ctx;
use stremio_core::models::streaming_server::StreamingServer;
use stremio_core::runtime::{
    ConditionalSend, Env, EnvError, EnvFuture, EnvFutureExt, TryEnvFuture,
};

use crate::{executor, fetch, storage};
use crate::fetch::{FetchOutcome, FetchRequest};

pub enum AppleEnv {}

impl Env for AppleEnv {
    fn fetch<IN, OUT>(request: Request<IN>) -> TryEnvFuture<OUT>
    where
        IN: Serialize + ConditionalSend + 'static,
        for<'de> OUT: Deserialize<'de> + ConditionalSend + 'static,
    {
        let (parts, body) = request.into_parts();
        let body = match serde_json::to_string(&body) {
            Ok(body) if body != "null" && parts.method != Method::GET => Some(body),
            Ok(_) => None,
            Err(error) => return future::err(EnvError::from(error)).boxed_env(),
        };
        let headers = parts
            .headers
            .iter()
            .map(|(name, value)| {
                (
                    name.as_str().to_owned(),
                    String::from_utf8_lossy(value.as_bytes()).into_owned(),
                )
            })
            .collect::<BTreeMap<_, _>>();
        let request = FetchRequest {
            method: parts.method.as_str().to_owned(),
            url: parts.uri.to_string(),
            headers,
            body,
        };
        let receiver = fetch::send(&request);
        async move {
            let outcome = receiver
                .await
                .map_err(|_| EnvError::Fetch("host dropped the request".to_owned()))?;
            match outcome {
                FetchOutcome::TransportError(message) => {
                    tracing::warn!(url = %request.url, %message, "fetch failed");
                    Err(EnvError::Fetch(message))
                }
                FetchOutcome::Response { status, .. } if !(200..300).contains(&status) => {
                    tracing::warn!(url = %request.url, status, "fetch got unexpected status");
                    Err(EnvError::Fetch(format!("Unexpected HTTP status code {status}")))
                }
                FetchOutcome::Response { status, body } => {
                    tracing::debug!(url = %request.url, status, bytes = body.len(), "fetch done");
                    let mut deserializer = serde_json::Deserializer::from_slice(&body);
                    serde_path_to_error::deserialize(&mut deserializer).map_err(|error| {
                        tracing::warn!(url = %request.url, %error, "fetch response did not match the expected shape");
                        EnvError::Fetch(error.to_string())
                    })
                }
            }
        }
        .boxed_env()
    }

    fn get_storage<T>(key: &str) -> TryEnvFuture<Option<T>>
    where
        for<'de> T: Deserialize<'de> + ConditionalSend + 'static,
    {
        let key = key.to_owned();
        blocking(move || {
            let value = storage::read(&key)?;
            tracing::debug!(key, found = value.is_some(), "storage read");
            value
                .map(|value| serde_json::from_str(&value))
                .transpose()
                .map_err(EnvError::from)
        })
    }

    fn set_storage<T: Serialize>(key: &str, value: Option<&T>) -> TryEnvFuture<()> {
        let key = key.to_owned();
        let value = match value.map(serde_json::to_string).transpose() {
            Ok(value) => value,
            Err(error) => return future::err(EnvError::from(error)).boxed_env(),
        };
        blocking(move || {
            tracing::debug!(key, bytes = value.as_ref().map(String::len), "storage write");
            storage::write(&key, value.as_deref())
        })
    }

    fn exec_concurrent<F: Future<Output = ()> + ConditionalSend + 'static>(future: F) {
        executor::spawn_concurrent(future);
    }

    fn exec_sequential<F: Future<Output = ()> + ConditionalSend + 'static>(future: F) {
        executor::spawn_sequential(future);
    }

    fn now() -> DateTime<Utc> {
        Utc::now()
    }

    fn flush_analytics() -> EnvFuture<'static, ()> {
        future::ready(()).boxed_env()
    }

    fn analytics_context(
        _ctx: &Ctx,
        _streaming_server: &StreamingServer,
        _path: &str,
    ) -> serde_json::Value {
        serde_json::Value::Null
    }

    #[cfg(debug_assertions)]
    fn log(message: String) {
        tracing::debug!(target: "stremio_core", "{message}");
    }
}

fn blocking<T, F>(work: F) -> TryEnvFuture<T>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, EnvError> + Send + 'static,
{
    executor::runtime()
        .spawn_blocking(work)
        .map(|joined| joined.unwrap_or_else(|error| Err(EnvError::Other(error.to_string()))))
        .boxed_env()
}
