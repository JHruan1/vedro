#![allow(clippy::not_unsafe_ptr_arg_deref)]
use std::collections::VecDeque;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;
use std::time::Duration;

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::runtime::Runtime;
use tracing::warn;
use vedro_playback::{
    AudioOutputMode, AudioRoutingDecision, DolbyVisionDecision, PlaybackConfig, PlaybackEngine,
    PlaybackStats, ToneMappingAlgorithm,
};
use vedro_protocol::{
    discover_lan_servers, BaseItemDto, ClientIdentity, ClientTransportOptions, EmbyClient,
    ItemsQuery, MediaBadges, MediaSourceInfo, MediaStream, PlaybackProgressPayload,
    WebSocketSession,
};
use vedro_storage::{ServerProfile, ServerRoute, VedroStore};
use vedro_stream::{
    inspect_media_header, InspectedMedia, StreamProxy, StreamProxyConfig, StreamProxyStats,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreparedPlayback {
    pub item_id: String,
    pub media_source_id: String,
    pub play_session_id: String,
    pub stream_id: String,
    pub proxy_url: String,
    pub upstream_url: String,
    pub uses_stream_ticket: bool,
    pub media_source: MediaSourceInfo,
    pub badges: MediaBadges,
    pub inspected: Option<InspectedMedia>,
    pub hdr_decision: DolbyVisionDecision,
    pub audio_decision: AudioRoutingDecision,
    pub mpv_options: Vec<(String, String)>,
    pub external_subtitles: Vec<ExternalSubtitle>,
    pub all_sources: Vec<MediaSourceInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExternalSubtitle {
    pub index: i32,
    pub language: Option<String>,
    pub title: String,
    pub codec: String,
    pub is_default: bool,
    pub is_forced: bool,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CombinedPlayerStats {
    pub playback: PlaybackStats,
    pub proxy: StreamProxyStats,
}

struct ActivePlaybackSession {
    item_id: String,
    media_source_id: String,
    play_session_id: String,
    stream_id: String,
    run_time_ticks: Option<i64>,
    audio_stream_index: Option<i32>,
    subtitle_stream_index: Option<i32>,
}

/// Core runtime backing both the C-ABI FFI library (`libvedro_ffi`) and native Rust hosts.
pub struct VedroRuntime {
    rt: Runtime,
    store: VedroStore,
    proxy: Arc<StreamProxy>,
    client: Mutex<Option<EmbyClient>>,
    ws: Mutex<Option<WebSocketSession>>,
    engine: Mutex<Option<Arc<PlaybackEngine>>>,
    playback_config: Mutex<PlaybackConfig>,
    active_session: Mutex<Option<ActivePlaybackSession>>,
    events: Arc<Mutex<VecDeque<Value>>>,
    identity: Mutex<ClientIdentity>,
    speedtest_cancel: Arc<std::sync::atomic::AtomicBool>,
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

        let store = match db_path {
            None | Some("") | Some(":memory:") => VedroStore::open_in_memory(),
            Some(p) => VedroStore::open(p),
        }
        .map_err(|e| format!("failed to open storage: {e}"))?;

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
            proxy.set_image_cache_dir(d.join("img_cache"));
        }

        // Pre-register saved server image upstreams + remembered active upstream IMMEDIATELY on cold start
        // so `http://127.0.0.1:<port>/img/...` serves cached/live artwork at millisecond 0 without waiting
        // for `restore_session` network round-trips!
        if let Ok(saved_list) = store.list_servers() {
            let remembered_id = store
                .get_setting::<String>("last_active_server_id")
                .ok()
                .flatten()
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
            let target_srv = remembered_id
                .as_deref()
                .and_then(|rid| {
                    saved_list
                        .iter()
                        .find(|s| s.id == rid && s.access_token.is_some())
                })
                .or_else(|| {
                    saved_list
                        .iter()
                        .filter(|s| s.access_token.is_some())
                        .max_by_key(|s| s.last_connected_at)
                });
            if let Some(srv) = target_srv {
                let route_url = srv
                    .active_route()
                    .map(|r| r.url.clone())
                    .filter(|u| !u.is_empty())
                    .unwrap_or_else(|| srv.url.clone());
                let hdrs = identity.build_headers(srv.access_token.as_deref());
                proxy.set_image_upstream(route_url, hdrs);
            }
        }

        Ok(Self {
            rt,
            store,
            proxy,
            client: Mutex::new(None),
            ws: Mutex::new(None),
            engine: Mutex::new(None),
            playback_config: Mutex::new(saved_cfg),
            active_session: Mutex::new(None),
            events: Arc::new(Mutex::new(VecDeque::with_capacity(256))),
            identity: Mutex::new(identity),
            speedtest_cancel: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        })
    }

    pub fn poll_events(&self) -> Vec<Value> {
        let mut guard = self.events.lock();
        guard.drain(..).collect()
    }

    pub fn invoke(&self, method: &str, params: Value) -> Result<Value, String> {
        self.rt.block_on(self.invoke_async(method, params))
    }

    fn require_client(&self) -> Result<EmbyClient, String> {
        self.client
            .lock()
            .clone()
            .ok_or_else(|| "no server connected; call connect_server first".to_string())
    }

    fn ensure_engine(
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

    fn enrich_item_with_learned_tracks(&self, item: &mut BaseItemDto) {
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
                if !learned.is_empty() {
                    let mut merged: Vec<MediaStream> = ms
                        .media_streams
                        .iter()
                        .filter(|s| s.is_external)
                        .cloned()
                        .collect();
                    let offset = merged.iter().map(|s| s.index + 1).max().unwrap_or(0).max(0);
                    for (idx, mut st) in learned.into_iter().enumerate() {
                        if offset > 0 && st.index < offset {
                            st.index = offset + idx as i32;
                        }
                        merged.push(st);
                    }
                    ms.media_streams = merged;
                }
            }
        }
    }

    fn start_websocket(&self, client: EmbyClient) {
        if let Some(mut old) = self.ws.lock().take() {
            self.rt.spawn(async move {
                old.stop().await;
            });
        }
        let (session, mut rx) = WebSocketSession::spawn(client);
        *self.ws.lock() = Some(session);
        let events = Arc::clone(&self.events);
        self.rt.spawn(async move {
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
        match method {
            "version" => Ok(json!({
                "version": env!("CARGO_PKG_VERSION"),
                "proxy_addr": self.proxy.listen_addr().to_string(),
            })),

            "bootstrap_state" => {
                let list = self.store.list_servers().unwrap_or_default();
                let id_snap = self.identity.lock().clone();
                for srv in &list {
                    let route_url = srv
                        .active_route()
                        .map(|r| r.url.clone())
                        .filter(|u| !u.is_empty())
                        .unwrap_or_else(|| srv.url.clone());
                    let hdrs = id_snap.build_headers(srv.access_token.as_deref());
                    self.proxy
                        .register_server_image_upstream(srv.id.clone(), route_url, hdrs);
                }
                let remembered_id = self
                    .store
                    .get_setting::<String>("last_active_server_id")
                    .ok()
                    .flatten()
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty());
                let target_srv = remembered_id
                    .as_deref()
                    .and_then(|rid| {
                        list.iter().find(|s| {
                            s.id == rid && s.access_token.is_some() && s.user_id.is_some()
                        })
                    })
                    .or_else(|| {
                        list.iter()
                            .filter(|s| s.access_token.is_some() && s.user_id.is_some())
                            .max_by_key(|s| s.last_connected_at)
                    });
                let mut cached_home: Option<Value> = None;
                if let Some(srv) = target_srv {
                    let route_url = srv
                        .active_route()
                        .map(|r| r.url.clone())
                        .filter(|u| !u.is_empty())
                        .unwrap_or_else(|| srv.url.clone());
                    let hdrs = id_snap.build_headers(srv.access_token.as_deref());
                    self.proxy.set_image_upstream(route_url, hdrs);
                    cached_home = self
                        .store
                        .get_setting::<Value>(&format!("home_cache_v1:{}", srv.id))
                        .ok()
                        .flatten();
                }
                let cfg = self.playback_config.lock().clone();
                let home_layout = self
                    .store
                    .get_setting::<Value>("home_layout")
                    .ok()
                    .flatten();
                let vedro_prefs = self
                    .store
                    .get_setting::<Value>("vedro_prefs")
                    .ok()
                    .flatten();
                let downloads_queue = self
                    .store
                    .get_setting::<Value>("downloads_queue")
                    .ok()
                    .flatten();

                Ok(json!({
                    "version": env!("CARGO_PKG_VERSION"),
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                    "servers": list,
                    "settings": cfg,
                    "home_layout": home_layout,
                    "vedro_prefs": vedro_prefs,
                    "downloads_queue": downloads_queue,
                    "last_active_server_id": remembered_id,
                    "cached_home": cached_home,
                }))
            }

            "discover_servers" => {
                let timeout_ms = params
                    .get("timeout_ms")
                    .and_then(Value::as_u64)
                    .unwrap_or(1500)
                    .clamp(200, 5000);
                let found = discover_lan_servers(Duration::from_millis(timeout_ms))
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(found).unwrap())
            }

            "list_servers" => {
                let list = self.store.list_servers().map_err(|e| e.to_string())?;
                let id_snap = self.identity.lock().clone();
                for srv in &list {
                    let hdrs = id_snap.build_headers(srv.access_token.as_deref());
                    self.proxy.register_server_image_upstream(
                        srv.id.clone(),
                        srv.url.clone(),
                        hdrs,
                    );
                }
                Ok(serde_json::to_value(list).unwrap())
            }

            "delete_server" => {
                let id = str_param(&params, "id")?;
                self.store.delete_server(&id).map_err(|e| e.to_string())?;
                if let Ok(Some(last_id)) = self.store.get_setting::<String>("last_active_server_id")
                {
                    if last_id == id {
                        let _ = self.store.set_setting("last_active_server_id", &"");
                    }
                }
                Ok(json!({"deleted": id}))
            }

            "save_server_routes" => {
                let server_id = str_param(&params, "server_id")?;
                let mut profile = self
                    .store
                    .get_server(&server_id)
                    .map_err(|e| e.to_string())?
                    .ok_or_else(|| format!("server not found: {server_id}"))?;
                let routes: Vec<ServerRoute> = serde_json::from_value(
                    params.get("routes").cloned().unwrap_or_else(|| json!([])),
                )
                .map_err(|e| format!("invalid routes payload: {e}"))?;
                if routes.is_empty() {
                    return Err("server must have at least one route".to_string());
                }
                profile.routes = routes;
                if let Some(active_id) = params.get("active_route_id").and_then(Value::as_str) {
                    if let Some(r) = profile.routes.iter().find(|r| r.id == active_id) {
                        profile.active_route_id = Some(r.id.clone());
                        profile.url = r.url.clone();
                    }
                } else if !profile
                    .routes
                    .iter()
                    .any(|r| Some(r.id.as_str()) == profile.active_route_id.as_deref())
                {
                    let first = profile.routes[0].clone();
                    profile.active_route_id = Some(first.id);
                    profile.url = first.url;
                }
                self.store
                    .upsert_server(&profile)
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(profile).unwrap())
            }

            "test_server_routes" => {
                let routes: Vec<ServerRoute> =
                    if let Some(sid) = params.get("server_id").and_then(Value::as_str) {
                        let profile = self
                            .store
                            .get_server(sid)
                            .map_err(|e| e.to_string())?
                            .ok_or_else(|| format!("server not found: {sid}"))?;
                        profile.routes
                    } else {
                        serde_json::from_value(
                            params.get("routes").cloned().unwrap_or_else(|| json!([])),
                        )
                        .map_err(|e| format!("invalid routes: {e}"))?
                    };

                let identity = self.identity.lock().clone();
                let mut set = tokio::task::JoinSet::new();
                for (idx, route) in routes.into_iter().enumerate() {
                    let id_clone = identity.clone();
                    set.spawn(async move {
                        let started = std::time::Instant::now();
                        let res = tokio::time::timeout(Duration::from_secs(5), async {
                            let client = EmbyClient::with_options(
                                &route.url,
                                id_clone,
                                ClientTransportOptions {
                                    proxy_url: route.proxy_url.clone(),
                                    accept_invalid_certs: route.accept_invalid_certs,
                                },
                            )
                            .map_err(|e| e.to_string())?;
                            client.probe_server().await.map_err(|e| e.to_string())
                        })
                        .await;
                        let elapsed_ms = started.elapsed().as_millis() as u64;
                        match res {
                            Ok(Ok(_)) => (
                                idx,
                                json!({
                                    "id": route.id,
                                    "name": route.name,
                                    "url": route.url,
                                    "ok": true,
                                    "latency_ms": elapsed_ms,
                                }),
                            ),
                            Ok(Err(err)) => (
                                idx,
                                json!({
                                    "id": route.id,
                                    "name": route.name,
                                    "url": route.url,
                                    "ok": false,
                                    "latency_ms": null,
                                    "error": err,
                                }),
                            ),
                            Err(_) => (
                                idx,
                                json!({
                                    "id": route.id,
                                    "name": route.name,
                                    "url": route.url,
                                    "ok": false,
                                    "latency_ms": null,
                                    "error": "连接超时",
                                }),
                            ),
                        }
                    });
                }
                let mut results = Vec::new();
                while let Some(joined) = set.join_next().await {
                    if let Ok(item) = joined {
                        results.push(item);
                    }
                }
                results.sort_by_key(|(idx, _)| *idx);
                let out: Vec<Value> = results.into_iter().map(|(_, v)| v).collect();
                Ok(Value::Array(out))
            }

            "probe_servers_status" => {
                let target_id = params
                    .get("server_id")
                    .and_then(Value::as_str)
                    .map(ToString::to_string);
                let servers = if let Some(sid) = target_id {
                    self.store
                        .get_server(&sid)
                        .map_err(|e| e.to_string())?
                        .into_iter()
                        .collect::<Vec<_>>()
                } else {
                    self.store.list_servers().map_err(|e| e.to_string())?
                };

                let identity = self.identity.lock().clone();
                let mut set = tokio::task::JoinSet::new();
                for srv in servers {
                    let id_clone = identity.clone();
                    set.spawn(async move {
                        let active_route = srv
                            .active_route_id
                            .as_deref()
                            .and_then(|rid| srv.routes.iter().find(|r| r.id == rid))
                            .or_else(|| srv.routes.first());
                        let url = active_route
                            .map(|r| r.url.clone())
                            .filter(|u| !u.is_empty())
                            .unwrap_or_else(|| srv.url.clone());
                        let proxy_url = active_route.and_then(|r| r.proxy_url.clone());
                        let accept_invalid_certs = active_route
                            .map(|r| r.accept_invalid_certs)
                            .unwrap_or(false);

                        let started = std::time::Instant::now();
                        let res = tokio::time::timeout(Duration::from_secs(4), async {
                            let client = EmbyClient::with_options(
                                &url,
                                id_clone,
                                ClientTransportOptions {
                                    proxy_url,
                                    accept_invalid_certs,
                                },
                            )
                            .map_err(|e| e.to_string())?;
                            let (info, _caps) =
                                client.probe_server().await.map_err(|e| e.to_string())?;
                            let elapsed_ms = started.elapsed().as_millis() as u64;

                            let counts = if let (Some(tok), Some(uid)) =
                                (srv.access_token.clone(), srv.user_id.clone())
                            {
                                client.set_credentials(tok, uid);
                                client.item_counts().await.ok()
                            } else {
                                None
                            };
                            Ok::<_, String>((elapsed_ms, info.version, counts))
                        })
                        .await;

                        let payload = match res {
                            Ok(Ok((latency_ms, version, counts))) => json!({
                                "server_id": srv.id,
                                "online": true,
                                "latency_ms": latency_ms,
                                "version": version,
                                "movie_count": counts.as_ref().map(|c| c.movie_count),
                                "series_count": counts.as_ref().map(|c| c.series_count),
                                "episode_count": counts.as_ref().map(|c| c.episode_count),
                            }),
                            Ok(Err(err)) => json!({
                                "server_id": srv.id,
                                "online": false,
                                "latency_ms": null,
                                "error": err,
                            }),
                            Err(_) => json!({
                                "server_id": srv.id,
                                "online": false,
                                "latency_ms": null,
                                "error": "连接超时",
                            }),
                        };
                        (srv.id, payload)
                    });
                }

                let mut map = serde_json::Map::new();
                while let Some(joined) = set.join_next().await {
                    if let Ok((sid, val)) = joined {
                        map.insert(sid, val);
                    }
                }
                Ok(Value::Object(map))
            }

            "switch_server_route" => {
                let server_id = str_param(&params, "server_id")?;
                let route_id = str_param(&params, "route_id")?;
                let mut profile = self
                    .store
                    .get_server(&server_id)
                    .map_err(|e| e.to_string())?
                    .ok_or_else(|| format!("server not found: {server_id}"))?;
                let route = profile
                    .routes
                    .iter()
                    .find(|r| r.id == route_id)
                    .cloned()
                    .ok_or_else(|| format!("route not found: {route_id}"))?;
                let token = profile
                    .access_token
                    .clone()
                    .ok_or_else(|| "server has no saved token".to_string())?;
                let user_id = profile
                    .user_id
                    .clone()
                    .ok_or_else(|| "server has no saved user_id".to_string())?;

                let eff_route_proxy = route
                    .proxy_url
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                let _ = self
                    .proxy
                    .configure_transport(eff_route_proxy.as_deref(), route.accept_invalid_certs);
                let identity = self.identity.lock().clone();
                let client = EmbyClient::with_options(
                    &route.url,
                    identity,
                    ClientTransportOptions {
                        proxy_url: eff_route_proxy,
                        accept_invalid_certs: route.accept_invalid_certs,
                    },
                )
                .map_err(|e| e.to_string())?;
                let (info, caps) = client.probe_server().await.map_err(|e| e.to_string())?;
                client.set_credentials(token, user_id);
                let user = client.current_user().await.map_err(|e| e.to_string())?;

                profile.url = route.url.clone();
                profile.active_route_id = Some(route.id.clone());
                profile.last_connected_at = chrono::Utc::now().timestamp();
                let _ = self.store.upsert_server(&profile);
                let _ = self.store.set_setting("last_active_server_id", &server_id);

                let hdrs = client.auth_headers();
                self.proxy
                    .set_image_upstream(client.base_url().to_string(), hdrs.clone());
                self.proxy.register_server_image_upstream(
                    profile.id.clone(),
                    client.base_url().to_string(),
                    hdrs,
                );
                *self.client.lock() = Some(client.clone());
                self.start_websocket(client);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "user": user,
                    "profile": profile,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "connect_server" => {
                let url = str_param(&params, "url")?;
                if let Some(dev_name) = params.get("device_name").and_then(Value::as_str) {
                    self.identity.lock().device_name = dev_name.to_string();
                }
                let raw_proxy = params
                    .get("proxy_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let proxy_url = raw_proxy.map(ToString::to_string);
                let accept_invalid_certs = params
                    .get("accept_invalid_certs")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let _ = self
                    .proxy
                    .configure_transport(proxy_url.as_deref(), accept_invalid_certs);

                let identity = self.identity.lock().clone();
                let client = EmbyClient::with_options(
                    &url,
                    identity,
                    ClientTransportOptions {
                        proxy_url,
                        accept_invalid_certs,
                    },
                )
                .map_err(|e| e.to_string())?;
                let (info, caps) = client.probe_server().await.map_err(|e| e.to_string())?;
                self.proxy
                    .set_image_upstream(client.base_url().to_string(), client.auth_headers());
                *self.client.lock() = Some(client);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "login" => {
                let client = self.require_client()?;
                let username = str_param(&params, "username")?;
                let password = params.get("password").and_then(Value::as_str).unwrap_or("");
                let auth = client
                    .authenticate_by_name(&username, password)
                    .await
                    .map_err(|e| e.to_string())?;
                let caps = client.capabilities();
                let server_id = if !caps.server_id.is_empty() {
                    caps.server_id.clone()
                } else {
                    auth.server_id
                        .clone()
                        .unwrap_or_else(|| client.base_url().to_string())
                };
                let is_admin = auth
                    .user
                    .policy
                    .as_ref()
                    .map(|p| p.is_administrator)
                    .unwrap_or(false);
                let existing = self.store.get_server(&server_id).ok().flatten();
                let current_url = client.base_url().to_string();
                let mut routes = existing
                    .as_ref()
                    .map(|e| e.routes.clone())
                    .unwrap_or_default();
                let active_route_id = if let Some(found) = routes
                    .iter()
                    .find(|r| r.url.trim_end_matches('/') == current_url.trim_end_matches('/'))
                {
                    Some(found.id.clone())
                } else {
                    let rid = if routes.is_empty() {
                        "default".to_string()
                    } else {
                        uuid::Uuid::new_v4().simple().to_string()
                    };
                    let rname = if routes.is_empty() {
                        "默认线路".to_string()
                    } else {
                        format!("线路 {}", routes.len() + 1)
                    };
                    routes.push(ServerRoute {
                        id: rid.clone(),
                        name: rname,
                        url: current_url.clone(),
                        proxy_url: None,
                        accept_invalid_certs: false,
                    });
                    Some(rid)
                };

                let _ = self.store.upsert_server(&ServerProfile {
                    id: server_id.clone(),
                    name: if caps.server_name.is_empty() {
                        current_url.clone()
                    } else {
                        caps.server_name.clone()
                    },
                    url: current_url.clone(),
                    dialect: caps.dialect.as_str().to_string(),
                    user_id: Some(auth.user.id.clone()),
                    username: Some(auth.user.name.clone()),
                    access_token: Some(auth.access_token.clone()),
                    is_admin,
                    last_connected_at: chrono::Utc::now().timestamp(),
                    routes,
                    active_route_id,
                });
                let hdrs = client.auth_headers();
                self.proxy
                    .set_image_upstream(current_url.clone(), hdrs.clone());
                self.proxy
                    .register_server_image_upstream(server_id.clone(), current_url, hdrs);
                let _ = self.store.set_setting("last_active_server_id", &server_id);
                self.start_websocket(client.clone());
                Ok(json!({
                    "auth": auth,
                    "capabilities": caps,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "restore_session" => {
                let url = str_param(&params, "url")?;
                let explicit_server_id = params
                    .get("server_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                let token = str_param(&params, "access_token")?;
                let user_id = str_param(&params, "user_id")?;
                let raw_proxy = params
                    .get("proxy_url")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let proxy_url = raw_proxy.map(ToString::to_string);
                let accept_invalid_certs = params
                    .get("accept_invalid_certs")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let _ = self
                    .proxy
                    .configure_transport(proxy_url.as_deref(), accept_invalid_certs);

                let identity = self.identity.lock().clone();
                let client = EmbyClient::with_options(
                    &url,
                    identity,
                    ClientTransportOptions {
                        proxy_url,
                        accept_invalid_certs,
                    },
                )
                .map_err(|e| e.to_string())?;
                client.set_credentials(token.clone(), user_id.clone());
                // Probe server capabilities AND validate current user in ONE single network RTT!
                let (probe_res, user_res) =
                    tokio::join!(client.probe_server(), client.current_user());
                let (info, caps) = probe_res.map_err(|e| e.to_string())?;
                let user = user_res.map_err(|e| e.to_string())?;

                // Update last_connected_at & last_active_server_id so next launch remembers this exact server
                let resolved_sid = explicit_server_id
                    .or_else(|| (!caps.server_id.is_empty()).then(|| caps.server_id.clone()));
                if let Some(ref sid) = resolved_sid {
                    let _ = self.store.set_setting("last_active_server_id", sid);
                    if let Ok(Some(mut saved)) = self.store.get_server(sid) {
                        saved.last_connected_at = chrono::Utc::now().timestamp();
                        saved.access_token = Some(token);
                        saved.user_id = Some(user_id);
                        saved.is_admin = user
                            .policy
                            .as_ref()
                            .map(|p| p.is_administrator)
                            .unwrap_or(saved.is_admin);
                        let _ = self.store.upsert_server(&saved);
                    }
                }

                let hdrs = client.auth_headers();
                self.proxy
                    .set_image_upstream(client.base_url().to_string(), hdrs.clone());
                if let Some(sid) = resolved_sid {
                    self.proxy.register_server_image_upstream(
                        sid,
                        client.base_url().to_string(),
                        hdrs,
                    );
                }
                *self.client.lock() = Some(client.clone());
                self.start_websocket(client);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "user": user,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "logout" => {
                let ws_opt = self.ws.lock().take();
                if let Some(mut ws) = ws_opt {
                    ws.stop().await;
                }
                let client_opt = self.client.lock().take();
                if let Some(client) = client_opt {
                    let _ = client.logout().await;
                }
                let _ = self.store.set_setting("last_active_server_id", &"");
                Ok(json!({"logged_out": true}))
            }

            "get_home" => {
                let client = self.require_client()?;
                let include_suggestions = params
                    .get("include_suggestions")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let include_favorites = params
                    .get("include_favorites")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);

                // Kick off `views` + `latest` pipeline concurrently with `resume`, `next_up`, `popular`,
                // `suggestions`, and `favorites` so `latest` NEVER waits for slower secondary rails!
                let views_and_latest_fut = async {
                    let views = client.views().await.map_err(|e| e.to_string())?;
                    let mut join_set = tokio::task::JoinSet::new();
                    for (idx, lib) in views.items.iter().take(8).cloned().enumerate() {
                        let c = client.clone();
                        join_set.spawn(async move {
                            let items = c.latest(Some(&lib.id), 16).await.unwrap_or_default();
                            (idx, lib, items)
                        });
                    }
                    let mut fetched_latest = Vec::new();
                    while let Some(res) = join_set.join_next().await {
                        if let Ok(tuple) = res {
                            fetched_latest.push(tuple);
                        }
                    }
                    fetched_latest.sort_by_key(|(idx, _, _)| *idx);
                    let latest_by_library: Vec<Value> = fetched_latest
                        .into_iter()
                        .filter(|(_, _, items)| !items.is_empty())
                        .map(|(_, lib, items)| {
                            json!({
                                "library": lib,
                                "items": items,
                            })
                        })
                        .collect();
                    Ok::<_, String>((views.items, latest_by_library))
                };

                let suggestions_fut = async {
                    if include_suggestions {
                        client.suggestions(16).await.unwrap_or_default().items
                    } else {
                        Vec::new()
                    }
                };
                let favorites_fut = async {
                    if include_favorites {
                        client.home_favorites(16).await.unwrap_or_default().items
                    } else {
                        Vec::new()
                    }
                };

                let (vl_r, resume_r, next_up_r, popular_r, suggestions, favorites) = tokio::join!(
                    views_and_latest_fut,
                    client.resume(20, None),
                    client.next_up(20, None),
                    client.popular(10),
                    suggestions_fut,
                    favorites_fut,
                );
                let (views_items, latest_by_library) = vl_r?;
                let resume = resume_r.unwrap_or_default();
                let next_up = next_up_r.unwrap_or_default();
                let popular = popular_r.unwrap_or_default();

                let out = json!({
                    "capabilities": client.capabilities(),
                    "views": views_items,
                    "popular": popular,
                    "resume": resume.items,
                    "next_up": next_up.items,
                    "suggestions": suggestions,
                    "favorites": favorites,
                    "latest_by_library": latest_by_library,
                });

                // Persist Home SWR snapshot keyed by server ID for 0ms instant Home render on next launch!
                let cache_sid = self
                    .store
                    .get_setting::<String>("last_active_server_id")
                    .ok()
                    .flatten()
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or_else(|| {
                        let cid = client.capabilities().server_id;
                        if cid.is_empty() {
                            client.base_url().to_string()
                        } else {
                            cid
                        }
                    });
                let _ = self
                    .store
                    .set_setting(&format!("home_cache_v1:{cache_sid}"), &out);

                Ok(out)
            }

            "get_items" => {
                let client = self.require_client()?;
                let query: ItemsQuery = serde_json::from_value(params).unwrap_or_default();
                let res = client.items(&query).await.map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_item" => {
                let client = self.require_client()?;
                let id = str_param(&params, "item_id")?;
                let (item_r, similar_r, segments_r) = tokio::join!(
                    client.item(&id),
                    client.similar(&id, 12),
                    client.media_segments(&id),
                );
                let mut item = item_r.map_err(|e| e.to_string())?;
                self.enrich_item_with_learned_tracks(&mut item);
                let similar = similar_r.unwrap_or_default();
                let segments = segments_r.unwrap_or_default();
                Ok(json!({
                    "item": item,
                    "similar": similar.items,
                    "segments": segments.items,
                }))
            }

            "get_seasons" => {
                let client = self.require_client()?;
                let series_id = str_param(&params, "series_id")?;
                let res = client
                    .seasons(&series_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_episodes" => {
                let client = self.require_client()?;
                let series_id = str_param(&params, "series_id")?;
                let season_id = params.get("season_id").and_then(Value::as_str);
                let start_index = params.get("start_index").and_then(Value::as_u64);
                let limit = params.get("limit").and_then(Value::as_u64);
                let mut res = client
                    .episodes(&series_id, season_id, start_index, limit)
                    .await
                    .map_err(|e| e.to_string())?;
                for ep in &mut res.items {
                    self.enrich_item_with_learned_tracks(ep);
                }
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_filters" => {
                let client = self.require_client()?;
                let parent_id = params.get("parent_id").and_then(Value::as_str);
                let res = client
                    .filters2(parent_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "search_hints" => {
                let client = self.require_client()?;
                let term = str_param(&params, "term")?;
                let types = params.get("include_item_types").and_then(Value::as_str);
                let limit = params.get("limit").and_then(Value::as_u64).unwrap_or(30) as u32;
                let res = client
                    .search_hints(&term, types, limit)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "aggregated_search" => {
                let term = str_param(&params, "term")?;
                let limit = params.get("limit").and_then(Value::as_u64).unwrap_or(24) as u32;
                let saved = self.store.list_servers().unwrap_or_default();
                let identity = self.identity.lock().clone();
                let mut set = tokio::task::JoinSet::new();

                for srv in saved {
                    let (Some(token), Some(uid)) = (srv.access_token.clone(), srv.user_id.clone())
                    else {
                        continue;
                    };
                    let active_route = srv.active_route().cloned();
                    let route_url = active_route
                        .as_ref()
                        .map(|r| r.url.clone())
                        .unwrap_or_else(|| srv.url.clone());
                    let proxy_url = active_route.as_ref().and_then(|r| r.proxy_url.clone());
                    let accept_invalid = active_route
                        .as_ref()
                        .map(|r| r.accept_invalid_certs)
                        .unwrap_or(false);

                    let hdrs = identity.build_headers(Some(&token));
                    self.proxy.register_server_image_upstream(
                        srv.id.clone(),
                        route_url.clone(),
                        hdrs,
                    );

                    let id_clone = identity.clone();
                    let term_clone = term.clone();
                    set.spawn(async move {
                        let res = tokio::time::timeout(Duration::from_secs(6), async {
                            let client = EmbyClient::with_options(
                                &route_url,
                                id_clone,
                                ClientTransportOptions {
                                    proxy_url,
                                    accept_invalid_certs: accept_invalid,
                                },
                            )
                            .map_err(|e| e.to_string())?;
                            client.set_credentials(token, uid);
                            client
                                .search_hints(&term_clone, None, limit)
                                .await
                                .map_err(|e| e.to_string())
                        })
                        .await;
                        (srv, res)
                    });
                }

                let mut items_out = Vec::new();
                let mut servers_out = Vec::new();
                while let Some(joined) = set.join_next().await {
                    let Ok((srv, res)) = joined else { continue };
                    match res {
                        Ok(Ok(hints)) => {
                            let count = hints.search_hints.len();
                            servers_out.push(json!({
                                "server_id": srv.id,
                                "server_name": srv.name,
                                "count": count,
                                "ok": true,
                            }));
                            for h in hints.search_hints {
                                let item_id = if !h.item_id.is_empty() {
                                    h.item_id
                                } else {
                                    h.id
                                };
                                items_out.push(json!({
                                    "server_id": srv.id,
                                    "server_name": srv.name,
                                    "id": item_id,
                                    "name": h.name,
                                    "type": h.item_type,
                                    "production_year": h.production_year,
                                    "primary_image_tag": h.primary_image_tag,
                                    "series": h.series,
                                    "run_time_ticks": h.run_time_ticks,
                                }));
                            }
                        }
                        _ => {
                            servers_out.push(json!({
                                "server_id": srv.id,
                                "server_name": srv.name,
                                "count": 0,
                                "ok": false,
                            }));
                        }
                    }
                }

                // Fallback to currently connected client if no saved servers were queried
                if servers_out.is_empty() {
                    if let Ok(client) = self.require_client() {
                        if let Ok(hints) = client.search_hints(&term, None, limit).await {
                            let caps = client.capabilities();
                            let sid = if caps.server_id.is_empty() {
                                "active".to_string()
                            } else {
                                caps.server_id.clone()
                            };
                            let sname = if caps.server_name.is_empty() {
                                "当前服务器".to_string()
                            } else {
                                caps.server_name.clone()
                            };
                            servers_out.push(json!({
                                "server_id": sid,
                                "server_name": sname,
                                "count": hints.search_hints.len(),
                                "ok": true,
                            }));
                            for h in hints.search_hints {
                                let item_id = if !h.item_id.is_empty() {
                                    h.item_id
                                } else {
                                    h.id
                                };
                                items_out.push(json!({
                                    "server_id": sid,
                                    "server_name": sname,
                                    "id": item_id,
                                    "name": h.name,
                                    "type": h.item_type,
                                    "production_year": h.production_year,
                                    "primary_image_tag": h.primary_image_tag,
                                    "series": h.series,
                                    "run_time_ticks": h.run_time_ticks,
                                }));
                            }
                        }
                    }
                }

                Ok(json!({
                    "servers": servers_out,
                    "items": items_out,
                    "proxy_addr": self.proxy.listen_addr().to_string(),
                }))
            }

            "get_person_credits" => {
                let client = self.require_client()?;
                let person_id = str_param(&params, "person_id")?;
                let res = client
                    .person_credits(&person_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "set_favorite" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let favorite = params
                    .get("favorite")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let res = client
                    .set_favorite(&item_id, favorite)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "set_played" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let played = params
                    .get("played")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let res = client
                    .set_played(&item_id, played)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "hide_from_resume" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let hide = params.get("hide").and_then(Value::as_bool).unwrap_or(true);
                let res = client
                    .hide_from_resume(&item_id, hide)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "list_playlists" => {
                let client = self.require_client()?;
                let res = client.playlists().await.map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "get_playlist_items" => {
                let client = self.require_client()?;
                let playlist_id = str_param(&params, "playlist_id")?;
                let res = client
                    .playlist_items(&playlist_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "create_playlist" => {
                let client = self.require_client()?;
                let name = str_param(&params, "name")?;
                let item_ids: Vec<String> = params
                    .get("item_ids")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(ToString::to_string))
                            .collect()
                    })
                    .unwrap_or_default();
                let res = client
                    .create_playlist(&name, &item_ids)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(serde_json::to_value(res).unwrap())
            }

            "add_to_playlist" => {
                let client = self.require_client()?;
                let playlist_id = str_param(&params, "playlist_id")?;
                let item_ids: Vec<String> = params
                    .get("item_ids")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(ToString::to_string))
                            .collect()
                    })
                    .unwrap_or_default();
                client
                    .add_to_playlist(&playlist_id, &item_ids)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"added": true}))
            }

            "remove_from_playlist" => {
                let client = self.require_client()?;
                let playlist_id = str_param(&params, "playlist_id")?;
                let entry_ids: Vec<String> = params
                    .get("entry_ids")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(ToString::to_string))
                            .collect()
                    })
                    .unwrap_or_default();
                client
                    .remove_from_playlist(&playlist_id, &entry_ids)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"removed": true}))
            }

            "probe_media_source" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let media_source_id = params
                    .get("media_source_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty());

                let cache_key = format!(
                    "source_probe_v1:{}:{}",
                    item_id,
                    media_source_id.unwrap_or("default")
                );
                if let Ok(Some(cached)) = self.store.get_setting::<Value>(&cache_key) {
                    if cached
                        .get("media_source")
                        .and_then(|m| m.get("MediaStreams"))
                        .and_then(Value::as_array)
                        .map(|arr| {
                            arr.iter().any(|s| {
                                s.get("Type")
                                    .and_then(Value::as_str)
                                    .map(|t| {
                                        t.eq_ignore_ascii_case("Audio")
                                            || t.eq_ignore_ascii_case("Video")
                                    })
                                    .unwrap_or(false)
                            })
                        })
                        .unwrap_or(false)
                    {
                        return Ok(cached);
                    }
                }

                // 1. Ask server PlaybackInfo with EnableMediaProbe=true for this exact MediaSourceId
                let pb = client
                    .playback_info_with_probe(&item_id, media_source_id, None, None, true)
                    .await
                    .map_err(|e| e.to_string())?;
                let mut chosen = if let Some(target_id) = media_source_id {
                    pb.media_sources
                        .iter()
                        .find(|s| s.id == target_id)
                        .cloned()
                        .or_else(|| pb.media_sources.first().cloned())
                } else {
                    pb.media_sources.first().cloned()
                }
                .ok_or_else(|| "no media source returned".to_string())?;

                let has_embedded_av = chosen.media_streams.iter().any(|s| {
                    s.stream_type.eq_ignore_ascii_case("Audio")
                        || s.stream_type.eq_ignore_ascii_case("Video")
                });

                // 2. Fallback: if server still returned zero embedded AV streams (e.g. unprobed file or
                //    version with sidecar subtitles), read first 512 KiB via HTTP Range & parse container tracks!
                if !has_embedded_av {
                    if let Some(dsu) = chosen.direct_stream_url.clone() {
                        if let Ok(upstream_url) = client.resolve_media_url(&dsu) {
                            let uses_ticket =
                                vedro_protocol::auth::url_has_stream_ticket(upstream_url.as_str());
                            let headers = if uses_ticket {
                                let mut h = reqwest::header::HeaderMap::new();
                                if let Ok(ua) = reqwest::header::HeaderValue::from_str(
                                    &client.identity().user_agent(),
                                ) {
                                    h.insert(reqwest::header::USER_AGENT, ua);
                                }
                                h
                            } else {
                                client.auth_headers()
                            };
                            let (temp_id, _) = self.proxy.register_stream(
                                upstream_url.to_string(),
                                headers,
                                chosen.size,
                                chosen.container.as_deref().map(container_mime_type),
                            );
                            let header_bytes = self.proxy.read_range(&temp_id, 0, 512 * 1024).await;
                            self.proxy.unregister_stream(&temp_id);

                            if let Some(bytes) = header_bytes {
                                let tracks = vedro_stream::inspect_media_tracks(&bytes);
                                if !tracks.is_empty() {
                                    let base_idx = chosen
                                        .media_streams
                                        .iter()
                                        .map(|s| s.index + 1)
                                        .max()
                                        .unwrap_or(0)
                                        .max(0);
                                    for (offset, t) in tracks.into_iter().enumerate() {
                                        chosen.media_streams.push(vedro_protocol::MediaStream {
                                            index: base_idx + offset as i32,
                                            stream_type: t.stream_type,
                                            codec: Some(t.codec),
                                            language: t.language,
                                            title: t.title,
                                            display_title: Some(t.display_title),
                                            is_default: t.is_default,
                                            is_forced: t.is_forced,
                                            is_external: false,
                                            is_text_subtitle_stream: t.is_text_subtitle,
                                            width: t.width,
                                            height: t.height,
                                            channels: t.channels,
                                            video_range: t.video_range,
                                            ..Default::default()
                                        });
                                    }
                                }
                            }
                        }
                    }
                }

                let out = json!({
                    "media_source": chosen,
                    "probed": true,
                });
                if chosen.media_streams.iter().any(|s| {
                    s.stream_type.eq_ignore_ascii_case("Audio")
                        || s.stream_type.eq_ignore_ascii_case("Video")
                }) {
                    let _ = self.store.set_setting(&cache_key, &out);
                }
                Ok(out)
            }

            "save_learned_tracks" => {
                let item_id = str_param(&params, "item_id")?;
                let media_source_id = params
                    .get("media_source_id")
                    .and_then(Value::as_str)
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or("default");
                let streams: Vec<MediaStream> = serde_json::from_value(
                    params.get("streams").cloned().unwrap_or_else(|| json!([])),
                )
                .map_err(|e| format!("invalid learned streams: {e}"))?;
                if !streams.is_empty() {
                    let learned_key = format!("learned_streams_v1:{item_id}:{media_source_id}");
                    let _ = self.store.set_setting(&learned_key, &streams);
                }
                Ok(json!({"saved": true}))
            }

            "prepare_playback" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let media_source_id = params.get("media_source_id").and_then(Value::as_str);
                let audio_idx = params
                    .get("audio_stream_index")
                    .and_then(Value::as_i64)
                    .map(|v| v as i32);
                let sub_idx = params
                    .get("subtitle_stream_index")
                    .and_then(Value::as_i64)
                    .map(|v| v as i32);
                let inspect_header = params
                    .get("inspect_header")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);

                let pb = client
                    .playback_info(&item_id, media_source_id, audio_idx, sub_idx)
                    .await
                    .map_err(|e| e.to_string())?;

                let chosen = pb
                    .media_sources
                    .first()
                    .cloned()
                    .ok_or_else(|| "no media source returned".to_string())?;

                let upstream_url = if let Some(dsu) = &chosen.direct_stream_url {
                    client.resolve_media_url(dsu).map_err(|e| e.to_string())?
                } else {
                    client
                        .build_fallback_video_url(
                            &item_id,
                            &chosen.id,
                            chosen.container.as_deref(),
                            &pb.play_session_id,
                        )
                        .map_err(|e| e.to_string())?
                };
                let uses_ticket =
                    vedro_protocol::auth::url_has_stream_ticket(upstream_url.as_str());

                // Clean up previous stream registration if any
                if let Some(prev) = self.active_session.lock().take() {
                    self.proxy.unregister_stream(&prev.stream_id);
                }

                let headers = if uses_ticket {
                    // When embygo issues a StreamTicket, media requests don't need long-lived tokens
                    let mut h = reqwest::header::HeaderMap::new();
                    if let Ok(ua) =
                        reqwest::header::HeaderValue::from_str(&client.identity().user_agent())
                    {
                        h.insert(reqwest::header::USER_AGENT, ua);
                    }
                    h
                } else {
                    client.auth_headers()
                };

                let (stream_id, proxy_url) = self.proxy.register_stream(
                    upstream_url.to_string(),
                    headers,
                    chosen.size,
                    chosen.container.as_deref().map(container_mime_type),
                );

                // Inspect the first 256 KiB via our proxy (reuses chunk 0 cache — 0 extra upstream requests!)
                // to detect Dolby Vision / Atmos AND cache embedded track table naturally while playing!
                let inspected = if inspect_header {
                    self.proxy
                        .read_range(&stream_id, 0, 256 * 1024)
                        .await
                        .map(|bytes| {
                            let has_av = chosen.media_streams.iter().any(|s| {
                                s.stream_type.eq_ignore_ascii_case("Audio")
                                    || s.stream_type.eq_ignore_ascii_case("Video")
                            });
                            if !has_av {
                                let tracks = vedro_stream::inspect_media_tracks(&bytes);
                                if !tracks.is_empty() {
                                    let learned: Vec<MediaStream> = tracks
                                        .into_iter()
                                        .enumerate()
                                        .map(|(idx, t)| MediaStream {
                                            index: idx as i32,
                                            stream_type: t.stream_type,
                                            codec: Some(t.codec),
                                            language: t.language,
                                            title: t.title,
                                            display_title: Some(t.display_title),
                                            is_default: t.is_default,
                                            is_forced: t.is_forced,
                                            is_external: false,
                                            is_text_subtitle_stream: t.is_text_subtitle,
                                            width: t.width,
                                            height: t.height,
                                            channels: t.channels,
                                            video_range: t.video_range,
                                            ..Default::default()
                                        })
                                        .collect();
                                    let src_id = if chosen.id.is_empty() {
                                        "default"
                                    } else {
                                        chosen.id.as_str()
                                    };
                                    let learned_key =
                                        format!("learned_streams_v1:{item_id}:{src_id}");
                                    let _ = self.store.set_setting(&learned_key, &learned);
                                }
                            }
                            inspect_media_header(&bytes)
                        })
                } else {
                    None
                };

                let cfg = self.playback_config.lock().clone();
                let hdr_fmt = inspected
                    .as_ref()
                    .and_then(|i| i.hdr_format.clone())
                    .unwrap_or(vedro_stream::HdrFormat::Sdr);
                let spatial = inspected.as_ref().and_then(|i| i.spatial_audio.clone());

                let hdr_decision = vedro_playback::resolve_hdr_pipeline(
                    cfg.platform,
                    &cfg.display,
                    &hdr_fmt,
                    cfg.prefer_native_dolby_vision,
                    cfg.tone_mapping,
                );
                let audio_decision = vedro_playback::resolve_audio_routing(
                    cfg.platform,
                    cfg.audio_mode,
                    spatial.as_ref(),
                    cfg.night_mode,
                    cfg.dialogue_boost,
                );
                let mpv_options = cfg.build_mpv_options(&hdr_fmt, spatial.as_ref());

                let external_subtitles: Vec<ExternalSubtitle> = chosen
                    .media_streams
                    .iter()
                    .filter(|s| {
                        s.stream_type.eq_ignore_ascii_case("Subtitle") && s.delivery_url.is_some()
                    })
                    .filter_map(|s| {
                        let resolved = client.resolve_media_url(s.delivery_url.as_deref()?).ok()?;
                        Some(ExternalSubtitle {
                            index: s.index,
                            language: s.language.clone(),
                            title: s
                                .display_title
                                .clone()
                                .or_else(|| s.title.clone())
                                .or_else(|| s.language.clone())
                                .unwrap_or_else(|| format!("Subtitle #{}", s.index)),
                            codec: s.codec.clone().unwrap_or_else(|| "srt".to_string()),
                            is_default: s.is_default,
                            is_forced: s.is_forced,
                            url: resolved.to_string(),
                        })
                    })
                    .collect();

                let badges = chosen.infer_badges();

                *self.active_session.lock() = Some(ActivePlaybackSession {
                    item_id: item_id.clone(),
                    media_source_id: chosen.id.clone(),
                    play_session_id: pb.play_session_id.clone(),
                    stream_id: stream_id.clone(),
                    run_time_ticks: chosen.run_time_ticks,
                    audio_stream_index: chosen.default_audio_stream_index,
                    subtitle_stream_index: chosen.default_subtitle_stream_index,
                });

                let prepared = PreparedPlayback {
                    item_id,
                    media_source_id: chosen.id.clone(),
                    play_session_id: pb.play_session_id,
                    stream_id,
                    proxy_url,
                    upstream_url: upstream_url.to_string(),
                    uses_stream_ticket: uses_ticket,
                    media_source: chosen,
                    badges,
                    inspected,
                    hdr_decision,
                    audio_decision,
                    mpv_options,
                    external_subtitles,
                    all_sources: pb.media_sources,
                };
                Ok(serde_json::to_value(prepared).unwrap())
            }

            "refresh_stream_ticket" => {
                let client = self.require_client()?;
                let active = self
                    .active_session
                    .lock()
                    .as_ref()
                    .map(|s| {
                        (
                            s.item_id.clone(),
                            s.media_source_id.clone(),
                            s.stream_id.clone(),
                        )
                    })
                    .ok_or_else(|| "no active playback session".to_string())?;
                let pb = client
                    .playback_info(&active.0, Some(&active.1), None, None)
                    .await
                    .map_err(|e| e.to_string())?;
                let src = pb
                    .media_sources
                    .first()
                    .ok_or_else(|| "no media source on refresh".to_string())?;
                let new_url = src
                    .direct_stream_url
                    .as_deref()
                    .ok_or_else(|| "no DirectStreamUrl on refresh".to_string())?;
                let resolved = client
                    .resolve_media_url(new_url)
                    .map_err(|e| e.to_string())?;
                let swapped = self
                    .proxy
                    .update_upstream_url(&active.2, resolved.to_string(), None);
                Ok(json!({
                    "swapped": swapped,
                    "play_session_id": pb.play_session_id,
                }))
            }

            "player_start" => {
                let url = str_param(&params, "url")?;
                let start_secs = params.get("start_secs").and_then(Value::as_f64);
                let headless = params.get("headless").and_then(Value::as_bool);
                let wid = params.get("wid").and_then(Value::as_i64);
                let inspected: Option<InspectedMedia> = params
                    .get("inspected")
                    .and_then(|v| serde_json::from_value(v.clone()).ok());

                let eng = self.ensure_engine(headless)?;
                if let Some(w) = wid {
                    let _ = eng.attach_window_id(w);
                }
                let (hdr_dec, audio_dec) = eng
                    .load_media(&url, start_secs, inspected.as_ref())
                    .map_err(|e| e.to_string())?;
                let _ = eng.set_paused(false);
                Ok(json!({
                    "started": true,
                    "hdr_decision": hdr_dec,
                    "audio_decision": audio_dec,
                }))
            }

            "player_pause" => {
                let paused = params
                    .get("paused")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                let eng = self.ensure_engine(None)?;
                eng.set_paused(paused).map_err(|e| e.to_string())?;
                Ok(json!({"paused": paused}))
            }

            "player_toggle_pause" => {
                let eng = self.ensure_engine(None)?;
                eng.toggle_pause().map_err(|e| e.to_string())?;
                Ok(json!({"ok": true}))
            }

            "player_seek" => {
                let seconds = params
                    .get("seconds")
                    .and_then(Value::as_f64)
                    .ok_or("missing seconds")?;
                let relative = params
                    .get("relative")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let eng = self.ensure_engine(None)?;
                if relative {
                    eng.seek_relative(seconds).map_err(|e| e.to_string())?;
                } else {
                    eng.seek_absolute(seconds).map_err(|e| e.to_string())?;
                }
                Ok(json!({"seeked": seconds}))
            }

            "player_set_speed" => {
                let speed = params
                    .get("speed")
                    .and_then(Value::as_f64)
                    .ok_or("missing speed")?;
                let eng = self.ensure_engine(None)?;
                eng.set_speed(speed).map_err(|e| e.to_string())?;
                Ok(json!({"speed": speed}))
            }

            "player_set_volume" => {
                let volume = params
                    .get("volume")
                    .and_then(Value::as_f64)
                    .ok_or("missing volume")?;
                let eng = self.ensure_engine(None)?;
                eng.set_volume(volume).map_err(|e| e.to_string())?;
                Ok(json!({"volume": volume}))
            }

            "player_set_audio_track" => {
                let track_id = params
                    .get("track_id")
                    .and_then(Value::as_i64)
                    .ok_or("missing track_id")?;
                let eng = self.ensure_engine(None)?;
                eng.set_audio_track(track_id).map_err(|e| e.to_string())?;
                Ok(json!({"track_id": track_id}))
            }

            "player_set_subtitle_track" => {
                let track_id = params
                    .get("track_id")
                    .and_then(Value::as_i64)
                    .ok_or("missing track_id")?;
                let eng = self.ensure_engine(None)?;
                eng.set_subtitle_track(track_id)
                    .map_err(|e| e.to_string())?;
                Ok(json!({"track_id": track_id}))
            }

            "player_add_subtitle" => {
                let url = str_param(&params, "url")?;
                let title = params.get("title").and_then(Value::as_str);
                let lang = params.get("language").and_then(Value::as_str);
                let eng = self.ensure_engine(None)?;
                eng.add_external_subtitle(&url, title, lang)
                    .map_err(|e| e.to_string())?;
                Ok(json!({"added": true}))
            }

            "player_set_tone_mapping" => {
                let algo: ToneMappingAlgorithm =
                    serde_json::from_value(params.get("algorithm").cloned().unwrap_or(Value::Null))
                        .map_err(|e| format!("invalid algorithm: {e}"))?;
                self.playback_config.lock().tone_mapping = algo;
                if let Some(eng) = self.engine.lock().as_ref() {
                    let _ = eng.set_tone_mapping(algo);
                }
                Ok(json!({"tone_mapping": algo}))
            }

            "player_set_audio_mode" => {
                let mode: AudioOutputMode =
                    serde_json::from_value(params.get("mode").cloned().unwrap_or(Value::Null))
                        .map_err(|e| format!("invalid audio mode: {e}"))?;
                let night = params
                    .get("night_mode")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                let dialogue = params
                    .get("dialogue_boost")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);
                {
                    let mut cfg = self.playback_config.lock();
                    cfg.audio_mode = mode;
                    cfg.night_mode = night;
                    cfg.dialogue_boost = dialogue;
                }
                if let Some(eng) = self.engine.lock().as_ref() {
                    let dec = eng
                        .set_audio_mode(mode, night, dialogue)
                        .map_err(|e| e.to_string())?;
                    return Ok(serde_json::to_value(dec).unwrap());
                }
                Ok(json!({"audio_mode": mode}))
            }

            "player_stop" => {
                if let Some(eng) = self.engine.lock().as_ref() {
                    let _ = eng.stop();
                }
                if let Some(active) = self.active_session.lock().take() {
                    self.proxy.unregister_stream(&active.stream_id);
                }
                Ok(json!({"stopped": true}))
            }

            "player_stats" => {
                let playback = self
                    .engine
                    .lock()
                    .as_ref()
                    .map(|e| e.stats_snapshot())
                    .unwrap_or_default();
                let proxy = self.proxy.stats();
                Ok(serde_json::to_value(CombinedPlayerStats { playback, proxy }).unwrap())
            }

            "get_image_cache_stats" => {
                let stats = self.proxy.image_cache_stats();
                Ok(serde_json::to_value(stats).unwrap())
            }

            "clear_image_cache" => {
                let (removed_files, freed_bytes) = self.proxy.clear_image_cache();
                let after = self.proxy.image_cache_stats();
                Ok(json!({
                    "removed_files": removed_files,
                    "freed_bytes": freed_bytes,
                    "stats": after,
                }))
            }

            "report_playback_start" | "report_playback_progress" | "report_playback_stopped" => {
                let client = self.require_client()?;
                let position_ticks = params
                    .get("position_ticks")
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                let is_paused = params
                    .get("is_paused")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);

                let payload = if let Some(item_id) = params.get("item_id").and_then(Value::as_str) {
                    PlaybackProgressPayload {
                        item_id: item_id.to_string(),
                        media_source_id: params
                            .get("media_source_id")
                            .and_then(Value::as_str)
                            .map(ToString::to_string),
                        play_session_id: params
                            .get("play_session_id")
                            .and_then(Value::as_str)
                            .unwrap_or("")
                            .to_string(),
                        position_ticks,
                        run_time_ticks: params.get("run_time_ticks").and_then(Value::as_i64),
                        is_paused,
                        play_method: "DirectPlay".to_string(),
                        audio_stream_index: params
                            .get("audio_stream_index")
                            .and_then(Value::as_i64)
                            .map(|v| v as i32),
                        subtitle_stream_index: params
                            .get("subtitle_stream_index")
                            .and_then(Value::as_i64)
                            .map(|v| v as i32),
                        can_seek: Some(true),
                    }
                } else {
                    let active = self.active_session.lock();
                    let s = active
                        .as_ref()
                        .ok_or_else(|| "no active playback session".to_string())?;
                    PlaybackProgressPayload {
                        item_id: s.item_id.clone(),
                        media_source_id: Some(s.media_source_id.clone()),
                        play_session_id: s.play_session_id.clone(),
                        position_ticks,
                        run_time_ticks: params
                            .get("run_time_ticks")
                            .and_then(Value::as_i64)
                            .or(s.run_time_ticks),
                        is_paused,
                        play_method: "DirectPlay".to_string(),
                        audio_stream_index: s.audio_stream_index,
                        subtitle_stream_index: s.subtitle_stream_index,
                        can_seek: Some(true),
                    }
                };

                match method {
                    "report_playback_start" => client
                        .report_playback_start(&payload)
                        .await
                        .map_err(|e| e.to_string())?,
                    "report_playback_progress" => client
                        .report_playback_progress(&payload)
                        .await
                        .map_err(|e| e.to_string())?,
                    _ => client
                        .report_playback_stopped(&payload)
                        .await
                        .map_err(|e| e.to_string())?,
                }
                Ok(json!({"reported": true}))
            }

            "report_playback_ping" => {
                let client = self.require_client()?;
                let psid = params
                    .get("play_session_id")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
                    .or_else(|| {
                        self.active_session
                            .lock()
                            .as_ref()
                            .map(|s| s.play_session_id.clone())
                    })
                    .unwrap_or_default();
                client
                    .report_playback_ping(&psid)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"pinged": true}))
            }

            "get_embygo_admin_dashboard" => {
                let client = self.require_client()?;
                let (status, counts, sessions, devices, libraries, users, tasks, activity) = tokio::join!(
                    client.embygo_status(),
                    client.item_counts(),
                    client.sessions(false),
                    client.embygo_devices(None),
                    client.virtual_folders(),
                    client.query_users(),
                    client.scheduled_tasks(),
                    client.activity_log(30),
                );
                let all_sessions = sessions.unwrap_or_default();
                let playing_sessions: Vec<_> = all_sessions
                    .iter()
                    .filter(|s| s.now_playing_item.is_some())
                    .cloned()
                    .collect();
                Ok(json!({
                    "status": status.ok(),
                    "counts": counts.ok(),
                    "playing_sessions": playing_sessions,
                    "sessions": all_sessions,
                    "devices": devices.ok(),
                    "libraries": libraries.ok(),
                    "users": users.ok(),
                    "tasks": tasks.ok(),
                    "activity": activity.ok(),
                }))
            }

            "get_user_devices" => {
                let client = self.require_client()?;
                let explicit_uid = params
                    .get("user_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let raw = client
                    .embygo_devices(explicit_uid)
                    .await
                    .map_err(|e| e.to_string())?;
                let items = if let Some(arr) = raw.get("Items").and_then(Value::as_array) {
                    arr.clone()
                } else if let Some(arr) = raw.as_array() {
                    arr.clone()
                } else {
                    Vec::new()
                };
                let cur_dev = self.identity.lock().device_id.clone();
                Ok(json!({
                    "items": items,
                    "current_device_id": cur_dev,
                }))
            }

            "delete_user_device" => {
                let client = self.require_client()?;
                let device_id = str_param(&params, "device_id")?;
                let explicit_uid = params
                    .get("user_id")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string)
                    .or_else(|| client.user_id());
                client
                    .embygo_delete_device(explicit_uid.as_deref(), &device_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({
                    "deleted": device_id,
                    "user_id": explicit_uid,
                }))
            }

            "cancel_embygo_speedtest" => {
                self.speedtest_cancel
                    .store(true, std::sync::atomic::Ordering::SeqCst);
                Ok(json!({"cancelled": true}))
            }

            "run_embygo_speedtest" => {
                use futures_util::StreamExt;
                use std::sync::atomic::Ordering;

                let client = self.require_client()?;
                self.speedtest_cancel.store(false, Ordering::SeqCst);
                let start = client
                    .embygo_start_speedtest()
                    .await
                    .map_err(|e| e.to_string())?;

                let raw_ping = start
                    .get("PingUrl")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "服务器未返回 PingUrl".to_string())?;
                let raw_dl = start
                    .get("DownloadUrl")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "服务器未返回 DownloadUrl".to_string())?;
                let ping_url = client
                    .base_url()
                    .join(raw_ping)
                    .map_err(|e| format!("无效测速地址: {e}"))?;
                let dl_url = client
                    .base_url()
                    .join(raw_dl)
                    .map_err(|e| format!("无效测速下载流地址: {e}"))?;

                let route = start
                    .get("Route")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let duration_secs = start
                    .get("DurationSeconds")
                    .and_then(Value::as_u64)
                    .unwrap_or(8)
                    .clamp(1, 25);
                let account_limit_bps = start
                    .get("AccountBitrateLimit")
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                let remaining_hour = start
                    .get("RemainingThisHour")
                    .and_then(Value::as_i64)
                    .unwrap_or(-1);
                let remaining_today = start
                    .get("RemainingToday")
                    .and_then(Value::as_i64)
                    .unwrap_or(-1);

                // Build a clean ticket-only HTTP client honoring active route TLS/proxy settings
                let accept_invalid = client.transport_options().accept_invalid_certs;
                let eff_proxy = client
                    .transport_options()
                    .proxy_url
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);
                let mut builder = reqwest::Client::builder()
                    .danger_accept_invalid_certs(accept_invalid)
                    .connect_timeout(Duration::from_secs(5));
                if let Some(ref p) = eff_proxy {
                    if let Ok(px) = reqwest::Proxy::all(p) {
                        builder = builder.proxy(px);
                    }
                } else {
                    builder = builder.no_proxy();
                }
                let http = builder.build().map_err(|e| e.to_string())?;

                // 1. Five sequential pings (1st warms up TCP/TLS; median of 2..=5)
                let mut ping_samples_ms: Vec<f64> = Vec::new();
                let mut client_ip: Option<String> = None;
                for _ in 0..5 {
                    if self.speedtest_cancel.load(Ordering::SeqCst) {
                        return Err("测速已取消".into());
                    }
                    let t0 = std::time::Instant::now();
                    if let Ok(Ok(resp)) = tokio::time::timeout(
                        Duration::from_secs(5),
                        http.get(ping_url.clone()).send(),
                    )
                    .await
                    {
                        let elapsed = t0.elapsed().as_secs_f64() * 1000.0;
                        if resp.status().is_success() {
                            ping_samples_ms.push(elapsed);
                            if let Ok(body) = resp.json::<Value>().await {
                                if let Some(ip) = body
                                    .get("Ip")
                                    .and_then(Value::as_str)
                                    .filter(|s| !s.is_empty())
                                {
                                    client_ip = Some(ip.to_string());
                                }
                            }
                        }
                    }
                }
                let latency_ms: Option<f64> = {
                    let slice = if ping_samples_ms.len() > 1 {
                        &ping_samples_ms[1..]
                    } else {
                        &ping_samples_ms[..]
                    };
                    if slice.is_empty() {
                        None
                    } else {
                        let mut sorted = slice.to_vec();
                        sorted
                            .sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                        let mid = sorted.len() / 2;
                        Some(if sorted.len() % 2 == 1 {
                            sorted[mid]
                        } else {
                            (sorted[mid - 1] + sorted[mid]) / 2.0
                        })
                    }
                };

                {
                    let mut q = self.events.lock();
                    if q.len() >= 256 {
                        q.pop_front();
                    }
                    q.push_back(json!({
                        "source": "speedtest",
                        "phase": "ping",
                        "latency_ms": latency_ms,
                        "client_ip": client_ip,
                    }));
                }

                // 2. Timed download throughput measurement (excluding 1s warm-up if >= 2s)
                let mut samples: Vec<(u128, u64)> = Vec::new();
                let mut total_bytes: u64 = 0;
                let mut first_byte_at: Option<std::time::Instant> = None;
                let mut last_emit_ms: u128 = 0;
                let dl_deadline = tokio::time::Instant::now() + Duration::from_secs(duration_secs);

                let compute_mbps = |pts: &[(u128, u64)]| -> Option<f64> {
                    if pts.len() < 2 {
                        return None;
                    }
                    let first = pts[0];
                    let last = *pts.last().unwrap();
                    let mut warm = first;
                    if last.0.saturating_sub(first.0) >= 2000 {
                        if let Some(hit) = pts.iter().find(|s| s.0.saturating_sub(first.0) >= 1000)
                        {
                            warm = *hit;
                        }
                    }
                    let secs = (last.0.saturating_sub(warm.0)) as f64 / 1000.0;
                    if secs <= 0.0 {
                        return None;
                    }
                    let mbps = ((last.1.saturating_sub(warm.1)) as f64 * 8.0) / secs / 1e6;
                    (mbps.is_finite() && mbps >= 0.0).then_some(mbps)
                };

                let resp = tokio::time::timeout_at(dl_deadline, http.get(dl_url).send())
                    .await
                    .map_err(|_| "测速下载流连接超时".to_string())?
                    .map_err(|e| format!("测速连接失败: {e}"))?;
                if !resp.status().is_success() {
                    return Err(format!("测速响应异常: HTTP {}", resp.status().as_u16()));
                }
                let mut stream = resp.bytes_stream();
                let transfer_epoch = std::time::Instant::now();
                loop {
                    if self.speedtest_cancel.load(Ordering::SeqCst) {
                        return Err("测速已取消".into());
                    }
                    match tokio::time::timeout_at(dl_deadline, stream.next()).await {
                        Ok(Some(Ok(chunk))) => {
                            if !chunk.is_empty() {
                                let now = std::time::Instant::now();
                                let t_ms = transfer_epoch.elapsed().as_millis();
                                if first_byte_at.is_none() {
                                    first_byte_at = Some(now);
                                }
                                total_bytes += chunk.len() as u64;
                                samples.push((t_ms, total_bytes));
                                if t_ms.saturating_sub(last_emit_ms) >= 250 {
                                    last_emit_ms = t_ms;
                                    let live = compute_mbps(&samples).or_else(|| {
                                        let fb = first_byte_at?;
                                        let dt = now.duration_since(fb).as_secs_f64();
                                        (dt > 0.02).then_some((total_bytes as f64 * 8.0) / dt / 1e6)
                                    });
                                    if let Some(mbps) = live {
                                        let mut q = self.events.lock();
                                        if q.len() >= 256 {
                                            q.pop_front();
                                        }
                                        q.push_back(json!({
                                            "source": "speedtest",
                                            "phase": "download",
                                            "live_mbps": mbps,
                                        }));
                                    }
                                }
                            }
                        }
                        Ok(Some(Err(e))) => {
                            if samples.len() < 2 {
                                return Err(format!("测速读取中断: {e}"));
                            }
                            break;
                        }
                        Ok(None) | Err(_) => break,
                    }
                }

                let measured_mbps = compute_mbps(&samples).or_else(|| {
                    let fb = first_byte_at?;
                    let dt = fb.elapsed().as_secs_f64();
                    (total_bytes > 0 && dt > 0.01).then_some((total_bytes as f64 * 8.0) / dt / 1e6)
                });
                let effective_mbps = measured_mbps.map(|m| {
                    if account_limit_bps > 0 {
                        m.min(account_limit_bps as f64 / 1e6)
                    } else {
                        m
                    }
                });

                Ok(json!({
                    "route": route,
                    "latency_ms": latency_ms,
                    "client_ip": client_ip,
                    "measured_mbps": measured_mbps,
                    "account_limit_bps": account_limit_bps,
                    "effective_mbps": effective_mbps,
                    "remaining_this_hour": remaining_hour,
                    "remaining_today": remaining_today,
                }))
            }

            "trigger_library_refresh" => {
                let client = self.require_client()?;
                client
                    .trigger_library_refresh()
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"refresh_started": true}))
            }

            "admin_end_session" => {
                let client = self.require_client()?;
                let session_id = str_param(&params, "session_id")?;
                client
                    .end_session(&session_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"ended": session_id}))
            }

            "admin_create_user" => {
                let client = self.require_client()?;
                let name = str_param(&params, "name")?;
                let password = params.get("password").and_then(Value::as_str).unwrap_or("");
                let user = client
                    .create_user(&name, password)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(user)
            }

            "admin_set_user_policy" => {
                let client = self.require_client()?;
                let user_id = str_param(&params, "user_id")?;
                let policy = params.get("policy").cloned().unwrap_or_else(|| json!({}));
                client
                    .set_user_policy(&user_id, policy)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"updated": user_id}))
            }

            "admin_delete_user" => {
                let client = self.require_client()?;
                let user_id = str_param(&params, "user_id")?;
                client
                    .delete_user(&user_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"deleted": user_id}))
            }

            "admin_run_task" => {
                let client = self.require_client()?;
                let key = str_param(&params, "key")?;
                client
                    .run_scheduled_task(&key)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"started": key}))
            }

            "get_me_quota" => {
                let client = self.require_client()?;
                let quota = client.me_quota().await.map_err(|e| e.to_string())?;
                Ok(quota.unwrap_or(Value::Null))
            }

            "prepare_download" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let media_source_id = params.get("media_source_id").and_then(Value::as_str);
                let caps = client.capabilities();

                // On embygo, mint a long-lived StreamTicket via `external_play_info` (just like embygo Web)
                // so large downloads never expire mid-transfer and cross-origin 302 redirects never need tokens.
                let pb = if caps.is_embygo() {
                    client
                        .external_play_info(&item_id, media_source_id, Some("vedro-download"))
                        .await
                        .map_err(|e| e.to_string())?
                } else {
                    client
                        .playback_info(&item_id, media_source_id, None, None)
                        .await
                        .map_err(|e| e.to_string())?
                };

                let chosen = media_source_id
                    .and_then(|sid| pb.media_sources.iter().find(|s| s.id == sid))
                    .or_else(|| pb.media_sources.first())
                    .cloned()
                    .ok_or_else(|| "未找到可下载的媒体源".to_string())?;

                // Extract StreamTicket from DirectStreamUrl if issued by embygo
                let stream_ticket = chosen.direct_stream_url.as_deref().and_then(|dsu| {
                    client.resolve_media_url(dsu).ok().and_then(|u| {
                        u.query_pairs()
                            .find(|(k, _)| k == "StreamTicket")
                            .map(|(_, v)| v.into_owned())
                            .filter(|v| !v.is_empty())
                    })
                });

                let download_url = client
                    .build_download_url(&item_id, Some(&chosen.id), stream_ticket.as_deref())
                    .map_err(|e| e.to_string())?;

                let uses_ticket = stream_ticket.is_some();
                let mut header_map = serde_json::Map::new();
                header_map.insert(
                    "User-Agent".to_string(),
                    Value::String(client.identity().user_agent()),
                );
                if !uses_ticket {
                    for (k, v) in client.auth_headers().iter() {
                        if let Ok(val) = v.to_str() {
                            header_map
                                .insert(k.as_str().to_string(), Value::String(val.to_string()));
                        }
                    }
                }

                let basename = chosen
                    .path
                    .as_deref()
                    .and_then(|p| p.rsplit(['/', '\\']).next())
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToString::to_string);

                let transport = client.transport_options();
                Ok(json!({
                    "url": download_url.to_string(),
                    "headers": header_map,
                    "uses_stream_ticket": uses_ticket,
                    "media_source_id": chosen.id,
                    "container": chosen.container,
                    "size": chosen.size,
                    "filename": basename,
                    "proxy_url": transport.proxy_url,
                    "accept_invalid_certs": transport.accept_invalid_certs,
                }))
            }

            "admin_user_detail" => {
                let client = self.require_client()?;
                let user_id = str_param(&params, "user_id")?;
                client
                    .admin_user_detail(&user_id)
                    .await
                    .map_err(|e| e.to_string())
            }

            "admin_adjust_download_pack" => {
                let client = self.require_client()?;
                let user_id = str_param(&params, "user_id")?;
                let bytes = params
                    .get("bytes")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| "missing required integer parameter `bytes`".to_string())?;
                let note = params.get("note").and_then(Value::as_str);
                client
                    .admin_adjust_download_pack(&user_id, bytes, note)
                    .await
                    .map_err(|e| e.to_string())
            }

            "admin_set_monthly_download_quota" => {
                let client = self.require_client()?;
                let user_id = str_param(&params, "user_id")?;
                let monthly_bytes = params.get("monthly_bytes").and_then(Value::as_i64);
                client
                    .admin_set_monthly_download_quota(&user_id, monthly_bytes)
                    .await
                    .map_err(|e| e.to_string())
            }

            "admin_download_quota_events" => {
                let client = self.require_client()?;
                let user_id = str_param(&params, "user_id")?;
                let limit = params.get("limit").and_then(Value::as_u64).unwrap_or(20) as u32;
                client
                    .admin_download_quota_events(&user_id, limit)
                    .await
                    .map_err(|e| e.to_string())
            }

            "admin_set_library_covers" => {
                let client = self.require_client()?;
                let id = str_param(&params, "id")?;
                let enabled = params
                    .get("enabled")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                client
                    .set_library_generate_covers(&id, enabled)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({"updated": id, "enabled": enabled}))
            }

            "ai_translate" => {
                let base_url = str_param(&params, "base_url")?;
                let api_key = params.get("api_key").and_then(Value::as_str).unwrap_or("");
                let is_bilibili_index = base_url
                    .to_ascii_lowercase()
                    .contains("index-translate.bilibili.com")
                    || params
                        .get("model")
                        .and_then(Value::as_str)
                        .map(|m| m.to_ascii_lowercase().starts_with("index-translate"))
                        .unwrap_or(false);
                let model = params
                    .get("model")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or(if is_bilibili_index {
                        "Index-Translate-35B-A3B"
                    } else {
                        "gpt-4o-mini"
                    });
                let text = str_param(&params, "text")?;
                let target_lang = params
                    .get("target_lang")
                    .and_then(Value::as_str)
                    .unwrap_or("简体中文");
                // Bilibili Index-Translate checks client IP: always default to user's direct IP (`no_proxy`)
                // so it never exits via datacenter proxies and NEVER touches the media server!
                let direct_ip = params
                    .get("direct_ip")
                    .and_then(Value::as_bool)
                    .unwrap_or(is_bilibili_index);

                let endpoint = format!("{}/chat/completions", base_url.trim_end_matches('/'));
                let mut builder = reqwest::Client::builder().timeout(Duration::from_secs(30));
                if direct_ip {
                    builder = builder.no_proxy();
                }
                let http = builder.build().map_err(|e| e.to_string())?;

                let payload = if is_bilibili_index {
                    json!({
                        "model": model,
                        "temperature": 0.1,
                        "messages": [
                            {
                                "role": "user",
                                "content": format!(
                                    "请将以下文本翻译为{target_lang}，直接输出翻译结果，不要进行任何解释。\n\n{text}"
                                )
                            }
                        ]
                    })
                } else {
                    let system_prompt = params
                        .get("system_prompt")
                        .and_then(Value::as_str)
                        .map(ToString::to_string)
                        .unwrap_or_else(|| {
                            format!(
                                "You are a concise cinema translator. Translate the user text naturally into {target_lang}. Output only the translation with no extra commentary."
                            )
                        });
                    json!({
                        "model": model,
                        "temperature": 0.2,
                        "messages": [
                            { "role": "system", "content": system_prompt },
                            { "role": "user", "content": text }
                        ]
                    })
                };

                let mut req = http
                    .post(&endpoint)
                    .header(
                        reqwest::header::USER_AGENT,
                        if is_bilibili_index {
                            "Index-Translate-Client/1.0"
                        } else {
                            "Vedro-Translate/0.3"
                        },
                    )
                    .json(&payload);
                if !api_key.trim().is_empty() {
                    req = req.bearer_auth(api_key.trim());
                }
                let resp = req.send().await.map_err(|e| e.to_string())?;
                let status = resp.status();
                let body: Value = resp
                    .json()
                    .await
                    .map_err(|e| format!("invalid AI response ({status}): {e}"))?;
                if !status.is_success() {
                    let msg = body
                        .pointer("/error/message")
                        .and_then(Value::as_str)
                        .unwrap_or("AI request failed");
                    return Err(format!("HTTP {}: {msg}", status.as_u16()));
                }
                let translated = body
                    .pointer("/choices/0/message/content")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim()
                    .to_string();
                Ok(json!({
                    "translated": translated,
                    "direct_ip": direct_ip,
                    "provider": if is_bilibili_index { "bilibili_index" } else { "openai_compat" }
                }))
            }

            "ai_list_models" => {
                let base_url = str_param(&params, "base_url")?;
                let api_key = params.get("api_key").and_then(Value::as_str).unwrap_or("");
                let is_bilibili_index = base_url
                    .to_ascii_lowercase()
                    .contains("index-translate.bilibili.com");
                let direct_ip = params
                    .get("direct_ip")
                    .and_then(Value::as_bool)
                    .unwrap_or(false);

                let endpoint = format!("{}/models", base_url.trim_end_matches('/'));
                let mut builder = reqwest::Client::builder().timeout(Duration::from_secs(12));
                if direct_ip {
                    builder = builder.no_proxy();
                }
                let http = builder.build().map_err(|e| e.to_string())?;
                let mut req = http.get(&endpoint).header(
                    reqwest::header::USER_AGENT,
                    if is_bilibili_index {
                        "Index-Translate-Client/1.0"
                    } else {
                        concat!("Vedro-Translate/", env!("CARGO_PKG_VERSION"))
                    },
                );
                if !api_key.trim().is_empty() {
                    req = req.bearer_auth(api_key.trim());
                }

                let mut models: Vec<String> = Vec::new();
                match req.send().await {
                    Ok(resp) if resp.status().is_success() => {
                        if let Ok(body) = resp.json::<Value>().await {
                            let arr_opt = body
                                .get("data")
                                .and_then(Value::as_array)
                                .or_else(|| body.get("models").and_then(Value::as_array))
                                .or_else(|| body.as_array());
                            if let Some(arr) = arr_opt {
                                for item in arr {
                                    let id = item
                                        .get("id")
                                        .and_then(Value::as_str)
                                        .or_else(|| item.get("name").and_then(Value::as_str))
                                        .or_else(|| item.as_str())
                                        .map(str::trim)
                                        .filter(|s| !s.is_empty());
                                    if let Some(m) = id {
                                        let clean =
                                            m.strip_prefix("models/").unwrap_or(m).to_string();
                                        if !models.contains(&clean) {
                                            models.push(clean);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Ok(resp) => {
                        if !is_bilibili_index {
                            let status = resp.status();
                            let text = resp.text().await.unwrap_or_default();
                            let msg = serde_json::from_str::<Value>(&text)
                                .ok()
                                .and_then(|v| {
                                    v.pointer("/error/message")
                                        .and_then(Value::as_str)
                                        .map(ToString::to_string)
                                })
                                .unwrap_or_else(|| format!("HTTP {}", status.as_u16()));
                            return Err(format!("获取模型失败: {msg}"));
                        }
                    }
                    Err(e) => {
                        if !is_bilibili_index {
                            return Err(format!("获取模型失败: {e}"));
                        }
                    }
                }
                if models.is_empty() && is_bilibili_index {
                    models.push("Index-Translate-35B-A3B".to_string());
                }
                models.sort();
                Ok(json!({
                    "models": models,
                    "direct_ip": direct_ip,
                }))
            }

            "delete_playlist" => {
                let client = self.require_client()?;
                let playlist_id = str_param(&params, "playlist_id")?;
                client
                    .delete_item(&playlist_id)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(json!({ "deleted": playlist_id }))
            }

            "external_play_url" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let media_source_id = params.get("media_source_id").and_then(Value::as_str);
                let player_id = params.get("player_id").and_then(Value::as_str);
                let pb = client
                    .external_play_info(&item_id, media_source_id, player_id)
                    .await
                    .map_err(|e| e.to_string())?;
                let chosen = media_source_id
                    .and_then(|sid| pb.media_sources.iter().find(|s| s.id == sid))
                    .or_else(|| pb.media_sources.first())
                    .ok_or_else(|| "no playable media source".to_string())?;
                let url = if let Some(ds) = chosen.direct_stream_url.as_deref() {
                    client.resolve_media_url(ds).map_err(|e| e.to_string())?
                } else {
                    let mut fallback = client
                        .build_fallback_video_url(
                            &item_id,
                            &chosen.id,
                            chosen.container.as_deref(),
                            &pb.play_session_id,
                        )
                        .map_err(|e| e.to_string())?;
                    if let Some(tok) = client.access_token() {
                        fallback.query_pairs_mut().append_pair("api_key", &tok);
                    }
                    fallback
                };
                Ok(json!({
                    "url": url.to_string(),
                    "media_source_id": chosen.id,
                }))
            }

            "danmaku_fetch" => {
                let custom_base = params
                    .get("api_base")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let raw_title = str_param(&params, "title")?;
                let alt_title = params
                    .get("alt_title")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty());
                let episode = params.get("episode").and_then(Value::as_u64);
                let season = params.get("season").and_then(Value::as_u64);
                let http = self.build_danmaku_http_client()?;

                // 1. Direct XML/comment URL if provided explicitly
                if let Some(base) = custom_base {
                    if base.ends_with(".xml")
                        || base.contains("/comment/")
                        || base.contains("list.so")
                    {
                        let raw = fetch_danmaku_xml_text(&http, base).await?;
                        return Ok(json!({
                            "source": "direct_xml",
                            "episode_title": raw_title,
                            "raw": raw,
                        }));
                    }
                }

                let queries = build_danmaku_queries(&raw_title, alt_title, season);

                // 2. Try user-configured DandanPlay endpoint (if set) + community DandanPlay proxy
                let mut dandan_bases: Vec<&str> = Vec::new();
                if let Some(b) = custom_base {
                    if !b.contains("api.dandanplay.net") {
                        dandan_bases.push(b);
                    }
                }
                dandan_bases.push("https://dandan-proxy.wiidede.space");
                if let Some(b) = custom_base {
                    if b.contains("api.dandanplay.net") {
                        dandan_bases.push(b);
                    }
                }

                for base in &dandan_bases {
                    for q in &queries {
                        if let Ok(Some(matched)) = dandan_auto_match(&http, base, q, episode).await
                        {
                            return Ok(matched);
                        }
                    }
                }

                // 3. Fallback to official Bilibili PGC (番剧 + 影视) & Bilibili Video XML danmaku
                for q in &queries {
                    if let Ok(Some(matched)) = bilibili_auto_match(&http, q, episode).await {
                        return Ok(matched);
                    }
                }

                Err("未匹配到对应弹幕库，可尝试精简片名关键词或手动选择剧集".to_string())
            }

            "danmaku_search" => {
                let keyword = str_param(&params, "keyword")?;
                let custom_base = params
                    .get("api_base")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty() && !s.contains("api.dandanplay.net"));
                let http = self.build_danmaku_http_client()?;
                let cleaned = clean_danmaku_title(&keyword);
                let search_kw = if cleaned.is_empty() {
                    keyword.trim().to_string()
                } else {
                    cleaned
                };

                let dandan_base = custom_base.unwrap_or("https://dandan-proxy.wiidede.space");
                let (dd_res, bili_res) = tokio::join!(
                    dandan_search_candidates(&http, dandan_base, &search_kw),
                    bilibili_search_candidates(&http, &search_kw),
                );
                let mut candidates = Vec::new();
                if let Ok(mut dd) = dd_res {
                    candidates.append(&mut dd);
                }
                if let Ok(mut bl) = bili_res {
                    candidates.append(&mut bl);
                }
                Ok(json!({ "candidates": candidates }))
            }

            "danmaku_load_target" => {
                let provider = str_param(&params, "provider")?;
                let target_id = str_param(&params, "target_id")?;
                let title = params
                    .get("title")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let custom_base = params
                    .get("api_base")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|s| !s.is_empty() && !s.contains("api.dandanplay.net"));
                let http = self.build_danmaku_http_client()?;

                match provider.as_str() {
                    "bilibili_cid" => {
                        let url = format!("https://comment.bilibili.com/{target_id}.xml");
                        let raw = fetch_danmaku_xml_text(&http, &url).await?;
                        Ok(json!({
                            "source": "bilibili",
                            "episode_title": title,
                            "raw": raw,
                        }))
                    }
                    "bilibili_bvid" => {
                        let view_url = format!(
                            "https://api.bilibili.com/x/web-interface/view?bvid={target_id}"
                        );
                        let resp: Value = http
                            .get(&view_url)
                            .header("Referer", "https://www.bilibili.com/")
                            .send()
                            .await
                            .map_err(|e| e.to_string())?
                            .json()
                            .await
                            .map_err(|e| e.to_string())?;
                        let cid = resp
                            .pointer("/data/cid")
                            .and_then(Value::as_u64)
                            .ok_or_else(|| "无法解析 B 站视频 CID".to_string())?;
                        let xml_url = format!("https://comment.bilibili.com/{cid}.xml");
                        let raw = fetch_danmaku_xml_text(&http, &xml_url).await?;
                        Ok(json!({
                            "source": "bilibili",
                            "episode_title": title,
                            "raw": raw,
                        }))
                    }
                    _ => {
                        let base = custom_base
                            .unwrap_or("https://dandan-proxy.wiidede.space")
                            .trim_end_matches('/');
                        let c_url = format!("{base}/api/v2/comment/{target_id}?withRelated=true");
                        let c_json: Value = http
                            .get(&c_url)
                            .send()
                            .await
                            .map_err(|e| e.to_string())?
                            .json()
                            .await
                            .map_err(|e| e.to_string())?;
                        Ok(json!({
                            "source": "dandan",
                            "episode_id": target_id,
                            "episode_title": title,
                            "comments": c_json.get("comments").cloned().unwrap_or_else(|| json!([])),
                        }))
                    }
                }
            }

            "get_settings" => {
                let cfg = self.playback_config.lock().clone();
                Ok(serde_json::to_value(cfg).unwrap())
            }

            "save_settings" => {
                let cfg: PlaybackConfig =
                    serde_json::from_value(params).map_err(|e| format!("invalid settings: {e}"))?;
                self.store
                    .set_setting("playback_config", &cfg)
                    .map_err(|e| e.to_string())?;
                *self.playback_config.lock() = cfg.clone();
                Ok(serde_json::to_value(cfg).unwrap())
            }

            "get_kv" => {
                let key = str_param(&params, "key")?;
                let val: Option<Value> = self.store.get_setting(&key).map_err(|e| e.to_string())?;
                Ok(json!({ "value": val }))
            }

            "set_kv" => {
                let key = str_param(&params, "key")?;
                let value = params.get("value").cloned().unwrap_or(Value::Null);
                self.store
                    .set_setting(&key, &value)
                    .map_err(|e| e.to_string())?;
                Ok(json!({ "saved": true }))
            }

            "image_url" => {
                let client = self.require_client()?;
                let item_id = str_param(&params, "item_id")?;
                let image_type = params
                    .get("image_type")
                    .and_then(Value::as_str)
                    .unwrap_or("Primary");
                let tag = params.get("tag").and_then(Value::as_str);
                let max_width = params
                    .get("max_width")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32);
                let max_height = params
                    .get("max_height")
                    .and_then(Value::as_u64)
                    .map(|v| v as u32);
                let quality = params
                    .get("quality")
                    .and_then(Value::as_u64)
                    .map(|v| v as u8);
                let url = client
                    .image_url(&item_id, image_type, tag, max_width, max_height, quality)
                    .map_err(|e| e.to_string())?;
                Ok(json!({"url": url.to_string()}))
            }

            other => Err(format!("unknown vedro_invoke method: {other}")),
        }
    }

    fn build_danmaku_http_client(&self) -> Result<reqwest::Client, String> {
        let mut builder = reqwest::Client::builder()
            .timeout(Duration::from_secs(12))
            .user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36");
        if let Some(client) = self.client.lock().as_ref() {
            let opts = client.transport_options();
            builder = builder.danger_accept_invalid_certs(opts.accept_invalid_certs);
            if let Some(p) = opts
                .proxy_url
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
            {
                if let Ok(proxy) = reqwest::Proxy::all(p) {
                    builder = builder.proxy(proxy);
                }
            }
        }
        builder.build().map_err(|e| e.to_string())
    }
}

