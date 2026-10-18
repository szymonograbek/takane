//! Routes `tracing` output (ours and stremio-core's) and panics to the host logger.

use std::io;

use tracing::{Level, Metadata};
use tracing_subscriber::fmt::MakeWriter;

use crate::host::{self, SBLogLevel};

pub fn install() {
    let subscriber = tracing_subscriber::fmt()
        .with_writer(HostMakeWriter)
        .with_max_level(Level::TRACE)
        .without_time()
        .with_ansi(false)
        .with_level(false)
        .with_target(false)
        .finish();
    if tracing::subscriber::set_global_default(subscriber).is_err() {
        tracing::warn!("tracing subscriber was already installed");
    }

    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        host::log(SBLogLevel::Error, "panic", &info.to_string());
        default_hook(info);
    }));
}

struct HostMakeWriter;

/// Buffers one formatted event and hands it to the host when dropped.
struct HostWriter {
    level: SBLogLevel,
    target: String,
    buffer: Vec<u8>,
}

impl<'a> MakeWriter<'a> for HostMakeWriter {
    type Writer = HostWriter;

    fn make_writer(&'a self) -> Self::Writer {
        HostWriter {
            level: SBLogLevel::Info,
            target: String::new(),
            buffer: Vec::new(),
        }
    }

    fn make_writer_for(&'a self, meta: &Metadata<'_>) -> Self::Writer {
        let level = match *meta.level() {
            Level::ERROR => SBLogLevel::Error,
            Level::WARN => SBLogLevel::Warn,
            Level::INFO => SBLogLevel::Info,
            Level::DEBUG => SBLogLevel::Debug,
            Level::TRACE => SBLogLevel::Trace,
        };
        HostWriter {
            level,
            target: meta.target().to_owned(),
            buffer: Vec::new(),
        }
    }
}

impl io::Write for HostWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.buffer.extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Drop for HostWriter {
    fn drop(&mut self) {
        let message = String::from_utf8_lossy(&self.buffer);
        host::log(self.level, &self.target, message.trim_end());
    }
}
