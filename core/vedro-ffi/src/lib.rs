#![allow(clippy::not_unsafe_ptr_arg_deref)]

mod c_abi;
mod danmaku;
mod rpc_admin;
mod rpc_ai;
mod rpc_media;
mod rpc_server;
mod security;
mod types;
mod updater;

#[cfg(test)]
mod tests;

pub use c_abi::*;
pub use types::{CombinedPlayerStats, ExternalSubtitle, PreparedPlayback};

use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use parking_lot::Mutex;
use serde_json::{json, Value};
use tokio::runtime::Runtime;
use tracing::warn;
use vedro_playback::{PlaybackConfig, PlaybackEngine};
use vedro_protocol::{
    BaseItemDto, ClientIdentity, ClientTransportOptions, EmbyClient, MediaStream, WebSocketSession,
};
use vedro_storage::VedroStore;
use vedro_stream::{StreamProxy, StreamProxyConfig};

use crate::rpc_media::apply_learned_streams;
use crate::types::ActivePlaybackSession;
use crate::updater::UpdateDownloadState;

pub(crate) enum RpcErr {
    Err(String),
    Unhandled,
}

impl From<String> for RpcErr {
    fn from(e: String) -> Self {
        Self::Err(e)
    }
}

impl From<&str> for RpcErr {
    fn from(e: &str) -> Self {
        Self::Err(e.to_string())
    }
}

/// Core runtime backing both the C-ABI FFI library (`libvedro_ffi`) and native Rust hosts.
/// Field order & explicit `Drop` ensure playback/ws/proxy stop before the Tokio runtime shuts down.
pub struct VedroRuntime {
    pub(crate) engine: Mutex<Option<Arc<PlaybackEngine>>>,
    pub(crate) ws: Mutex<Option<WebSocketSession>>,
    pub(crate) active_session: Mutex<Option<ActivePlaybackSession>>,
    pub(crate) client: Mutex<Option<EmbyClient>>,
    pub(crate) active_server_id: Mutex<Option<String>>,
    pub(crate) session_epoch: std::sync::atomic::AtomicU64,
    pub(crate) playback_epoch: std::sync::atomic::AtomicU64,
    pub(crate) speedtest_epoch: std::sync::atomic::AtomicU64,
    pub(crate) proxy: Arc<StreamProxy>,
    pub(crate) store: Arc<VedroStore>,
    pub(crate) playback_config: Mutex<PlaybackConfig>,
    pub(crate) events: Arc<Mutex<VecDeque<Value>>>,
    pub(crate) identity: Mutex<ClientIdentity>,
    pub(crate) speedtest_cancel: Arc<std::sync::atomic::AtomicBool>,
    pub(crate) explicitly_logged_out: std::sync::atomic::AtomicBool,
    pub(crate) http_default: reqwest::Client,
    pub(crate) http_direct: reqwest::Client,
    pub(crate) asr_temp_dir: PathBuf,
    pub(crate) updates_dir: PathBuf,
    pub(crate) update_download: Arc<Mutex<UpdateDownloadState>>,
    pub(crate) update_cancel: Arc<std::sync::atomic::AtomicBool>,
    pub(crate) update_epoch: std::sync::atomic::AtomicU64,
    pub(crate) rt: Option<Runtime>,
}

impl Drop for VedroRuntime {
    fn drop(&mut self) {
        let in_tokio = tokio::runtime::Handle::try_current().is_ok();
        // 1. Terminate libmpv first so it stops reading from StreamProxy
        self.engine.lock().take();
        // 2. Stop active WebSocket session (construct timeout INSIDE `rt.block_on` so reactor is active!)
        if let Some(mut ws) = self.ws.lock().take() {
            if !in_tokio {
                if let Some(ref rt) = self.rt {
                    rt.block_on(async move {
                        let _ = tokio::time::timeout(Duration::from_millis(500), ws.stop()).await;
                    });
                }
            }
        }
        // 3. Unregister active stream and explicitly signal proxy listener shutdown
        if let Some(sess) = self.active_session.lock().take() {
            self.proxy.unregister_stream(&sess.stream_id);
        }
        self.proxy.shutdown();
        // 4. Shut down Tokio runtime with bounded timeout so shutdown never hangs
        if let Some(rt) = self.rt.take() {
            if in_tokio {
                rt.shutdown_background();
            } else {
                rt.shutdown_timeout(Duration::from_secs(2));
            }
        }
    }
}