fn clean_danmaku_title(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    // Strip common video extensions
    for ext in [
        ".mkv", ".mp4", ".avi", ".ts", ".m2ts", ".mov", ".webm", ".strm",
    ] {
        if s.len() > ext.len() && s.to_lowercase().ends_with(ext) {
            s.truncate(s.len() - ext.len());
        }
    }
    // Strip leading bracket tags like `[4K]` / `【动漫】`
    while let Some(rest) = s.strip_prefix('[') {
        if let Some(idx) = rest.find(']') {
            s = rest[idx + 1..].trim().to_string();
        } else {
            break;
        }
    }
    while let Some(rest) = s.strip_prefix('【') {
        if let Some(idx) = rest.find('】') {
            s = rest[idx + '】'.len_utf8()..].trim().to_string();
        } else {
            break;
        }
    }
    // Replace dots/underscores in torrent-style names when no spaces exist
    if !s.contains(' ') && (s.matches('.').count() >= 2 || s.matches('_').count() >= 2) {
        s = s.replace(['.', '_'], " ");
    }
    // Truncate at common release / technical tokens
    let lower = s.to_lowercase();
    let cut_tokens = [
        " 2160p", " 1080p", " 720p", " 4k", " bluray", " blu-ray", " remux", " web-dl", " webrip",
        " hdtv", " hevc", " x265", " x264", " h265", " h264", " dovi", " hdr", " s01", " s02",
        " s03", " s04",
    ];
    let mut cut_at = s.len();
    for tok in cut_tokens {
        if let Some(pos) = lower.find(tok) {
            if pos >= 2 && pos < cut_at {
                cut_at = pos;
            }
        }
    }
    s.truncate(cut_at);
    // Strip trailing `(2024)` year suffix
    let trimmed = s.trim();
    if trimmed.ends_with(')') {
        if let Some(open) = trimmed.rfind('(') {
            let inside = trimmed[open + 1..trimmed.len() - 1].trim();
            if inside.len() == 4 && inside.chars().all(|c| c.is_ascii_digit()) && open >= 2 {
                return trimmed[..open].trim().to_string();
            }
        }
    }
    trimmed.to_string()
}

