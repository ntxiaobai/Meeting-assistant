#ifndef MEETING_CORE_FFI_H
#define MEETING_CORE_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ma_event_callback)(const char* event_json, void* user_data);

void* ma_runtime_new(const char* config_json);
void ma_runtime_free(void* runtime_handle);
char* ma_invoke_json(void* runtime_handle, const char* request_json);
void ma_set_event_callback(void* runtime_handle, ma_event_callback callback, void* user_data);
void ma_free_c_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif

