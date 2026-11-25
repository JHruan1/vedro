#![allow(clippy::not_unsafe_ptr_arg_deref)]
//! Dynamic FFI loader for `libmpv` (C API v2 / v1 compatible).
//! Loading dynamically via `libloading` keeps the Rust core portable across
//! Android, iOS, macOS, Windows, and Linux while allowing direct zero-overhead
//! calls into the native `libmpv` + `libplacebo` playback engine at runtime.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_double, c_int, c_void};

use libloading::{Library, Symbol};

pub const MPV_FORMAT_STRING: c_int = 1;
pub const MPV_FORMAT_FLAG: c_int = 3;
pub const MPV_FORMAT_INT64: c_int = 4;
pub const MPV_FORMAT_DOUBLE: c_int = 5;

#[repr(C)]
pub struct MpvHandle {
    _private: [u8; 0],
}

#[repr(C)]
pub struct MpvEvent {
    pub event_id: c_int,
    pub error: c_int,
    pub reply_userdata: u64,
    pub data: *mut c_void,
}

type FnCreate = unsafe extern "C" fn() -> *mut MpvHandle;
type FnInitialize = unsafe extern "C" fn(*mut MpvHandle) -> c_int;
type FnTerminateDestroy = unsafe extern "C" fn(*mut MpvHandle);
type FnSetOptionString =
    unsafe extern "C" fn(*mut MpvHandle, *const c_char, *const c_char) -> c_int;
type FnSetPropertyString =
    unsafe extern "C" fn(*mut MpvHandle, *const c_char, *const c_char) -> c_int;
type FnGetPropertyString = unsafe extern "C" fn(*mut MpvHandle, *const c_char) -> *mut c_char;
type FnGetProperty =
    unsafe extern "C" fn(*mut MpvHandle, *const c_char, c_int, *mut c_void) -> c_int;
type FnCommand = unsafe extern "C" fn(*mut MpvHandle, *const *const c_char) -> c_int;
type FnWaitEvent = unsafe extern "C" fn(*mut MpvHandle, c_double) -> *mut MpvEvent;
type FnFree = unsafe extern "C" fn(*mut c_void);
type FnClientApiVersion = unsafe extern "C" fn() -> u64;

pub struct LibMpv {
    _lib: Library,
    create: FnCreate,
    initialize: FnInitialize,
    terminate_destroy: FnTerminateDestroy,
    set_option_string: FnSetOptionString,
    set_property_string: FnSetPropertyString,
    get_property_string: FnGetPropertyString,
    get_property: FnGetProperty,
    command: FnCommand,
    wait_event: FnWaitEvent,
    free: FnFree,
    client_api_version: FnClientApiVersion,
}

unsafe impl Send for LibMpv {}
unsafe impl Sync for LibMpv {}

impl LibMpv {
    /// Attempt to load the system/bundled `libmpv` dynamic library for the current OS.
    pub fn load() -> Result<Self, String> {
        let candidates: &[&str] = match std::env::consts::OS {
            "windows" => &["libmpv-2.dll", "mpv-2.dll", "mpv-1.dll"],
            "macos" | "ios" => &[
                "libmpv.2.dylib",
                "libmpv.dylib",
                "@rpath/Libmpv.framework/Libmpv",
            ],
            _ => &["libmpv.so.2", "libmpv.so.1", "libmpv.so"],
        };

        let mut last_err = String::new();
        for name in candidates {
            match unsafe { Library::new(name) } {
                Ok(lib) => return Self::from_library(lib),
                Err(e) => last_err = format!("{name}: {e}"),
            }
        }
        Err(format!("unable to load libmpv ({last_err})"))
    }

    fn from_library(lib: Library) -> Result<Self, String> {
        unsafe {
            let create: Symbol<FnCreate> = lib.get(b"mpv_create").map_err(|e| e.to_string())?;
            let initialize: Symbol<FnInitialize> =
                lib.get(b"mpv_initialize").map_err(|e| e.to_string())?;
            let terminate_destroy: Symbol<FnTerminateDestroy> = lib
                .get(b"mpv_terminate_destroy")
                .map_err(|e| e.to_string())?;
            let set_option_string: Symbol<FnSetOptionString> = lib
                .get(b"mpv_set_option_string")
                .map_err(|e| e.to_string())?;
            let set_property_string: Symbol<FnSetPropertyString> = lib
                .get(b"mpv_set_property_string")
                .map_err(|e| e.to_string())?;
            let get_property_string: Symbol<FnGetPropertyString> = lib
                .get(b"mpv_get_property_string")
                .map_err(|e| e.to_string())?;
            let get_property: Symbol<FnGetProperty> =
                lib.get(b"mpv_get_property").map_err(|e| e.to_string())?;
            let command: Symbol<FnCommand> = lib.get(b"mpv_command").map_err(|e| e.to_string())?;
            let wait_event: Symbol<FnWaitEvent> =
                lib.get(b"mpv_wait_event").map_err(|e| e.to_string())?;
            let free: Symbol<FnFree> = lib.get(b"mpv_free").map_err(|e| e.to_string())?;
            let client_api_version: Symbol<FnClientApiVersion> = lib
                .get(b"mpv_client_api_version")
                .map_err(|e| e.to_string())?;

            let fns = (
                *create,
                *initialize,
                *terminate_destroy,
                *set_option_string,
                *set_property_string,
                *get_property_string,
                *get_property,
                *command,
                *wait_event,
                *free,
                *client_api_version,
            );
            Ok(Self {
                _lib: lib,
                create: fns.0,
                initialize: fns.1,
                terminate_destroy: fns.2,
                set_option_string: fns.3,
                set_property_string: fns.4,
                get_property_string: fns.5,
                get_property: fns.6,
                command: fns.7,
                wait_event: fns.8,
                free: fns.9,
                client_api_version: fns.10,
            })
        }
    }

