use std::{
    ffi::{c_char, c_void, CStr, CString},
    ptr,
    sync::{Arc, Mutex},
};

use meeting_core::Runtime;
use serde_json::json;

type MaEventCallback = unsafe extern "C" fn(event_json: *const c_char, user_data: *mut c_void);

#[derive(Clone, Copy)]
struct CallbackRegistration {
    callback: MaEventCallback,
    user_data: usize,
}

#[repr(C)]
pub struct MaRuntimeHandle {
    runtime: Runtime,
    callback: Arc<Mutex<Option<CallbackRegistration>>>,
}

#[no_mangle]
pub unsafe extern "C" fn ma_runtime_new(config_json: *const c_char) -> *mut MaRuntimeHandle {
    let config = if config_json.is_null() {
        String::new()
    } else {
        match CStr::from_ptr(config_json).to_str() {
            Ok(value) => value.to_string(),
            Err(error) => {
                eprintln!("ma_runtime_new: invalid UTF-8 config json: {error}");
                return ptr::null_mut();
            }
        }
    };

    let runtime = match Runtime::new(&config) {
        Ok(value) => value,
        Err(error) => {
            eprintln!("ma_runtime_new: failed to initialize runtime: {error}");
            return ptr::null_mut();
        }
    };

    let callback = Arc::new(Mutex::new(None::<CallbackRegistration>));
    let callback_ref = Arc::clone(&callback);
    runtime.set_event_callback(move |_event, payload| {
        let registration = {
            let guard = callback_ref
                .lock()
                .expect("ffi callback registration mutex poisoned");
            *guard
        };
        if let Some(registration) = registration {
            let payload_json = payload.to_string();
            if let Ok(c_payload) = CString::new(payload_json) {
                unsafe {
                    (registration.callback)(c_payload.as_ptr(), registration.user_data as *mut c_void)
                };
            }
        }
    });

    Box::into_raw(Box::new(MaRuntimeHandle { runtime, callback }))
}

#[no_mangle]
pub unsafe extern "C" fn ma_runtime_free(handle: *mut MaRuntimeHandle) {
    if handle.is_null() {
        return;
    }
    let boxed = Box::from_raw(handle);
    boxed.runtime.clear_event_callback();
    let mut guard = boxed
        .callback
        .lock()
        .expect("ffi callback registration mutex poisoned");
    *guard = None;
}

#[no_mangle]
pub unsafe extern "C" fn ma_set_event_callback(
    handle: *mut MaRuntimeHandle,
    callback: Option<MaEventCallback>,
    user_data: *mut c_void,
) {
    if handle.is_null() {
        return;
    }

    let runtime = &mut *handle;
    let mut guard = runtime
        .callback
        .lock()
        .expect("ffi callback registration mutex poisoned");
    *guard = callback.map(|value| CallbackRegistration {
        callback: value,
        user_data: user_data as usize,
    });
}

#[no_mangle]
pub unsafe extern "C" fn ma_invoke_json(
    handle: *mut MaRuntimeHandle,
    request_json: *const c_char,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string(json_error("invalid_handle", "runtime handle is null").to_string());
    }
    if request_json.is_null() {
        return into_c_string(json_error("invalid_request", "request_json is null").to_string());
    }

    let request = match CStr::from_ptr(request_json).to_str() {
        Ok(value) => value,
        Err(error) => {
            return into_c_string(
                json_error("invalid_request", &format!("request_json must be UTF-8: {error}"))
                    .to_string(),
            );
        }
    };

    let runtime = &mut *handle;
    let response = runtime.runtime.invoke_json(request);
    into_c_string(response)
}

#[no_mangle]
pub unsafe extern "C" fn ma_free_c_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = CString::from_raw(ptr);
}

fn into_c_string(value: String) -> *mut c_char {
    match CString::new(value) {
        Ok(text) => text.into_raw(),
        Err(_) => CString::new(
            r#"{"ok":false,"error":{"code":"encoding_failure","message":"response contains invalid NUL"}}"#,
        )
        .expect("fallback c string literal is valid")
        .into_raw(),
    }
}

fn json_error(code: &str, message: &str) -> serde_json::Value {
    json!({
        "ok": false,
        "error": {
            "code": code,
            "message": message
        }
    })
}