fn build_danmaku_queries(title: &str, alt_title: Option<&str>, season: Option<u64>) -> Vec<String> {
    let mut out = Vec::new();
    let base = clean_danmaku_title(title);
    if !base.is_empty() {
        if let Some(sn) = season.filter(|&n| n > 1) {
            out.push(format!("{base} 第{sn}季"));
        }
        out.push(base.clone());
        // If title contains middle dot or colon subtitle, also try main prefix
        for sep in ['：', ':', '·', '-'] {
            if let Some((head, _)) = base.split_once(sep) {
                let h = head.trim();
                if h.chars().count() >= 2 && !out.iter().any(|x| x == h) {
                    out.push(h.to_string());
                }
            }
        }
    }
    if let Some(alt) = alt_title {
        let cleaned_alt = clean_danmaku_title(alt);
        if !cleaned_alt.is_empty() && !out.iter().any(|x| x.eq_ignore_ascii_case(&cleaned_alt)) {
            out.push(cleaned_alt);
        }
    }
    if out.is_empty() && !title.trim().is_empty() {
        out.push(title.trim().to_string());
    }
    out
}

fn strip_html_tags(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut in_tag = false;
    for ch in raw.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }
    out
}

fn extract_episode_number_from_text(text: &str) -> Option<u64> {
    let trimmed = text.trim();
    if let Ok(n) = trimmed.parse::<u64>() {
        return Some(n);
    }
    // Look for `第12话` / `第12集` / `EP12` / `E12` / leading digits
    let chars: Vec<char> = trimmed.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i].is_ascii_digit() {
            let start = i;
            while i < chars.len() && chars[i].is_ascii_digit() {
                i += 1;
            }
            let num_str: String = chars[start..i].iter().collect();
            if let Ok(n) = num_str.parse::<u64>() {
                // Skip 4-digit years like 2024 unless preceded by 第/E
                let prev = if start > 0 {
                    Some(chars[start - 1])
                } else {
                    None
                };
                if n < 1900 || matches!(prev, Some('第' | 'E' | 'e' | 'P' | 'p')) {
                    return Some(n);
                }
            }
        } else {
            i += 1;
        }
    }
    None
}

