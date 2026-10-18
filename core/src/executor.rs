//! The async executor behind `Env::exec_concurrent` and `Env::exec_sequential`.

use std::future::Future;
use std::sync::OnceLock;

use futures::future::BoxFuture;
use futures::FutureExt;
use tokio::runtime::Runtime;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static SEQUENTIAL: OnceLock<UnboundedSender<BoxFuture<'static, ()>>> = OnceLock::new();

pub fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .thread_name("stremio-core")
            .build()
            .expect("tokio runtime builds")
    })
}

pub fn spawn_concurrent<F: Future<Output = ()> + Send + 'static>(future: F) {
    runtime().spawn(future);
}

/// Runs futures one after another, in submission order.
pub fn spawn_sequential<F: Future<Output = ()> + Send + 'static>(future: F) {
    let queue = SEQUENTIAL.get_or_init(|| {
        let (sender, mut receiver) = unbounded_channel::<BoxFuture<'static, ()>>();
        runtime().spawn(async move {
            while let Some(future) = receiver.recv().await {
                future.await;
            }
        });
        sender
    });
    queue
        .send(future.boxed())
        .expect("sequential queue lives as long as the runtime");
}
