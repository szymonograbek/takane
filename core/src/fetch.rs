//! HTTP requests delegated to the host, matched to their replies by request id.

use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use futures::channel::oneshot;
use serde::Serialize;

use crate::{host, open_movies};

/// The JSON document the host receives for each request.
#[derive(Serialize, Debug)]
pub struct FetchRequest {
    pub method: String,
    pub url: String,
    pub headers: BTreeMap<String, String>,
    pub body: Option<String>,
}

#[derive(Debug)]
pub enum FetchOutcome {
    Response { status: u16, body: Vec<u8> },
    TransportError(String),
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);
static PENDING: OnceLock<Mutex<HashMap<u64, oneshot::Sender<FetchOutcome>>>> = OnceLock::new();

fn pending() -> &'static Mutex<HashMap<u64, oneshot::Sender<FetchOutcome>>> {
    PENDING.get_or_init(Default::default)
}

/// Sends `request` to the host. The receiver completes when the host replies. Open Movies'
/// requests are answered here instead.
pub fn send(request: &FetchRequest) -> oneshot::Receiver<FetchOutcome> {
    let (sender, receiver) = oneshot::channel();
    if let Some(outcome) = open_movies::respond(&request.url) {
        // The receiver is still held here, so the send cannot fail.
        let _ = sender.send(outcome);
        return receiver;
    }
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    pending().lock().expect("pending fetches lock").insert(id, sender);
    let payload = serde_json::to_vec(request).expect("FetchRequest serializes");
    host::fetch(id, &payload);
    receiver
}

pub fn complete(id: u64, outcome: FetchOutcome) {
    let sender = pending().lock().expect("pending fetches lock").remove(&id);
    match sender {
        Some(sender) => {
            if sender.send(outcome).is_err() {
                tracing::debug!(id, "fetch completed after its future was dropped");
            }
        }
        None => tracing::warn!(id, "fetch completion for unknown request id"),
    }
}
