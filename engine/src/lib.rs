//! `netbar_engine` — the menu policy behind NetBar, exposed to the app through
//! one C entry point.
//!
//! The Swift app captures the radio with CoreWLAN, serializes the capture as
//! `NBEngineInput` JSON, and gets the finished row list back as
//! `NBEngineOutput` JSON. Keeping the policy here means it can be tested against
//! fixtures on any machine, without a radio.
//!
//! The ABI is declared once in `Contracts/NBEngineExports.h`.

#![forbid(unsafe_op_in_unsafe_fn)]

pub mod json;
pub mod menu;
pub mod model;

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Version reported by `netbar_engine_version`.
const VERSION: &str = concat!("netbar_engine/", env!("CARGO_PKG_VERSION"));

/// Menu returned when the request cannot be decoded at all: empty, no status,
/// so the app shows only its header and footer.
const EMPTY_OUTPUT: &str = "{\"schemaVersion\":1,\"statusTitle\":null,\"statusNeedsSetup\":false,\
\"items\":[],\"hiddenOtherCount\":0,\"connectedName\":null,\"connectedIsHotspot\":false,\
\"connectedCell\":0,\"connectedBattery\":0,\"connectedStrength\":0}";

/// The last reply, kept alive until the next call or `netbar_string_free`.
///
/// The app frees every reply, so the simplest correct ownership rule is: the
/// engine hands out a buffer it owns, and `netbar_string_free` may ignore it.
/// Returning a fresh `CString` per call is cheaper to reason about and the
/// buffers are a few kilobytes.
///
/// # Safety
/// `input_json` must be NUL-terminated UTF-8 or NULL.
#[no_mangle]
pub unsafe extern "C" fn netbar_node_json(input_json: *const c_char) -> *mut c_char {
    let reply = catch_unwind(AssertUnwindSafe(|| {
        if input_json.is_null() {
            return EMPTY_OUTPUT.to_owned();
        }
        // SAFETY: the caller guarantees a NUL-terminated string.
        let text = unsafe { CStr::from_ptr(input_json) };
        match text.to_str() {
            Ok(text) => render(text),
            Err(_) => EMPTY_OUTPUT.to_owned(),
        }
    }))
    .unwrap_or_else(|_| EMPTY_OUTPUT.to_owned());

    match CString::new(reply) {
        Ok(text) => text.into_raw(),
        Err(_) => CString::new(EMPTY_OUTPUT)
            .expect("the empty output contains no NUL")
            .into_raw(),
    }
}

/// The engine version, as a static string the caller must not free.
#[no_mangle]
pub extern "C" fn netbar_engine_version() -> *const c_char {
    // A `'static` string with no interior NUL, so this cannot fail.
    static VERSION_C: &str = concat!("netbar_engine/", env!("CARGO_PKG_VERSION"), "\0");
    debug_assert!(VERSION.ends_with(env!("CARGO_PKG_VERSION")));
    VERSION_C.as_ptr().cast()
}

/// Releases a buffer from `netbar_node_json`.
///
/// # Safety
/// `buffer` must be NULL or a pointer returned by `netbar_node_json` that has
/// not been freed yet.
#[no_mangle]
pub unsafe extern "C" fn netbar_string_free(buffer: *mut c_char) {
    if buffer.is_null() {
        return;
    }
    // SAFETY: the pointer came from `CString::into_raw`.
    drop(unsafe { CString::from_raw(buffer) });
}

/// Decodes one request and renders its menu.
fn render(request: &str) -> String {
    match json::parse(request) {
        Ok(value) => {
            let input = model::Input::decode(&value);
            menu::build(&input).encode()
        }
        Err(_) => EMPTY_OUTPUT.to_owned(),
    }
}

#[cfg(test)]
mod tests;