async fn fetch_danmaku_xml_text(http: &reqwest::Client, url: &str) -> Result<String, String> {
    use std::io::Read;
    let resp = http
        .get(url)
        .header("Accept-Encoding", "identity")
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("HTTP {}", resp.status().as_u16()));
    }
    let bytes = resp.bytes().await.map_err(|e| e.to_string())?;
    if bytes.starts_with(b"<?xml")
        || bytes.starts_with(b"<i>")
        || bytes.windows(3).any(|w| w == b"<d ")
    {
        return Ok(String::from_utf8_lossy(&bytes).into_owned());
    }
    // Bilibili `comment.bilibili.com/{cid}.xml` uses raw RFC-1951 deflate without zlib header
    let mut inflated = Vec::new();
    if flate2::read::DeflateDecoder::new(&bytes[..])
        .read_to_end(&mut inflated)
        .is_ok()
        && !inflated.is_empty()
    {
        return Ok(String::from_utf8_lossy(&inflated).into_owned());
    }
    let mut zlib_out = Vec::new();
    if flate2::read::ZlibDecoder::new(&bytes[..])
        .read_to_end(&mut zlib_out)
        .is_ok()
        && !zlib_out.is_empty()
    {
        return Ok(String::from_utf8_lossy(&zlib_out).into_owned());
    }
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

