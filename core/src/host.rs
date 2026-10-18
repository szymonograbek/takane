//! The C ABI types the Swift host implements, and the one place Rust calls back into it.

use std::ffi::c_void;
use std::sync::OnceLock;

/// Borrowed bytes. Valid only for the duration of the call that receives them.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SBBytes {
    pub ptr: *const u8,
    pub len: usize,
}

impl SBBytes {
    pub fn from_slice(slice: &[u8]) -> Self {
        SBBytes {
            ptr: slice.as_ptr(),
            len: slice.len(),
        }
    }

    /// # Safety
    /// `ptr` must point to `len` readable bytes that outlive `'a`.
    pub unsafe fn as_slice<'a>(&self) -> &'a [u8] {
        if self.len == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(self.ptr, self.len)
        }
    }
}

/// Bytes allocated by Rust and handed to the host. The host releases them with `sb_bytes_free`.
#[repr(C)]
pub struct SBOwnedBytes {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
}

impl SBOwnedBytes {
    pub fn empty() -> Self {
        Self::from_vec(Vec::new())
    }

    pub fn from_vec(vec: Vec<u8>) -> Self {
        let mut vec = std::mem::ManuallyDrop::new(vec);
        SBOwnedBytes {
            ptr: vec.as_mut_ptr(),
            len: vec.len(),
            cap: vec.capacity(),
        }
    }

    /// # Safety
    /// Must come from `from_vec` and be released exactly once.
    pub unsafe fn into_vec(self) -> Vec<u8> {
        Vec::from_raw_parts(self.ptr, self.len, self.cap)
    }
}

#[repr(u8)]
#[derive(Clone, Copy, Debug)]
pub enum SBLogLevel {
    Error = 0,
    Warn = 1,
    Info = 2,
    Debug = 3,
    Trace = 4,
}

/// Callbacks the host registers once at initialization.
///
/// They may be called from any thread. `context` is passed back untouched.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SBHost {
    pub context: *mut c_void,
    pub log: extern "C" fn(context: *mut c_void, level: SBLogLevel, target: SBBytes, message: SBBytes),
    /// Perform an HTTP request described by a `FetchRequest` JSON document.
    /// The host must answer exactly once with `sb_fetch_resolve` or `sb_fetch_reject`.
    pub fetch: extern "C" fn(context: *mut c_void, request_id: u64, request: SBBytes),
    /// Receives each serialized `RuntimeEvent` (`NewState` or `CoreEvent`).
    pub emit: extern "C" fn(context: *mut c_void, event: SBBytes),
}

// The host guarantees its callbacks and context are thread-safe.
unsafe impl Send for SBHost {}
unsafe impl Sync for SBHost {}

static HOST: OnceLock<SBHost> = OnceLock::new();

pub fn install(host: SBHost) -> bool {
    HOST.set(host).is_ok()
}

fn host() -> Option<&'static SBHost> {
    HOST.get()
}

pub fn log(level: SBLogLevel, target: &str, message: &str) {
    if let Some(host) = host() {
        (host.log)(
            host.context,
            level,
            SBBytes::from_slice(target.as_bytes()),
            SBBytes::from_slice(message.as_bytes()),
        );
    }
}

pub fn fetch(request_id: u64, request: &[u8]) {
    let host = host().expect("host is installed before the runtime starts");
    (host.fetch)(host.context, request_id, SBBytes::from_slice(request));
}

pub fn emit(event: &[u8]) {
    let host = host().expect("host is installed before the runtime starts");
    (host.emit)(host.context, SBBytes::from_slice(event));
}
