#include "include/meeting_core_ffi.h"

#include <stdlib.h>
#include <string.h>

#ifdef MEETING_USE_RUST_FFI
// Rust FFI mode: this translation unit intentionally exports no C ABI symbols.
int meeting_core_ffi_stub_disabled = 1;
#else

typedef struct {
  int placeholder;
} ma_runtime_stub;

static ma_event_callback g_callback = NULL;
static void* g_user_data = NULL;

void* ma_runtime_new(const char* config_json) {
  (void)config_json;
  ma_runtime_stub* runtime = (ma_runtime_stub*)malloc(sizeof(ma_runtime_stub));
  if (runtime != NULL) {
    runtime->placeholder = 1;
  }
  return runtime;
}

void ma_runtime_free(void* runtime_handle) {
  if (runtime_handle != NULL) {
    free(runtime_handle);
  }
}

char* ma_invoke_json(void* runtime_handle, const char* request_json) {
  (void)runtime_handle;
  (void)request_json;
  const char* payload =
      "{\"ok\":false,\"error\":{\"code\":\"ffi_stub\",\"message\":\"Linked to local FFI stub. Replace with Rust libmeeting_core_ffi for production.\"}}";
  size_t len = strlen(payload);
  char* out = (char*)malloc(len + 1);
  if (out == NULL) {
    return NULL;
  }
  memcpy(out, payload, len + 1);
  return out;
}

void ma_set_event_callback(void* runtime_handle, ma_event_callback callback, void* user_data) {
  (void)runtime_handle;
  g_callback = callback;
  g_user_data = user_data;
}

void ma_free_c_string(char* ptr) {
  if (ptr != NULL) {
    free(ptr);
  }
}

#endif