impl VedroRuntime {
    pub fn new(db_path: Option<&str>) -> Result<Self, String> {
        let _ = tracing_subscriber::fmt()
            .with_env_filter(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
            )
            .try_init();

        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .thread_name("vedro-core")
            .build()
            .map_err(|e| format!("failed to build tokio runtime: {e}"))?;

        let db_dir = db_path
            .filter(|p| !p.is_empty() && *p != ":memory:")
            .and_then(|p| std::path::Path::new(p).parent().map(|d| d.to_path_buf()));

        let store = Arc::new(
            match db_path {
                None | Some("") | Some(":memory:") => VedroStore::open_in_memory(),
                Some(p) => VedroStore::open(p),
            }
            .map_err(|e| format!("failed to open storage: {e}"))?,
        );

        let asr_temp_dir = db_dir
            .as_ref()
            .map(|d| d.join("asr_tmp"))
            .unwrap_or_else(|| {
                std::env::temp_dir().join(format!("vedro_asr_{}", std::process::id()))
            });
        let updates_dir = db_dir
            .as_ref()
            .map(|d| d.join("updates"))
            .unwrap_or_else(|| {
                std::env::temp_dir().join(format!("vedro_updates_{}", std::process::id()))
            });
        let _ = std::fs::create_dir_all(&asr_temp_dir);
        let _ = std::fs::create_dir_all(&updates_dir);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&asr_temp_dir, std::fs::Permissions::from_mode(0o700));
        }
        // Sweep orphaned ASR temp WAV files from previous crashes on startup
        let startup_asr_dir = asr_temp_dir.clone();
        rt.spawn(async move {
            if let Ok(mut rd) = tokio::fs::read_dir(&startup_asr_dir).await {
                while let Ok(Some(ent)) = rd.next_entry().await {
                    let name = ent.file_name().to_string_lossy().to_string();
                    if name.starts_with("vedro_asr_") && name.ends_with(".wav") {
                        let _ = tokio::fs::remove_file(ent.path()).await;
                    }
                }
            }
        });

        let build_http = |timeout_secs: u64, direct: bool| -> Result<reqwest::Client, String> {
            let attempt = |disable_native_certs: bool, force_no_proxy: bool| {
                let mut b = reqwest::Client::builder()
                    .pool_max_idle_per_host(8)
                    .connect_timeout(Duration::from_secs(12))
                    .timeout(Duration::from_secs(timeout_secs))
                    .tcp_nodelay(true);
                if disable_native_certs {
                    b = b.tls_built_in_native_certs(false);
                }
                if direct || force_no_proxy {
                    b = b.no_proxy();
                }
                b.build()
            };
            match attempt(false, false) {
                Ok(c) => Ok(c),
                Err(first_err) => {
                    warn!(
                        error = %first_err,
                        direct,
                        "reqwest client build failed with OS certs/proxy; falling back to bundled WebPKI roots"
                    );
                    attempt(true, false)
                        .or_else(|_| attempt(true, true))
                        .map_err(|e| format!("{first_err} (fallback: {e})"))
                }
            }
        };

        let http_default = build_http(45, false)
            .map_err(|e| format!("failed to build default http client: {e}"))?;
        let http_direct =
            build_http(60, true).map_err(|e| format!("failed to build direct http client: {e}"))?;

        let saved_cfg: PlaybackConfig = store
            .get_setting("playback_config")
            .ok()
            .flatten()
            .unwrap_or_default();

        let saved_device_id: String = store
            .get_setting("device_id")
            .ok()
            .flatten()
            .unwrap_or_else(|| {
                let id = uuid::Uuid::new_v4().to_string();
                let _ = store.set_setting("device_id", &id);
                id
            });

        let identity = ClientIdentity {
            device_id: saved_device_id,
            ..Default::default()
        };

        let proxy = rt
            .block_on(StreamProxy::start(StreamProxyConfig::default()))
            .map_err(|e| format!("failed to start local stream proxy: {e}"))?;
        if let Some(ref d) = db_dir {
            let _rt_guard = rt.enter();
            proxy.set_image_cache_dir(d.join("img_cache"));
        }

        // Pre-register saved server image upstreams + optimistically attach the last active
        // authenticated client IMMEDIATELY on cold start so BOTH:
        //  1) `http://127.0.0.1:<port>/img/...` loads artwork at millisecond 0 (with proxy/TLS config!), AND
        //  2) `get_home`/`get_item`/`get_items` NEVER fail with "no server connected" while SWR hydrates!
        let mut initial_client: Option<EmbyClient> = None;
        let mut initial_server_id: Option<String> = None;
        let mut initial_logged_out = false;
        if let Ok(saved_list) = store.list_servers() {
            let raw_remembered = store
                .get_setting::<String>("last_active_server_id")
                .ok()
                .flatten();
            if raw_remembered
                .as_deref()
                .map(|s| s.trim().is_empty())
                .unwrap_or(false)
            {
                initial_logged_out = true;
            }
            let remembered_id = raw_remembered
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());
            for srv in &saved_list {
                let route_url = srv
                    .active_route()
                    .map(|r| r.url.clone())
                    .filter(|u| !u.is_empty())
                    .unwrap_or_else(|| srv.url.clone());
                let hdrs = identity.build_headers(srv.access_token.as_deref());
                proxy.register_server_image_upstream(srv.id.clone(), route_url, hdrs);
            }
            if !initial_logged_out {
                let target_srv = remembered_id
                    .as_deref()
                    .and_then(|rid| {
                        saved_list.iter().find(|s| {
                            s.id == rid && s.access_token.is_some() && s.user_id.is_some()
                        })
                    })
                    .or_else(|| {
                        saved_list
                            .iter()
                            .filter(|s| s.access_token.is_some() && s.user_id.is_some())
                            .max_by_key(|s| s.last_connected_at)
                    });
                if let Some(srv) = target_srv {
                    let route = srv.active_route();
                    let route_url = route
                        .map(|r| r.url.clone())
                        .filter(|u| !u.is_empty())
                        .unwrap_or_else(|| srv.url.clone());
                    let route_proxy = route
                        .and_then(|r| r.proxy_url.as_deref())
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                        .map(ToString::to_string);
                    let accept_invalid = route.map(|r| r.accept_invalid_certs).unwrap_or(false);
                    let _ = proxy.configure_transport(route_proxy.as_deref(), accept_invalid);
                    let hdrs = identity.build_headers(srv.access_token.as_deref());
                    proxy.set_image_upstream(route_url.clone(), hdrs);
                    if let (Some(tok), Some(uid)) = (&srv.access_token, &srv.user_id) {
                        if let Ok(c) = EmbyClient::with_options(
                            &route_url,
                            identity.clone(),
                            ClientTransportOptions {
                                proxy_url: route_proxy,
                                accept_invalid_certs: accept_invalid,
                            },
                        ) {
                            c.seed_dialect_hint(&srv.dialect, Some(&srv.id), Some(&srv.name));
                            c.set_credentials(tok.clone(), uid.clone());
                            initial_client = Some(c);
                            initial_server_id = Some(srv.id.clone());
                        }
                    }
                }
            }
        }

        Ok(Self {
            engine: Mutex::new(None),
            ws: Mutex::new(None),
            active_session: Mutex::new(None),
            client: Mutex::new(initial_client),
            active_server_id: Mutex::new(initial_server_id),
            session_epoch: std::sync::atomic::AtomicU64::new(0),
            playback_epoch: std::sync::atomic::AtomicU64::new(0),
            speedtest_epoch: std::sync::atomic::AtomicU64::new(0),
            proxy,
            store,
            playback_config: Mutex::new(saved_cfg),
            events: Arc::new(Mutex::new(VecDeque::with_capacity(256))),
            identity: Mutex::new(identity),
            speedtest_cancel: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            explicitly_logged_out: std::sync::atomic::AtomicBool::new(initial_logged_out),
            http_default,
            http_direct,
            asr_temp_dir,
            updates_dir,
            update_download: Arc::new(Mutex::new(UpdateDownloadState {
                status: "idle".to_string(),
                ..Default::default()
            })),
            update_cancel: Arc::new(std::sync::atomic::AtomicBool::new(false)),
            update_epoch: std::sync::atomic::AtomicU64::new(0),
            rt: Some(rt),
        })
    }

    pub fn proxy_speed_bps(&self) -> u64 {
        self.proxy.current_speed_bps()
    }

    pub fn poll_events(&self) -> Vec<Value> {
        let mut guard = self.events.lock();
        guard.drain(..).collect()
    }

    pub fn invoke(&self, method: &str, params: Value) -> Result<Value, String> {
        let Some(ref rt) = self.rt else {
            return Err("runtime shut down".to_string());
        };
        rt.block_on(self.invoke_async(method, params))
    }

    /// Lazily attach the last active saved server (with proxy/TLS config & credentials)
    /// when `self.client` is empty and the user has NOT explicitly logged out.
    pub(crate) fn attach_saved_server_optimistically(&self) -> Option<EmbyClient> {
        if let Some(existing) = self.client.lock().clone() {
            return Some(existing);
        }
        if self
            .explicitly_logged_out
            .load(std::sync::atomic::Ordering::SeqCst)
        {
            return None;
        }
        let saved_list = self.store.list_servers().ok()?;
        let raw_remembered = self
            .store
            .get_setting::<String>("last_active_server_id")
            .ok()
            .flatten();
        if raw_remembered
            .as_deref()
            .map(|s| s.trim().is_empty())
            .unwrap_or(false)
        {
            return None;
        }
        let remembered_id = raw_remembered
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        let target_srv = remembered_id
            .as_deref()
            .and_then(|rid| {
                saved_list
                    .iter()
                    .find(|s| s.id == rid && s.access_token.is_some() && s.user_id.is_some())
            })
            .or_else(|| {
                saved_list
                    .iter()
                    .filter(|s| s.access_token.is_some() && s.user_id.is_some())
                    .max_by_key(|s| s.last_connected_at)
            })?;
        let route = target_srv.active_route();
        let route_url = route
            .map(|r| r.url.clone())
            .filter(|u| !u.is_empty())
            .unwrap_or_else(|| target_srv.url.clone());
        let route_proxy = route
            .and_then(|r| r.proxy_url.as_deref())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToString::to_string);
        let accept_invalid = route.map(|r| r.accept_invalid_certs).unwrap_or(false);
        let _ = self
            .proxy
            .configure_transport(route_proxy.as_deref(), accept_invalid);
        let identity = self.identity.lock().clone();
        let client = EmbyClient::with_options(
            &route_url,
            identity,
            ClientTransportOptions {
                proxy_url: route_proxy,
                accept_invalid_certs: accept_invalid,
            },
        )
        .ok()?;
        client.seed_dialect_hint(
            &target_srv.dialect,
            Some(&target_srv.id),
            Some(&target_srv.name),
        );
        if let (Some(tok), Some(uid)) = (&target_srv.access_token, &target_srv.user_id) {
            client.set_credentials(tok.clone(), uid.clone());
        }
        let hdrs = client.auth_headers();
        self.proxy
            .set_image_upstream(client.effective_base_url(), hdrs.clone());
        self.proxy.register_server_image_upstream(
            target_srv.id.clone(),
            client.effective_base_url(),
            hdrs,
        );
        let mut guard = self.client.lock();
        if let Some(existing) = guard.clone() {
            return Some(existing);
        }
        *guard = Some(client.clone());
        *self.active_server_id.lock() = Some(target_srv.id.clone());
        Some(client)
    }

    pub(crate) fn require_client(&self) -> Result<EmbyClient, String> {
        if let Some(c) = self.client.lock().clone() {
            return Ok(c);
        }
        if let Some(c) = self.attach_saved_server_optimistically() {
            return Ok(c);
        }
        Err("no server connected; call connect_server first".to_string())
    }

    pub(crate) fn ensure_engine(
        &self,
        headless_override: Option<bool>,
    ) -> Result<Arc<PlaybackEngine>, String> {
        let mut guard = self.engine.lock();
        if let Some(eng) = guard.as_ref() {
            return Ok(Arc::clone(eng));
        }
        let mut cfg = self.playback_config.lock().clone();
        if let Some(h) = headless_override {
            cfg.headless_null_vo = h;
        }
        let eng = PlaybackEngine::new(cfg).map_err(|e| e.to_string())?;
        *guard = Some(Arc::clone(&eng));
        Ok(eng)
    }

    pub(crate) fn enrich_item_with_learned_tracks(&self, item: &mut BaseItemDto) {
        if item.id.is_empty() || item.media_sources.is_empty() {
            return;
        }
        for ms in &mut item.media_sources {
            let has_av = ms.media_streams.iter().any(|s| {
                s.stream_type.eq_ignore_ascii_case("Audio")
                    || s.stream_type.eq_ignore_ascii_case("Video")
            });
            if has_av {
                continue;
            }
            let src_id = if ms.id.is_empty() {
                "default"
            } else {
                ms.id.as_str()
            };
            let learned_key = format!("learned_streams_v1:{}:{}", item.id, src_id);
            if let Ok(Some(learned)) = self.store.get_setting::<Vec<MediaStream>>(&learned_key) {
                apply_learned_streams(ms, learned);
            }
        }
    }

    /// Batch-enrich an entire episode list with ONE single SQLite prefix query (eliminates N+1 up to 5000 queries!).
    pub(crate) fn enrich_items_batch_with_learned_tracks(&self, items: &mut [BaseItemDto]) {
        let mut wanted_keys: Vec<String> = Vec::new();
        for item in items.iter() {
            if item.id.is_empty() || item.media_sources.is_empty() {
                continue;
            }
            for ms in &item.media_sources {
                let has_av = ms.media_streams.iter().any(|s| {
                    s.stream_type.eq_ignore_ascii_case("Audio")
                        || s.stream_type.eq_ignore_ascii_case("Video")
                });
                if has_av {
                    continue;
                }
                let src_id = if ms.id.is_empty() {
                    "default"
                } else {
                    ms.id.as_str()
                };
                wanted_keys.push(format!("learned_streams_v1:{}:{}", item.id, src_id));
            }
        }
        if wanted_keys.is_empty() {
            return;
        }
        let Ok(all_learned) = self.store.get_settings_by_keys(&wanted_keys) else {
            return;
        };
        if all_learned.is_empty() {
            return;
        }
        for item in items.iter_mut() {
            if item.id.is_empty() || item.media_sources.is_empty() {
                continue;
            }
            for ms in &mut item.media_sources {
                let has_av = ms.media_streams.iter().any(|s| {
                    s.stream_type.eq_ignore_ascii_case("Audio")
                        || s.stream_type.eq_ignore_ascii_case("Video")
                });
                if has_av {
                    continue;
                }
                let src_id = if ms.id.is_empty() {
                    "default"
                } else {
                    ms.id.as_str()
                };
                let key = format!("learned_streams_v1:{}:{}", item.id, src_id);
                if let Some(raw_json) = all_learned.get(&key) {
                    if let Ok(learned) = serde_json::from_str::<Vec<MediaStream>>(raw_json) {
                        apply_learned_streams(ms, learned);
                    }
                }
            }
        }
    }

    pub(crate) fn start_websocket(&self, client: EmbyClient, expected_epoch: u64) {
        let Some(ref rt) = self.rt else {
            return;
        };
        let mut ws_guard = self.ws.lock();
        if self.session_epoch.load(std::sync::atomic::Ordering::SeqCst) != expected_epoch {
            return;
        }
        if let Some(mut old) = ws_guard.take() {
            rt.spawn(async move {
                old.stop().await;
            });
        }
        let (session, mut rx) = WebSocketSession::spawn(client);
        *ws_guard = Some(session);
        drop(ws_guard);
        let events = Arc::clone(&self.events);
        rt.spawn(async move {
            while let Some(ev) = rx.recv().await {
                if let Ok(v) = serde_json::to_value(&ev) {
                    let mut q = events.lock();
                    if q.len() >= 256 {
                        q.pop_front();
                    }
                    q.push_back(json!({"source": "websocket", "event": v}));
                }
            }
        });
    }

    pub async fn invoke_async(&self, method: &str, params: Value) -> Result<Value, String> {
        macro_rules! try_domain {
            ($call:expr) => {
                match $call.await {
                    Ok(v) => return Ok(v),
                    Err(RpcErr::Err(e)) => return Err(e),
                    Err(RpcErr::Unhandled) => {}
                }
            };
        }

        try_domain!(self.handle_server_rpc(method, &params));
        try_domain!(self.handle_media_rpc(method, &params));
        try_domain!(self.handle_admin_rpc(method, &params));
        try_domain!(self.handle_ai_rpc(method, &params));
        try_domain!(self.handle_danmaku_rpc(method, &params));
        try_domain!(self.handle_updater_rpc(method, &params));

        Err(format!("unknown vedro_invoke method: {method}"))
    }
}
