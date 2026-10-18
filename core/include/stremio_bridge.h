// C interface of the stremio-bridge Rust crate (core/src/lib.rs, core/src/host.rs).
// Keep in sync with the #[repr(C)] types and #[no_mangle] functions there.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct SBBytes {
    const uint8_t *ptr;
    size_t len;
} SBBytes;

typedef struct SBOwnedBytes {
    uint8_t *ptr;
    size_t len;
    size_t cap;
} SBOwnedBytes;

typedef enum __attribute__((enum_extensibility(closed))) SBLogLevel : uint8_t {
    SBLogLevelError = 0,
    SBLogLevelWarn = 1,
    SBLogLevelInfo = 2,
    SBLogLevelDebug = 3,
    SBLogLevelTrace = 4,
} SBLogLevel;

typedef struct SBHost {
    void *context;
    void (*log)(void *context, SBLogLevel level, SBBytes target, SBBytes message);
    void (*fetch)(void *context, uint64_t request_id, SBBytes request);
    void (*emit)(void *context, SBBytes event);
} SBHost;

bool sb_initialize(SBHost host, SBBytes storage_directory, SBOwnedBytes *error_out);
bool sb_dispatch(SBBytes request, SBOwnedBytes *error_out);
bool sb_get_state(SBBytes field, SBOwnedBytes *state_out, SBOwnedBytes *error_out);
void sb_fetch_resolve(uint64_t request_id, uint16_t status, SBBytes body);
void sb_fetch_reject(uint64_t request_id, SBBytes message);
void sb_bytes_free(SBOwnedBytes bytes);