async fn dandan_auto_match(
    http: &reqwest::Client,
    api_base: &str,
    query: &str,
    target_ep: Option<u64>,
) -> Result<Option<Value>, String> {
    let base = api_base.trim_end_matches('/');
    let mut search_url = reqwest::Url::parse(&format!("{base}/api/v2/search/episodes"))
        .map_err(|e| e.to_string())?;
    search_url.query_pairs_mut().append_pair("anime", query);

    let resp = http
        .get(search_url)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Ok(None);
    }
    let s_json: Value = resp.json().await.map_err(|e| e.to_string())?;
    let animes = match s_json.get("animes").and_then(Value::as_array) {
        Some(arr) if !arr.is_empty() => arr,
        _ => return Ok(None),
    };

    let q_lower = query.to_lowercase();
    let best_anime = animes
        .iter()
        .max_by_key(|a| {
            let t = a
                .get("animeTitle")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_lowercase();
            let eps_len = a
                .get("episodes")
                .and_then(Value::as_array)
                .map(|e| e.len())
                .unwrap_or(0);
            let mut score: i64 = 0;
            if t == q_lower {
                score += 1000;
            } else if t.starts_with(&q_lower) {
                score += 650;
            } else if t.contains(&q_lower) || q_lower.contains(&t) {
                score += 350;
            }
            if let Some(ep) = target_ep {
                if eps_len >= ep as usize {
                    score += 180;
                }
            }
            score
        })
        .unwrap();

    let anime_title = best_anime
        .get("animeTitle")
        .and_then(Value::as_str)
        .unwrap_or(query);
    let episodes = match best_anime.get("episodes").and_then(Value::as_array) {
        Some(arr) if !arr.is_empty() => arr,
        _ => return Ok(None),
    };

    let chosen_ep = if let Some(ep_num) = target_ep {
        episodes
            .iter()
            .find(|e| {
                e.get("episodeTitle")
                    .and_then(Value::as_str)
                    .and_then(extract_episode_number_from_text)
                    == Some(ep_num)
            })
            .or_else(|| episodes.get((ep_num.saturating_sub(1)) as usize))
            .unwrap_or(&episodes[0])
    } else {
        &episodes[0]
    };

    let ep_id = match chosen_ep.get("episodeId").and_then(Value::as_i64) {
        Some(id) => id,
        None => return Ok(None),
    };
    let ep_sub = chosen_ep
        .get("episodeTitle")
        .and_then(Value::as_str)
        .unwrap_or("");
    let full_title = if ep_sub.is_empty() {
        anime_title.to_string()
    } else {
        format!("{anime_title} · {ep_sub}")
    };

    let c_url = format!("{base}/api/v2/comment/{ep_id}?withRelated=true");
    let c_resp = http.get(&c_url).send().await.map_err(|e| e.to_string())?;
    if !c_resp.status().is_success() {
        return Ok(None);
    }
    let c_json: Value = c_resp.json().await.map_err(|e| e.to_string())?;
    let comments = c_json
        .get("comments")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if comments.is_empty() {
        return Ok(None);
    }
    Ok(Some(json!({
        "source": "dandan",
        "episode_id": ep_id,
        "episode_title": full_title,
        "comments": comments,
    })))
}

