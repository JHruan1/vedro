#ifndef PRISM_FFI_H
#define PRISM_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PrismRuntime PrismRuntime;

/**
 * Initialize the Prism Rust Core runtime (Tokio multi-thread executor, SQLite WAL store,
 * local HTTP Range prefetch proxy, and native libmpv/libplacebo controller).
 *
 * @param db_path_utf8 Path to SQLite database file, or NULL / ":memory:" for in-memory mode.
 * @return Opaque runtime handle, or NULL on fatal initialization failure.
 */
PrismRuntime* prism_init(const char* db_path_utf8);

/**
 * Invoke any Prism core API method synchronously (bridged onto the internal Tokio runtime).
 *
 * @param rt Non-null runtime handle.
 * @param method_utf8 UTF-8 method name (e.g., "connect_server", "login", "get_home", "prepare_playback").
 * @param params_json_utf8 UTF-8 JSON object string (or NULL / "{}").
 * @return Newly allocated UTF-8 JSON string `{"ok":true,"data":...}` or `{"ok":false,"error":"..."}`.
 *         Caller MUST free the returned string with `prism_free_string`.
 */
char* prism_invoke(PrismRuntime* rt, const char* method_utf8, const char* params_json_utf8);

/**
 * Drain queued asynchronous events (WebSocket remote-control commands, UserDataChanged,
 * playback telemetry updates) as a UTF-8 JSON array string.
 * Caller MUST free the returned string with `prism_free_string`.
 */
char* prism_poll_events(PrismRuntime* rt);

/**
 * Return the Prism Core version string (static, do NOT free).
 */
const char* prism_version(void);

/**
 * Free a UTF-8 string returned by `prism_invoke` or `prism_poll_events`.
 */
void prism_free_string(char* ptr);

/**
 * Gracefully shut down playback, stream proxy, WebSocket session, and runtime.
 */
void prism_destroy(PrismRuntime* rt);

#ifdef __cplusplus
}
#endif

#endif /* PRISM_FFI_H */