    pub fn api_version(&self) -> (u32, u32) {
        let v = unsafe { (self.client_api_version)() };
        (((v >> 16) & 0xFFFF) as u32, (v & 0xFFFF) as u32)
    }

    pub fn create_handle(&self) -> Option<*mut MpvHandle> {
        let ptr = unsafe { (self.create)() };
        if ptr.is_null() {
            None
        } else {
            Some(ptr)
        }
    }

    pub fn initialize(&self, handle: *mut MpvHandle) -> Result<(), c_int> {
        let rc = unsafe { (self.initialize)(handle) };
        if rc < 0 {
            Err(rc)
        } else {
            Ok(())
        }
    }

    pub fn terminate_destroy(&self, handle: *mut MpvHandle) {
        unsafe { (self.terminate_destroy)(handle) };
    }

    pub fn set_option_string(
        &self,
        handle: *mut MpvHandle,
        name: &str,
        value: &str,
    ) -> Result<(), c_int> {
        let k = CString::new(name).map_err(|_| -4)?;
        let v = CString::new(value).map_err(|_| -4)?;
        let rc = unsafe { (self.set_option_string)(handle, k.as_ptr(), v.as_ptr()) };
        if rc < 0 {
            Err(rc)
        } else {
            Ok(())
        }
    }

    pub fn set_property_string(
        &self,
        handle: *mut MpvHandle,
        name: &str,
        value: &str,
    ) -> Result<(), c_int> {
        let k = CString::new(name).map_err(|_| -4)?;
        let v = CString::new(value).map_err(|_| -4)?;
        let rc = unsafe { (self.set_property_string)(handle, k.as_ptr(), v.as_ptr()) };
        if rc < 0 {
            Err(rc)
        } else {
            Ok(())
        }
    }

    pub fn get_property_string(&self, handle: *mut MpvHandle, name: &str) -> Option<String> {
        let k = CString::new(name).ok()?;
        let ptr = unsafe { (self.get_property_string)(handle, k.as_ptr()) };
        if ptr.is_null() {
            return None;
        }
        let s = unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned();
        unsafe { (self.free)(ptr as *mut c_void) };
        Some(s)
    }

    pub fn get_property_f64(&self, handle: *mut MpvHandle, name: &str) -> Option<f64> {
        let k = CString::new(name).ok()?;
        let mut out: c_double = 0.0;
        let rc = unsafe {
            (self.get_property)(
                handle,
                k.as_ptr(),
                MPV_FORMAT_DOUBLE,
                &mut out as *mut c_double as *mut c_void,
            )
        };
        if rc < 0 {
            None
        } else {
            Some(out)
        }
    }

    pub fn get_property_i64(&self, handle: *mut MpvHandle, name: &str) -> Option<i64> {
        let k = CString::new(name).ok()?;
        let mut out: i64 = 0;
        let rc = unsafe {
            (self.get_property)(
                handle,
                k.as_ptr(),
                MPV_FORMAT_INT64,
                &mut out as *mut i64 as *mut c_void,
            )
        };
        if rc < 0 {
            None
        } else {
            Some(out)
        }
    }

    pub fn get_property_bool(&self, handle: *mut MpvHandle, name: &str) -> Option<bool> {
        let k = CString::new(name).ok()?;
        let mut out: c_int = 0;
        let rc = unsafe {
            (self.get_property)(
                handle,
                k.as_ptr(),
                MPV_FORMAT_FLAG,
                &mut out as *mut c_int as *mut c_void,
            )
        };
        if rc < 0 {
            None
        } else {
            Some(out != 0)
        }
    }

    pub fn command(&self, handle: *mut MpvHandle, args: &[&str]) -> Result<(), c_int> {
        let c_args: Vec<CString> = args
            .iter()
            .map(|a| CString::new(*a).map_err(|_| -4))
            .collect::<Result<_, _>>()?;
        let mut ptrs: Vec<*const c_char> = c_args.iter().map(|s| s.as_ptr()).collect();
        ptrs.push(std::ptr::null());
        let rc = unsafe { (self.command)(handle, ptrs.as_ptr()) };
        if rc < 0 {
            Err(rc)
        } else {
            Ok(())
        }
    }

    pub fn drain_events(&self, handle: *mut MpvHandle) -> Vec<c_int> {
        let mut ids = Vec::new();
        for _ in 0..32 {
            let ev = unsafe { (self.wait_event)(handle, 0.0) };
            if ev.is_null() {
                break;
            }
            let id = unsafe { (*ev).event_id };
            if id == 0 {
                break;
            }
            ids.push(id);
        }
        ids
    }
}
