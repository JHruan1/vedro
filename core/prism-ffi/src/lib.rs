#![allow(clippy::not_unsafe_ptr_arg_deref)]
use std::collections::VecDeque;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;
use std::time::Duration;

use parking_lot::Mutex;
use prism_playback::{
    AudioOutputMode, AudioRoutingDecision, DolbyVisionDecision, PlaybackConfig, PlaybackEngine,
    PlaybackStats, ToneMappingAlgorithm,
};
use prism_protocol::{
    discover_lan_servers, ClientIdentity, EmbyClient, ItemsQuery, MediaBadges, MediaSourceInfo,
    PlaybackProgressPayload, WebSocketSession,
};
use prism_storage::{PrismStore, ServerProfile};
use prism_stream::{
    inspect_media_header, InspectedMedia, StreamProxy, StreamProxyConfig, StreamProxyStats,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::runtime::Runtime;
use tracing::warn;

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

/// Core runtime backing both the C-ABI FFI library (`libprism_ffi`) and native Rust hosts.
pub struct PrismRuntime {
    rt: Runtime,
    store: PrismStore,
    proxy: Arc<StreamProxy>,
    client: Mutex<Option<EmbyClient>>,
    ws: Mutex<Option<WebSocketSession>>,
    engine: Mutex<Option<Arc<PlaybackEngine>>>,
    playback_config: Mutex<PlaybackConfig>,
    active_session: Mutex<Option<ActivePlaybackSession>>,
    events: Arc<Mutex<VecDeque<Value>>>,
    identity: Mutex<ClientIdentity>,
}

impl PrismRuntime {
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
            .thread_name("prism-core")
            .build()
            .map_err(|e| format!("failed to build tokio runtime: {e}"))?;

        let store = match db_path {
            None | Some("") | Some(":memory:") => PrismStore::open_in_memory(),
            Some(p) => PrismStore::open(p),
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
                Ok(serde_json::to_value(list).unwrap())
            }

            "delete_server" => {
                let id = str_param(&params, "id")?;
                self.store.delete_server(&id).map_err(|e| e.to_string())?;
                Ok(json!({"deleted": id}))
            }

            "connect_server" => {
                let url = str_param(&params, "url")?;
                if let Some(dev_name) = params.get("device_name").and_then(Value::as_str) {
                    self.identity.lock().device_name = dev_name.to_string();
                }
                let identity = self.identity.lock().clone();
                let client = EmbyClient::new(&url, identity).map_err(|e| e.to_string())?;
                let (info, caps) = client.probe_server().await.map_err(|e| e.to_string())?;
                *self.client.lock() = Some(client);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
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
                let _ = self.store.upsert_server(&ServerProfile {
                    id: server_id,
                    name: if caps.server_name.is_empty() {
                        client.base_url().to_string()
                    } else {
                        caps.server_name.clone()
                    },
                    url: client.base_url().to_string(),
                    dialect: caps.dialect.as_str().to_string(),
                    user_id: Some(auth.user.id.clone()),
                    username: Some(auth.user.name.clone()),
                    access_token: Some(auth.access_token.clone()),
                    is_admin,
                    last_connected_at: chrono::Utc::now().timestamp(),
                });
                self.start_websocket(client.clone());
                Ok(json!({
                    "auth": auth,
                    "capabilities": caps,
                }))
            }

            "restore_session" => {
                let url = str_param(&params, "url")?;
                let token = str_param(&params, "access_token")?;
                let user_id = str_param(&params, "user_id")?;
                let identity = self.identity.lock().clone();
                let client = EmbyClient::new(&url, identity).map_err(|e| e.to_string())?;
                let (info, caps) = client.probe_server().await.map_err(|e| e.to_string())?;
                client.set_credentials(token, user_id);
                let user = client.current_user().await.map_err(|e| e.to_string())?;
                *self.client.lock() = Some(client.clone());
                self.start_websocket(client);
                Ok(json!({
                    "info": info,
                    "capabilities": caps,
                    "user": user,
                }))
            }

            "logout" => {
                let ws_opt = self.ws.lock().take();
                if let Some(mut ws) = ws_opt {
                    ws.stop().await;
                }
                let client_opt = self.client.lock().clone();
                if let Some(client) = client_opt {
                    let _ = client.logout().await;
                }
                Ok(json!({"logged_out": true}))
            }

            "get_home" => {
                let client = self.require_client()?;
                let (views_r, resume_r, next_up_r, popular_r, suggestions_r) = tokio::join!(
                    client.views(),
                    client.resume(20, None),
                    client.next_up(20, None),
                    client.popular(10),
                    client.suggestions(16),
                );
                let views = views_r.map_err(|e| e.to_string())?;
                let resume = resume_r.unwrap_or_default();
                let next_up = next_up_r.unwrap_or_default();
                let popular = popular_r.unwrap_or_default();
                let suggestions = suggestions_r.unwrap_or_default();

                // Fetch Latest for up to 6 libraries in parallel
                let mut latest_by_library = Vec::new();
                for lib in views.items.iter().take(6) {
                    if let Ok(items) = client.latest(Some(&lib.id), 16).await {
                        if !items.is_empty() {
                            latest_by_library.push(json!({
                                "library": lib,
                                "items": items,
                            }));
                        }
                    }
                }

                Ok(json!({
                    "capabilities": client.capabilities(),
                    "views": views.items,
                    "popular": popular,
                    "resume": resume.items,
                    "next_up": next_up.items,
                    "suggestions": suggestions.items,
                    "latest_by_library": latest_by_library,
                }))
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
                let item = client.item(&id).await.map_err(|e| e.to_string())?;
                let similar = client.similar(&id, 12).await.unwrap_or_default();
                let segments = client.media_segments(&id).await.unwrap_or_default();
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
                let res = client
                    .episodes(&series_id, season_id, start_index, limit)
                    .await
                    .map_err(|e| e.to_string())?;
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
                    prism_protocol::auth::url_has_stream_ticket(upstream_url.as_str());

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

                // Inspect the first 256 KiB via our proxy (reuses chunk 0 cache!) to detect
                // exact Dolby Vision Profile 5/7/8 & Dolby Atmos even on unprobed embygo items!
                let inspected = if inspect_header {
                    self.proxy
                        .read_range(&stream_id, 0, 256 * 1024)
                        .await
                        .map(|bytes| inspect_media_header(&bytes))
                } else {
                    None
                };

                let cfg = self.playback_config.lock().clone();
                let hdr_fmt = inspected
                    .as_ref()
                    .and_then(|i| i.hdr_format.clone())
                    .unwrap_or(prism_stream::HdrFormat::Sdr);
                let spatial = inspected.as_ref().and_then(|i| i.spatial_audio.clone());

                let hdr_decision = prism_playback::resolve_hdr_pipeline(
                    cfg.platform,
                    &cfg.display,
                    &hdr_fmt,
                    cfg.prefer_native_dolby_vision,
                    cfg.tone_mapping,
                );
                let audio_decision = prism_playback::resolve_audio_routing(
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
                let (status, counts, sessions) = tokio::join!(
                    client.embygo_status(),
                    client.item_counts(),
                    client.sessions(true),
                );
                Ok(json!({
                    "status": status.ok(),
                    "counts": counts.ok(),
                    "playing_sessions": sessions.unwrap_or_default(),
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

            other => Err(format!("unknown prism_invoke method: {other}")),
        }
    }
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
pub extern "C" fn prism_init(db_path_utf8: *const c_char) -> *mut PrismRuntime {
    let db_path = if db_path_utf8.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(db_path_utf8) }.to_str().ok()
    };
    match PrismRuntime::new(db_path) {
        Ok(rt) => Box::into_raw(Box::new(rt)),
        Err(e) => {
            warn!(error = %e, "prism_init failed");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn prism_invoke(
    rt: *mut PrismRuntime,
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
pub extern "C" fn prism_poll_events(rt: *mut PrismRuntime) -> *mut c_char {
    if rt.is_null() {
        return to_c_string("[]");
    }
    let runtime = unsafe { &*rt };
    let events = runtime.poll_events();
    to_c_string(&serde_json::to_string(&events).unwrap_or_else(|_| "[]".to_string()))
}

#[no_mangle]
pub extern "C" fn prism_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn prism_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn prism_destroy(rt: *mut PrismRuntime) {
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
        let rt = prism_init(std::ptr::null());
        assert!(!rt.is_null());

        let m = CString::new("version").unwrap();
        let res_ptr = prism_invoke(rt, m.as_ptr(), std::ptr::null());
        let res_str = unsafe { CStr::from_ptr(res_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        prism_free_string(res_ptr);

        let v: Value = serde_json::from_str(&res_str).unwrap();
        assert_eq!(v["ok"], true);
        assert!(v["data"]["proxy_addr"]
            .as_str()
            .unwrap()
            .starts_with("127.0.0.1:"));

        let ev_ptr = prism_poll_events(rt);
        let ev_str = unsafe { CStr::from_ptr(ev_ptr) }
            .to_str()
            .unwrap()
            .to_string();
        prism_free_string(ev_ptr);
        assert_eq!(ev_str, "[]");

        prism_destroy(rt);
    }
}
