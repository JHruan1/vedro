#ifndef VEDRO_FFI_H
#define VEDRO_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VedroRuntime VedroRuntime;

/**
 * Initialize the Vedro Rust Core runtime (Tokio multi-thread executor, SQLite WAL store,
 * local HTTP Range prefetch proxy, and native libmpv/libplacebo controller).
 *
 * @param db_path_utf8 Path to SQLite database file, or NULL / ":memory:" for in-memory mode.
 * @return Opaque runtime handle, or NULL on fatal initialization failure.
 */
VedroRuntime* vedro_init(const char* db_path_utf8);

/**
 * Invoke any Vedro core API method synchronously (bridged onto the internal Tokio runtime).
 *
 * @param rt Non-null runtime handle.
 * @param method_utf8 UTF-8 method name (e.g., "connect_server", "login", "get_home", "prepare_playback").
 * @param params_json_utf8 UTF-8 JSON object string (or NULL / "{}").
 * @return Newly allocated UTF-8 JSON string `{"ok":true,"data":...}` or `{"ok":false,"error":"..."}`.
 *         Caller MUST free the returned string with `vedro_free_string`.
 */
char* vedro_invoke(VedroRuntime* rt, const char* method_utf8, const char* params_json_utf8);

/**
 * Drain queued asynchronous events (WebSocket remote-control commands, UserDataChanged,
 * playback telemetry updates) as a UTF-8 JSON array string.
 * Caller MUST free the returned string with `vedro_free_string`.
 */
char* vedro_poll_events(VedroRuntime* rt);

/**
 * Fast lock-free readout of current local proxy download speed in bytes/sec (0 JSON, 0 allocations).
 */
uint64_t vedro_proxy_speed_bps(VedroRuntime* rt);

/**
 * Return the Vedro Core version string (static, do NOT free).
 */
const char* vedro_version(void);

/**
 * Free a UTF-8 string returned by `vedro_invoke` or `vedro_poll_events`.
 */
void vedro_free_string(char* ptr);

/**
 * Gracefully shut down playback, stream proxy, WebSocket session, and runtime.
 */
void vedro_destroy(VedroRuntime* rt);

#ifdef __cplusplus
}
#endif

#endif /* VEDRO_FFI_H */
