use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, OnceLock};

use dashmap::DashMap;
use parking_lot::Mutex;
use serde_json::{json, Value};
use tracing::warn;

use crate::VedroRuntime;

// =============================================================================
// C-ABI Exports (Flutter dart:ffi, Swift, Kotlin, C++)
//
// Runtime handles live in a process-wide `Arc<VedroRuntime>` registry so a concurrent
// `vedro_destroy` NEVER frees a runtime while another isolate is mid-`vedro_invoke`!
// =============================================================================

static RUNTIME_REGISTRY: OnceLock<DashMap<usize, Arc<VedroRuntime>>> = OnceLock::new();
static NEXT_RUNTIME_ID: AtomicUsize = AtomicUsize::new(1);
static LAST_INIT_ERROR: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn registry() -> &'static DashMap<usize, Arc<VedroRuntime>> {
    RUNTIME_REGISTRY.get_or_init(DashMap::new)
}

fn last_init_error_slot() -> &'static Mutex<Option<String>> {
    LAST_INIT_ERROR.get_or_init(|| Mutex::new(None))
}

fn set_last_init_error(msg: Option<String>) {
    *last_init_error_slot().lock() = msg;
}

fn panic_payload_to_string(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown panic".to_string()
    }
}

fn lookup_runtime(rt: *mut VedroRuntime) -> Option<Arc<VedroRuntime>> {
    if rt.is_null() {
        return None;
    }
    registry()
        .get(&(rt as usize))
        .map(|e| Arc::clone(e.value()))
}

#[no_mangle]
pub extern "C" fn vedro_init(db_path_utf8: *const c_char) -> *mut VedroRuntime {
    set_last_init_error(None);
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let db_path = if db_path_utf8.is_null() {
            None
        } else {
            unsafe { CStr::from_ptr(db_path_utf8) }.to_str().ok()
        };
        match VedroRuntime::new(db_path) {
            Ok(rt) => {
                let id = NEXT_RUNTIME_ID.fetch_add(1, Ordering::Relaxed);
                registry().insert(id, Arc::new(rt));
                id as *mut VedroRuntime
            }
            Err(e) => {
                warn!(error = %e, "vedro_init failed");
                set_last_init_error(Some(e));
                std::ptr::null_mut()
            }
        }
    }));
    match res {
        Ok(ptr) => ptr,
        Err(payload) => {
            let msg = format!("vedro_init panic: {}", panic_payload_to_string(payload));
            warn!(error = %msg, "vedro_init panicked");
            set_last_init_error(Some(msg));
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn vedro_last_init_error() -> *mut c_char {
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let guard = last_init_error_slot().lock();
        match guard.as_deref() {
            Some(msg) if !msg.is_empty() => to_c_string(msg),
            _ => std::ptr::null_mut(),
        }
    }));
    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn vedro_invoke(
    rt: *mut VedroRuntime,
    method_utf8: *const c_char,
    params_json_utf8: *const c_char,
) -> *mut c_char {
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if rt.is_null() || method_utf8.is_null() {
            return to_c_string(
                &json!({"ok": false, "error": "null runtime or method"}).to_string(),
            );
        }
        let Some(runtime) = lookup_runtime(rt) else {
            return to_c_string(&json!({"ok": false, "error": "runtime disposed"}).to_string());
        };
        let method = match unsafe { CStr::from_ptr(method_utf8) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                return to_c_string(
                    &json!({"ok": false, "error": "invalid utf8 method"}).to_string(),
                )
            }
        };
        let params = if params_json_utf8.is_null() {
            json!({})
        } else {
            match unsafe { CStr::from_ptr(params_json_utf8) }.to_str() {
                Ok(raw) if raw.trim().is_empty() => json!({}),
                Ok(raw) => match serde_json::from_str::<Value>(raw) {
                    Ok(v) => v,
                    Err(e) => {
                        return to_c_string(
                            &json!({"ok": false, "error": format!("invalid params JSON: {e}")})
                                .to_string(),
                        );
                    }
                },
                Err(_) => {
                    return to_c_string(
                        &json!({"ok": false, "error": "invalid utf8 params"}).to_string(),
                    );
                }
            }
        };

        let envelope = match runtime.invoke(method, params) {
            Ok(data) => json!({"ok": true, "data": data}),
            Err(err) => json!({"ok": false, "error": err}),
        };
        to_c_string(&envelope.to_string())
    }));
    res.unwrap_or_else(|_| to_c_string(r#"{"ok":false,"error":"internal core panic recovered"}"#))
}

#[no_mangle]
pub extern "C" fn vedro_poll_events(rt: *mut VedroRuntime) -> *mut c_char {
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let Some(runtime) = lookup_runtime(rt) else {
            return to_c_string("[]");
        };
        let events = runtime.poll_events();
        to_c_string(&serde_json::to_string(&events).unwrap_or_else(|_| "[]".to_string()))
    }));
    res.unwrap_or_else(|_| to_c_string("[]"))
}

#[no_mangle]
pub extern "C" fn vedro_proxy_speed_bps(rt: *mut VedroRuntime) -> u64 {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        lookup_runtime(rt).map(|r| r.proxy_speed_bps()).unwrap_or(0)
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn vedro_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn vedro_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
            let _ = CString::from_raw(ptr);
        }));
    }
}

#[no_mangle]
pub extern "C" fn vedro_destroy(rt: *mut VedroRuntime) {
    if !rt.is_null() {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = registry().remove(&(rt as usize));
        }));
    }
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"ok":false,"error":"nul byte in response"}"#).unwrap())
        .into_raw()
}