async fn bilibili_cookie_header(http: &reqwest::Client) -> String {
    if let Ok(resp) = http
        .get("https://api.bilibili.com/x/frontend/finger/spi")
        .header("Referer", "https://www.bilibili.com/")
        .send()
        .await
    {
        if let Ok(v) = resp.json::<Value>().await {
            let b3 = v.pointer("/data/b_3").and_then(Value::as_str).unwrap_or("");
            let b4 = v.pointer("/data/b_4").and_then(Value::as_str).unwrap_or("");
            if !b3.is_empty() {
                return format!("buvid3={b3}; buvid4={b4}");
            }
        }
    }
    "buvid3=vedro-client".to_string()
}

async fn bilibili_auto_match(
    http: &reqwest::Client,
    query: &str,
    target_ep: Option<u64>,
) -> Result<Option<Value>, String> {
    let cookie = bilibili_cookie_header(http).await;

    // 1. Official Bilibili PGC Bangumi & Film/TV (`media_bangumi`, `media_ft`)
    for search_type in ["media_bangumi", "media_ft"] {
        let mut s_url = reqwest::Url::parse("https://api.bilibili.com/x/web-interface/search/type")
            .map_err(|e| e.to_string())?;
        {
            let mut qp = s_url.query_pairs_mut();
            qp.append_pair("search_type", search_type);
            qp.append_pair("keyword", query);
        }
        let resp = match http
            .get(s_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            _ => continue,
        };
        let data: Value = match resp.json().await {
            Ok(v) => v,
            Err(_) => continue,
        };
        let results = match data.pointer("/data/result").and_then(Value::as_array) {
            Some(arr) if !arr.is_empty() => arr,
            _ => continue,
        };
        let first = &results[0];
        let season_title =
            strip_html_tags(first.get("title").and_then(Value::as_str).unwrap_or(query));
        let season_id = match first.get("season_id").and_then(Value::as_u64) {
            Some(id) => id,
            None => continue,
        };

        let pgc_url = format!("https://api.bilibili.com/pgc/view/web/season?season_id={season_id}");
        let s_resp = match http
            .get(&pgc_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            _ => continue,
        };
        let s_json: Value = match s_resp.json().await {
            Ok(v) => v,
            Err(_) => continue,
        };
        let eps = match s_json.pointer("/result/episodes").and_then(Value::as_array) {
            Some(arr) if !arr.is_empty() => arr,
            _ => continue,
        };

        let chosen = if let Some(ep_num) = target_ep {
            eps.iter()
                .find(|e| {
                    e.get("title")
                        .and_then(Value::as_str)
                        .and_then(|t| t.trim().parse::<u64>().ok())
                        == Some(ep_num)
                })
                .or_else(|| eps.get((ep_num.saturating_sub(1)) as usize))
                .unwrap_or(&eps[0])
        } else {
            &eps[0]
        };

        if let Some(cid) = chosen.get("cid").and_then(Value::as_u64) {
            let ep_label = chosen
                .get("long_title")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
                .or_else(|| chosen.get("title").and_then(Value::as_str))
                .unwrap_or("");
            let xml_url = format!("https://comment.bilibili.com/{cid}.xml");
            if let Ok(raw) = fetch_danmaku_xml_text(http, &xml_url).await {
                if raw.contains("<d ") {
                    let matched_title = if ep_label.is_empty() {
                        season_title
                    } else {
                        format!("{season_title} · 第{ep_label}话")
                    };
                    return Ok(Some(json!({
                        "source": "bilibili",
                        "episode_title": matched_title,
                        "raw": raw,
                    })));
                }
            }
        }
    }

    // 2. Fallback to Bilibili user-uploaded video when not in PGC
    if target_ep.is_none() || target_ep == Some(1) {
        let mut v_url = reqwest::Url::parse("https://api.bilibili.com/x/web-interface/search/type")
            .map_err(|e| e.to_string())?;
        {
            let mut qp = v_url.query_pairs_mut();
            qp.append_pair("search_type", "video");
            qp.append_pair("keyword", query);
        }
        if let Ok(resp) = http
            .get(v_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            if let Ok(data) = resp.json::<Value>().await {
                if let Some(results) = data.pointer("/data/result").and_then(Value::as_array) {
                    let q_lower = query.to_lowercase();
                    if let Some(hit) = results.iter().find(|r| {
                        let t =
                            strip_html_tags(r.get("title").and_then(Value::as_str).unwrap_or(""))
                                .to_lowercase();
                        t.contains(&q_lower)
                    }) {
                        if let Some(bvid) = hit.get("bvid").and_then(Value::as_str) {
                            let hit_title = strip_html_tags(
                                hit.get("title").and_then(Value::as_str).unwrap_or(query),
                            );
                            let view_url = format!(
                                "https://api.bilibili.com/x/web-interface/view?bvid={bvid}"
                            );
                            if let Ok(vr) = http
                                .get(&view_url)
                                .header("Referer", "https://www.bilibili.com/")
                                .header("Cookie", &cookie)
                                .send()
                                .await
                            {
                                if let Ok(vj) = vr.json::<Value>().await {
                                    if let Some(cid) =
                                        vj.pointer("/data/cid").and_then(Value::as_u64)
                                    {
                                        let xml_url =
                                            format!("https://comment.bilibili.com/{cid}.xml");
                                        if let Ok(raw) =
                                            fetch_danmaku_xml_text(http, &xml_url).await
                                        {
                                            if raw.contains("<d ") {
                                                return Ok(Some(json!({
                                                    "source": "bilibili",
                                                    "episode_title": hit_title,
                                                    "raw": raw,
                                                })));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Ok(None)
}

async fn dandan_search_candidates(
    http: &reqwest::Client,
    api_base: &str,
    keyword: &str,
) -> Result<Vec<Value>, String> {
    let base = api_base.trim_end_matches('/');
    let mut url = reqwest::Url::parse(&format!("{base}/api/v2/search/episodes"))
        .map_err(|e| e.to_string())?;
    url.query_pairs_mut().append_pair("anime", keyword);
    let resp = http.get(url).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Ok(Vec::new());
    }
    let body: Value = resp.json().await.map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    if let Some(animes) = body.get("animes").and_then(Value::as_array) {
        for a in animes.iter().take(8) {
            let title = a.get("animeTitle").and_then(Value::as_str).unwrap_or("");
            let kind = a
                .get("typeDescription")
                .and_then(Value::as_str)
                .unwrap_or("弹弹Play");
            let eps: Vec<Value> = a
                .get("episodes")
                .and_then(Value::as_array)
                .map(|arr| {
                    arr.iter()
                        .take(200)
                        .filter_map(|e| {
                            let id = e.get("episodeId")?.as_i64()?.to_string();
                            let ep_title =
                                e.get("episodeTitle").and_then(Value::as_str).unwrap_or("");
                            Some(json!({
                                "provider": "dandan",
                                "target_id": id,
                                "label": ep_title,
                            }))
                        })
                        .collect()
                })
                .unwrap_or_default();
            if !title.is_empty() && !eps.is_empty() {
                out.push(json!({
                    "source_badge": format!("弹弹 · {kind}"),
                    "title": title,
                    "episodes": eps,
                }));
            }
        }
    }
    Ok(out)
}

async fn bilibili_search_candidates(
    http: &reqwest::Client,
    keyword: &str,
) -> Result<Vec<Value>, String> {
    let cookie = bilibili_cookie_header(http).await;
    let mut out = Vec::new();

    for (stype, badge) in [("media_bangumi", "B站番剧"), ("media_ft", "B站影视")] {
        let mut s_url = reqwest::Url::parse("https://api.bilibili.com/x/web-interface/search/type")
            .map_err(|e| e.to_string())?;
        {
            let mut qp = s_url.query_pairs_mut();
            qp.append_pair("search_type", stype);
            qp.append_pair("keyword", keyword);
        }
        let resp = match http
            .get(s_url)
            .header("Referer", "https://www.bilibili.com/")
            .header("Cookie", &cookie)
            .send()
            .await
        {
            Ok(r) if r.status().is_success() => r,
            _ => continue,
        };
        let data: Value = match resp.json().await {
            Ok(v) => v,
            Err(_) => continue,
        };
        if let Some(results) = data.pointer("/data/result").and_then(Value::as_array) {
            for item in results.iter().take(4) {
                let title =
                    strip_html_tags(item.get("title").and_then(Value::as_str).unwrap_or(""));
                let season_id = match item.get("season_id").and_then(Value::as_u64) {
                    Some(id) => id,
                    None => continue,
                };
                let pgc_url =
                    format!("https://api.bilibili.com/pgc/view/web/season?season_id={season_id}");
                if let Ok(sr) = http
                    .get(&pgc_url)
                    .header("Referer", "https://www.bilibili.com/")
                    .header("Cookie", &cookie)
                    .send()
                    .await
                {
                    if let Ok(sj) = sr.json::<Value>().await {
                        if let Some(eps_raw) =
                            sj.pointer("/result/episodes").and_then(Value::as_array)
                        {
                            let eps: Vec<Value> = eps_raw
                                .iter()
                                .take(300)
                                .filter_map(|e| {
                                    let cid = e.get("cid")?.as_u64()?.to_string();
                                    let t = e.get("title").and_then(Value::as_str).unwrap_or("");
                                    let lt =
                                        e.get("long_title").and_then(Value::as_str).unwrap_or("");
                                    let lbl = if lt.is_empty() {
                                        format!("第 {t} 话")
                                    } else {
                                        format!("{t}. {lt}")
                                    };
                                    Some(json!({
                                        "provider": "bilibili_cid",
                                        "target_id": cid,
                                        "label": lbl,
                                    }))
                                })
                                .collect();
                            if !title.is_empty() && !eps.is_empty() {
                                out.push(json!({
                                    "source_badge": badge,
                                    "title": title,
                                    "episodes": eps,
                                }));
                            }
                        }
                    }
                }
            }
        }
    }
    Ok(out)
}

fn str_param(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
        .ok_or_else(|| format!("missing required string parameter `{key}`"))
}

fn container_mime_type(container: &str) -> String {
    match container.to_lowercase().as_str() {
        "mkv" | "matroska" => "video/x-matroska",
        "mp4" | "m4v" => "video/mp4",
        "mov" => "video/quicktime",
        "webm" => "video/webm",
        "ts" | "m2ts" => "video/mp2t",
        _ => "application/octet-stream",
    }
    .to_string()
}

// =============================================================================
// C-ABI Exports (Flutter dart:ffi, Swift, Kotlin, C++)
// =============================================================================

#[no_mangle]
pub extern "C" fn vedro_init(db_path_utf8: *const c_char) -> *mut VedroRuntime {
    let db_path = if db_path_utf8.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(db_path_utf8) }.to_str().ok()
    };
    match VedroRuntime::new(db_path) {
        Ok(rt) => Box::into_raw(Box::new(rt)),
        Err(e) => {
            warn!(error = %e, "vedro_init failed");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn vedro_invoke(
    rt: *mut VedroRuntime,
    method_utf8: *const c_char,
    params_json_utf8: *const c_char,
) -> *mut c_char {
    if rt.is_null() || method_utf8.is_null() {
        return to_c_string(&json!({"ok": false, "error": "null runtime or method"}).to_string());
    }
    let runtime = unsafe { &*rt };
    let method = match unsafe { CStr::from_ptr(method_utf8) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            return to_c_string(&json!({"ok": false, "error": "invalid utf8 method"}).to_string())
        }
    };
    let params = if params_json_utf8.is_null() {
        json!({})
    } else {
        match unsafe { CStr::from_ptr(params_json_utf8) }.to_str() {
            Ok(raw) if !raw.trim().is_empty() => {
                serde_json::from_str(raw).unwrap_or_else(|_| json!({}))
            }
            _ => json!({}),
        }
    };

    let envelope = match runtime.invoke(method, params) {
        Ok(data) => json!({"ok": true, "data": data}),
        Err(err) => json!({"ok": false, "error": err}),
    };
    to_c_string(&envelope.to_string())
}

#[no_mangle]
pub extern "C" fn vedro_poll_events(rt: *mut VedroRuntime) -> *mut c_char {
    if rt.is_null() {
        return to_c_string("[]");
    }
    let runtime = unsafe { &*rt };
    let events = runtime.poll_events();
    to_c_string(&serde_json::to_string(&events).unwrap_or_else(|_| "[]".to_string()))
}

#[no_mangle]
pub extern "C" fn vedro_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn vedro_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn vedro_destroy(rt: *mut VedroRuntime) {
    if !rt.is_null() {
        unsafe {
            let _ = Box::from_raw(rt);
        }
    }
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"ok":false,"error":"nul byte in response"}"#).unwrap())
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn c_abi_lifecycle_and_settings_roundtrip() {
        let rt = vedro_init(std::ptr::null());
        assert!(!rt.is_null());

        let m = CString::new("version").unwrap();
        let res_ptr = vedro_invoke(rt, m.as_ptr(), std::ptr::null());
        let res_str = unsafe { CStr::from_ptr(res_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        vedro_free_string(res_ptr);

        let v: Value = serde_json::from_str(&res_str).unwrap();
        assert_eq!(v["ok"], true);
        assert!(v["data"]["proxy_addr"]
            .as_str()
            .unwrap()
            .starts_with("127.0.0.1:"));

        let ev_ptr = vedro_poll_events(rt);
        let ev_str = unsafe { CStr::from_ptr(ev_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        vedro_free_string(ev_ptr);
        assert_eq!(ev_str, "[]");

        vedro_destroy(rt);
    }
}
