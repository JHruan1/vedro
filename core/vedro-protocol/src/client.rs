use std::sync::Arc;
use std::time::Duration;

use parking_lot::RwLock;
use reqwest::{Client, Method, Response, StatusCode};
use serde::de::DeserializeOwned;
use tracing::{debug, warn};
use url::Url;

use crate::auth::{url_has_stream_ticket, ClientIdentity};
use crate::dialect::{ServerCapabilities, ServerDialect};
use crate::error::{ProtocolError, Result};
use crate::models::*;

const DEFAULT_ITEM_FIELDS: &str = "PrimaryImageAspectRatio,MediaSources,Overview,ChildCount,RecursiveItemCount,People,Genres,Tags,ProviderIds,OriginalTitle,DateCreated,ProductionLocations";

/// High-performance async REST client supporting `embygo`, `Emby`, and `Jellyfin`.
///
/// Key invariants tailored for `embygo`:
/// - Sends auth strictly via `X-Emby-Authorization` / `Authorization` / `X-Emby-Token` headers.
/// - Never injects long-lived bearer tokens into `StreamTicket` media/subtitle URLs.
/// - Never requests `PlayMethod=Transcode` when talking to `embygo`.
/// - Gracefully handles embygo extensions (`Popular`, `Suggestions`, `HideFromResume`,
///   `Sessions/Playing/Ping`, `/emby-compat/status`) with clean fallback on Emby/Jellyfin.
#[derive(Clone)]
pub struct EmbyClient {
    http: Client,
    base_url: Url,
    identity: ClientIdentity,
    state: Arc<RwLock<ClientState>>,
}

#[derive(Debug, Default)]
struct ClientState {
    access_token: Option<String>,
    user_id: Option<String>,
    capabilities: ServerCapabilities,
}

impl EmbyClient {
    /// Create a new client targeting `server_url` (e.g. `https://emby.example.com` or `http://127.0.0.1:8097`).
    pub fn new(server_url: &str, identity: ClientIdentity) -> Result<Self> {
        let normalized = normalize_base_url(server_url)?;
        let http = Client::builder()
            .pool_max_idle_per_host(8)
            .pool_idle_timeout(Duration::from_secs(60))
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .tcp_nodelay(true)
            .build()?;

        Ok(Self {
            http,
            base_url: normalized,
            identity,
            state: Arc::new(RwLock::new(ClientState::default())),
        })
    }

    pub fn base_url(&self) -> &Url {
        &self.base_url
    }

    pub fn identity(&self) -> &ClientIdentity {
        &self.identity
    }

    pub fn capabilities(&self) -> ServerCapabilities {
        self.state.read().capabilities.clone()
    }

    pub fn access_token(&self) -> Option<String> {
        self.state.read().access_token.clone()
    }

    pub fn user_id(&self) -> Option<String> {
        self.state.read().user_id.clone()
    }

    /// Restore a previously saved authenticated session (e.g. from SQLite storage).
    pub fn set_credentials(&self, access_token: String, user_id: String) {
        let mut st = self.state.write();
        st.access_token = Some(access_token);
        st.user_id = Some(user_id);
    }

    pub fn clear_credentials(&self) {
        let mut st = self.state.write();
        st.access_token = None;
        st.user_id = None;
    }

    /// Build an absolute URL for a relative API path, preserving any configured path prefix.
    pub fn endpoint_url(&self, path: &str) -> Result<Url> {
        let trimmed = path.trim_start_matches('/');
        let base_str = self.base_url.as_str().trim_end_matches('/');
        let prefix = self.state.read().capabilities.api_prefix.clone();
        let full = if prefix.is_empty() {
            format!("{base_str}/{trimmed}")
        } else {
            format!("{base_str}/{}/{trimmed}", prefix.trim_matches('/'))
        };
        Ok(Url::parse(&full)?)
    }

    /// Resolve a `DirectStreamUrl` or subtitle `DeliveryUrl` returned by the server.
    ///
    /// Security rule (embygo): if the URL already carries a short-lived `StreamTicket`,
    /// return it as-is without appending any long-lived token or `api_key`.
    pub fn resolve_media_url(&self, server_relative_or_abs: &str) -> Result<Url> {
        let mut url = if server_relative_or_abs.starts_with("http://")
            || server_relative_or_abs.starts_with("https://")
        {
            Url::parse(server_relative_or_abs)?
        } else {
            self.endpoint_url(server_relative_or_abs)?
        };

        if url_has_stream_ticket(url.as_str()) {
            // Confirm dialect hint: StreamTicket is embygo's signature mechanism
            let mut st = self.state.write();
            st.capabilities.uses_stream_tickets = true;
            return Ok(url);
        }

        // For standard Emby/Jellyfin servers without StreamTicket, players like libmpv
        // can authenticate via HTTP headers (preferred). We only keep the URL clean here;
        // our stream proxy attaches `X-Emby-Token` / `X-Emby-Authorization` headers.
        let _ = &mut url;
        Ok(url)
    }

    /// Build a safe direct video stream URL fallback when `DirectStreamUrl` is absent
    /// (e.g. Jellyfin / older Emby responses).
    pub fn build_fallback_video_url(
        &self,
        item_id: &str,
        media_source_id: &str,
        container: Option<&str>,
        play_session_id: &str,
    ) -> Result<Url> {
        let action = match container.filter(|c| !c.is_empty()) {
            Some(ext) => format!("stream.{}", ext.trim_start_matches('.')),
            None => "stream".to_string(),
        };
        let mut url = self.endpoint_url(&format!("Videos/{item_id}/{action}"))?;
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("Static", "true");
            q.append_pair("MediaSourceId", media_source_id);
            if !play_session_id.is_empty() {
                q.append_pair("PlaySessionId", play_session_id);
            }
        }
        Ok(url)
    }

    /// Build an artwork image URL with optional `maxWidth` / `maxHeight` / `quality` / `tag`.
    /// Note: Image GETs are unauthenticated on embygo, Emby, and Jellyfin (ETag-immutable when tagged).
    pub fn image_url(
        &self,
        item_id: &str,
        image_type: &str,
        tag: Option<&str>,
        max_width: Option<u32>,
        max_height: Option<u32>,
        quality: Option<u8>,
    ) -> Result<Url> {
        let mut url = self.endpoint_url(&format!("Items/{item_id}/Images/{image_type}"))?;
        {
            let mut q = url.query_pairs_mut();
            if let Some(t) = tag.filter(|t| !t.is_empty()) {
                q.append_pair("tag", t);
            }
            if let Some(w) = max_width {
                q.append_pair("maxWidth", &w.to_string());
            }
            if let Some(h) = max_height {
                q.append_pair("maxHeight", &h.to_string());
            }
            if let Some(qual) = quality {
                q.append_pair("quality", &qual.to_string());
            }
        }
        Ok(url)
    }

    /// Build request headers for authenticated media/HTTP proxy requests.
    pub fn auth_headers(&self) -> reqwest::header::HeaderMap {
        let token = self.access_token();
        self.identity.build_headers(token.as_deref())
    }

    async fn send_raw(
        &self,
        method: Method,
        path: &str,
        query: &[(&str, String)],
        body: Option<serde_json::Value>,
    ) -> Result<Response> {
        let mut url = self.endpoint_url(path)?;
        if !query.is_empty() {
            let mut pairs = url.query_pairs_mut();
            for (k, v) in query {
                if !v.is_empty() {
                    pairs.append_pair(k, v);
                }
            }
        }
        let headers = self.auth_headers();
        let mut req = self.http.request(method, url).headers(headers);
        if let Some(json) = body {
            req = req.json(&json);
        }
        let resp = req.send().await?;
        let status = resp.status();
        if status.is_success() {
            return Ok(resp);
        }
        let retry_after = resp
            .headers()
            .get("Retry-After")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.parse::<u64>().ok());
        let text = resp.text().await.unwrap_or_default();
        let message = serde_json::from_str::<serde_json::Value>(&text)
            .ok()
            .and_then(|v| {
                v.get("Message")
                    .and_then(|m| m.as_str())
                    .map(ToString::to_string)
            })
            .filter(|m| !m.is_empty())
            .unwrap_or_else(|| {
                if text.is_empty() {
                    format!("HTTP {}", status.as_u16())
                } else {
                    text.chars().take(240).collect()
                }
            });

        Err(match status {
            StatusCode::UNAUTHORIZED => ProtocolError::Unauthorized(message),
            StatusCode::FORBIDDEN => ProtocolError::Forbidden(message),
            StatusCode::NOT_FOUND => ProtocolError::NotFound(message),
            StatusCode::TOO_MANY_REQUESTS => ProtocolError::RateLimited {
                retry_after_secs: retry_after,
                message,
            },
            _ => ProtocolError::Api {
                status: status.as_u16(),
                message,
            },
        })
    }

    async fn request_json<T: DeserializeOwned>(
        &self,
        method: Method,
        path: &str,
        query: &[(&str, String)],
        body: Option<serde_json::Value>,
    ) -> Result<T> {
        let resp = self.send_raw(method, path, query, body).await?;
        let bytes = resp.bytes().await?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    async fn request_empty(
        &self,
        method: Method,
        path: &str,
        query: &[(&str, String)],
        body: Option<serde_json::Value>,
    ) -> Result<()> {
        let _ = self.send_raw(method, path, query, body).await?;
        Ok(())
    }

    fn require_user_id(&self) -> Result<String> {
        self.user_id()
            .ok_or_else(|| ProtocolError::Unauthorized("not signed in".into()))
    }

    // -------------------------------------------------------------------------
    // Discovery, Health & Authentication
    // -------------------------------------------------------------------------

    /// Probe `GET /System/Info/Public` and detect server dialect (`embygo` / `Emby` / `Jellyfin`).
    pub async fn probe_server(&self) -> Result<(PublicSystemInfo, ServerCapabilities)> {
        let resp = self
            .send_raw(Method::GET, "System/Info/Public", &[], None)
            .await?;
        let server_hdr = resp
            .headers()
            .get("Server")
            .and_then(|v| v.to_str().ok())
            .map(ToString::to_string);
        let emby_ver_hdr = resp
            .headers()
            .get("X-Emby-Server-Version")
            .and_then(|v| v.to_str().ok())
            .map(ToString::to_string);
        let bytes = resp.bytes().await?;
        let info: PublicSystemInfo = serde_json::from_slice(&bytes)?;

        // Also check `/emby-compat/status` existence (401/403/200 indicates embygo; 404 indicates Emby/Jellyfin).
        let is_embygo_hint = match self
            .send_raw(Method::GET, "emby-compat/status", &[], None)
            .await
        {
            Ok(_) => true,
            Err(ProtocolError::Unauthorized(_)) | Err(ProtocolError::Forbidden(_)) => true,
            Err(_) => false,
        };

        let caps = ServerCapabilities::detect(
            &info,
            server_hdr.as_deref(),
            emby_ver_hdr.as_deref(),
            is_embygo_hint,
        );
        self.state.write().capabilities = caps.clone();
        debug!(
            dialect = caps.dialect.as_str(),
            server_name = %caps.server_name,
            version = %caps.advertised_version,
            "probed media server"
        );
        Ok((info, caps))
    }

    pub async fn ping(&self) -> Result<String> {
        let resp = self.send_raw(Method::GET, "System/Ping", &[], None).await?;
        Ok(resp.text().await.unwrap_or_default())
    }

    pub async fn public_users(&self) -> Result<Vec<UserDto>> {
        self.request_json(Method::GET, "Users/Public", &[], None)
            .await
    }

    /// Authenticate with username and plaintext password (`Pw`) via JSON body.
    /// Works seamlessly across `embygo`, `Emby`, and `Jellyfin`.
    pub async fn authenticate_by_name(
        &self,
        username: &str,
        password: &str,
    ) -> Result<AuthResponse> {
        let body = serde_json::json!({
            "Username": username,
            "Pw": password,
        });
        let resp: AuthResponse = self
            .request_json(Method::POST, "Users/AuthenticateByName", &[], Some(body))
            .await?;

        self.set_credentials(resp.access_token.clone(), resp.user.id.clone());

        // Post-login: register capabilities & inspect embygo admin status if available
        let _ = self
            .report_capabilities(&ClientCapabilitiesPayload::default())
            .await;
        if let Ok(status) = self.embygo_status().await {
            let mut st = self.state.write();
            st.capabilities.mark_embygo(status.version);
        }
        Ok(resp)
    }

    pub async fn logout(&self) -> Result<()> {
        let res = self
            .request_empty(Method::POST, "Sessions/Logout", &[], None)
            .await;
        self.clear_credentials();
        res
    }

    pub async fn current_user(&self) -> Result<UserDto> {
        let uid = self.require_user_id()?;
        self.request_json(Method::GET, &format!("Users/{uid}"), &[], None)
            .await
    }

    pub async fn report_capabilities(&self, caps: &ClientCapabilitiesPayload) -> Result<()> {
        let body = serde_json::to_value(caps)?;
        self.request_empty(Method::POST, "Sessions/Capabilities/Full", &[], Some(body))
            .await
    }

    // -------------------------------------------------------------------------
    // Home, Libraries, Browsing & EmbyGo Extensions
    // -------------------------------------------------------------------------

    pub async fn views(&self) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        self.request_json(Method::GET, &format!("Users/{uid}/Views"), &[], None)
            .await
    }

    pub async fn resume(
        &self,
        limit: u32,
        parent_id: Option<&str>,
    ) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let mut q = vec![
            ("Limit", limit.to_string()),
            ("EnableUserData", "true".into()),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
        ];
        if let Some(pid) = parent_id {
            q.push(("ParentId", pid.to_string()));
        }
        self.request_json(Method::GET, &format!("Users/{uid}/Items/Resume"), &q, None)
            .await
    }

    /// embygo & Emby: remove an item from Continue Watching WITHOUT clearing position or PlayCount.
    pub async fn hide_from_resume(&self, item_id: &str, hide: bool) -> Result<UserItemDataDto> {
        let uid = self.require_user_id()?;
        let method = if hide { Method::POST } else { Method::DELETE };
        self.request_json(
            method,
            &format!("Users/{uid}/Items/{item_id}/HideFromResume"),
            &[("Hide", hide.to_string())],
            None,
        )
        .await
    }

    pub async fn next_up(
        &self,
        limit: u32,
        series_id: Option<&str>,
    ) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let mut q = vec![
            ("UserId", uid),
            ("Limit", limit.to_string()),
            ("EnableUserData", "true".into()),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
        ];
        if let Some(sid) = series_id {
            q.push(("SeriesId", sid.to_string()));
        }
        self.request_json(Method::GET, "Shows/NextUp", &q, None)
            .await
    }

    /// embygo extension: `GET /Users/{id}/Items/Popular` (returns bare `Vec<BaseItemDto>`).
    /// Gracefully returns empty Vec if the server is Emby/Jellyfin and returns 404.
    pub async fn popular(&self, limit: u32) -> Result<Vec<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let q = vec![
            ("Limit", limit.to_string()),
            ("EnableUserData", "true".into()),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
        ];
        match self
            .request_json::<Vec<BaseItemDto>>(
                Method::GET,
                &format!("Users/{uid}/Items/Popular"),
                &q,
                None,
            )
            .await
        {
            Ok(items) => {
                let mut st = self.state.write();
                st.capabilities.supports_popular = true;
                Ok(items)
            }
            Err(ProtocolError::NotFound(_)) => {
                self.state.write().capabilities.supports_popular = false;
                Ok(Vec::new())
            }
            Err(e) => Err(e),
        }
    }

    /// "猜你喜欢" (`GET /Users/{id}/Suggestions`).
    pub async fn suggestions(&self, limit: u32) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let q = vec![
            ("Limit", limit.to_string()),
            ("EnableUserData", "true".into()),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
        ];
        match self
            .request_json::<ItemsResult<BaseItemDto>>(
                Method::GET,
                &format!("Users/{uid}/Suggestions"),
                &q,
                None,
            )
            .await
        {
            Ok(res) => Ok(res),
            Err(ProtocolError::NotFound(_)) => Ok(ItemsResult::default()),
            Err(e) => Err(e),
        }
    }

    pub async fn latest(&self, parent_id: Option<&str>, limit: u32) -> Result<Vec<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let mut q = vec![
            ("Limit", limit.to_string()),
            ("GroupItems", "true".into()),
            ("EnableUserData", "true".into()),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
        ];
        if let Some(pid) = parent_id {
            q.push(("ParentId", pid.to_string()));
        }
        self.request_json(Method::GET, &format!("Users/{uid}/Items/Latest"), &q, None)
            .await
    }

    pub async fn items(&self, query: &ItemsQuery) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let mut q: Vec<(&str, String)> = vec![
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
            ("EnableUserData", "true".into()),
        ];
        if let Some(v) = &query.parent_id {
            q.push(("ParentId", v.clone()));
        }
        if let Some(v) = &query.include_item_types {
            q.push(("IncludeItemTypes", v.clone()));
        }
        if let Some(v) = query.recursive {
            q.push(("Recursive", v.to_string()));
        }
        if let Some(v) = &query.sort_by {
            q.push(("SortBy", v.clone()));
        }
        if let Some(v) = &query.sort_order {
            q.push(("SortOrder", v.clone()));
        }
        if let Some(v) = query.start_index {
            q.push(("StartIndex", v.to_string()));
        }
        if let Some(v) = query.limit {
            q.push(("Limit", v.to_string()));
        }
        if let Some(v) = &query.search_term {
            q.push(("SearchTerm", v.clone()));
        }
        if let Some(v) = &query.genre_ids {
            q.push(("GenreIds", v.clone()));
        }
        if let Some(v) = &query.genres {
            q.push(("Genres", v.clone()));
        }
        if let Some(v) = &query.studio_ids {
            q.push(("StudioIds", v.clone()));
        }
        if let Some(v) = &query.tag_ids {
            q.push(("TagIds", v.clone()));
        }
        if let Some(v) = &query.tags {
            q.push(("Tags", v.clone()));
        }
        if let Some(v) = &query.years {
            q.push(("Years", v.clone()));
        }
        if let Some(v) = &query.official_ratings {
            q.push(("OfficialRatings", v.clone()));
        }
        if let Some(v) = &query.person_ids {
            q.push(("PersonIds", v.clone()));
        }
        if let Some(v) = query.is_played {
            q.push(("IsPlayed", v.to_string()));
        }
        if let Some(v) = query.is_favorite {
            q.push(("IsFavorite", v.to_string()));
        }
        if let Some(v) = query.is_resumable {
            q.push(("IsResumable", v.to_string()));
        }
        if let Some(v) = &query.filters {
            q.push(("Filters", v.clone()));
        }
        self.request_json(Method::GET, &format!("Users/{uid}/Items"), &q, None)
            .await
    }

    pub async fn item(&self, item_id: &str) -> Result<BaseItemDto> {
        let uid = self.require_user_id()?;
        let q = vec![
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
            ("EnableUserData", "true".into()),
        ];
        self.request_json(
            Method::GET,
            &format!("Users/{uid}/Items/{item_id}"),
            &q,
            None,
        )
        .await
    }

    pub async fn seasons(&self, series_id: &str) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let q = vec![
            ("UserId", uid),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
            ("EnableUserData", "true".into()),
        ];
        self.request_json(Method::GET, &format!("Shows/{series_id}/Seasons"), &q, None)
            .await
    }

    pub async fn episodes(
        &self,
        series_id: &str,
        season_id: Option<&str>,
        start_index: Option<u64>,
        limit: Option<u64>,
    ) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let mut q = vec![
            ("UserId", uid),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
            ("EnableUserData", "true".into()),
        ];
        if let Some(sid) = season_id {
            q.push(("SeasonId", sid.to_string()));
        }
        if let Some(idx) = start_index {
            q.push(("StartIndex", idx.to_string()));
        }
        if let Some(lim) = limit {
            q.push(("Limit", lim.to_string()));
        }
        self.request_json(
            Method::GET,
            &format!("Shows/{series_id}/Episodes"),
            &q,
            None,
        )
        .await
    }

    pub async fn similar(&self, item_id: &str, limit: u32) -> Result<ItemsResult<BaseItemDto>> {
        let uid = self.require_user_id()?;
        let q = vec![
            ("UserId", uid),
            ("Limit", limit.to_string()),
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
            ("EnableUserData", "true".into()),
        ];
        self.request_json(Method::GET, &format!("Items/{item_id}/Similar"), &q, None)
            .await
    }

    pub async fn search_hints(
        &self,
        term: &str,
        include_item_types: Option<&str>,
        limit: u32,
    ) -> Result<SearchHintsResult> {
        let uid = self.require_user_id()?;
        let mut q = vec![
            ("SearchTerm", term.to_string()),
            ("UserId", uid),
            ("Limit", limit.to_string()),
        ];
        if let Some(types) = include_item_types {
            q.push(("IncludeItemTypes", types.to_string()));
        }
        self.request_json(Method::GET, "Search/Hints", &q, None)
            .await
    }

    pub async fn person_credits(&self, person_id: &str) -> Result<ItemsResult<BaseItemDto>> {
        let q = vec![
            ("Fields", DEFAULT_ITEM_FIELDS.into()),
            ("EnableUserData", "true".into()),
        ];
        match self
            .request_json(
                Method::GET,
                &format!("Persons/{person_id}/Credits"),
                &q,
                None,
            )
            .await
        {
            Ok(res) => Ok(res),
            Err(ProtocolError::NotFound(_)) => {
                // Fallback for servers that prefer PersonIds filter on /Items
                self.items(&ItemsQuery {
                    person_ids: Some(person_id.to_string()),
                    recursive: Some(true),
                    include_item_types: Some("Movie,Series".to_string()),
                    limit: Some(100),
                    ..Default::default()
                })
                .await
            }
            Err(e) => Err(e),
        }
    }

    pub async fn filters2(&self, parent_id: Option<&str>) -> Result<Filters2Result> {
        let uid = self.require_user_id()?;
        let mut q = vec![("UserId", uid)];
        if let Some(pid) = parent_id {
            q.push(("ParentId", pid.to_string()));
        }
        self.request_json(Method::GET, "Items/Filters2", &q, None)
            .await
    }

    pub async fn media_segments(&self, item_id: &str) -> Result<MediaSegmentsResult> {
        match self
            .request_json(Method::GET, &format!("MediaSegments/{item_id}"), &[], None)
            .await
        {
            Ok(res) => Ok(res),
            Err(ProtocolError::NotFound(_)) => Ok(MediaSegmentsResult::default()),
            Err(e) => Err(e),
        }
    }

    // -------------------------------------------------------------------------
    // Playback Negotiation & Progress Reporting
    // -------------------------------------------------------------------------

    /// Negotiate direct-play sources & mint `StreamTicket` URLs (on embygo).
    ///
    /// On `embygo`, omits `DeviceProfile` so the server returns all original versions
    /// without risk of false rejection (matching embygo's own reference web client).
    /// On `Emby`/`Jellyfin`, sends Vedro's universal direct-play profile.
    pub async fn playback_info(
        &self,
        item_id: &str,
        media_source_id: Option<&str>,
        audio_stream_index: Option<i32>,
        subtitle_stream_index: Option<i32>,
    ) -> Result<PlaybackInfoResponse> {
        let uid = self.require_user_id()?;
        let caps = self.capabilities();
        let req = PlaybackInfoRequest {
            user_id: Some(uid),
            media_source_id: media_source_id.map(ToString::to_string),
            audio_stream_index,
            subtitle_stream_index,
            enable_direct_play: Some(true),
            enable_direct_stream: Some(true),
            enable_transcoding: Some(false),
            device_profile: if caps.omit_device_profile_on_playback_info
                || caps.dialect == ServerDialect::EmbyGo
            {
                None
            } else {
                Some(DeviceProfile::vedro_universal())
            },
        };
        let body = serde_json::to_value(&req)?;
        let resp: PlaybackInfoResponse = self
            .request_json(
                Method::POST,
                &format!("Items/{item_id}/PlaybackInfo"),
                &[],
                Some(body),
            )
            .await?;

        // Auto-detect embygo StreamTicket usage if present in any DirectStreamUrl
        if resp.media_sources.iter().any(|s| {
            s.direct_stream_url
                .as_deref()
                .map(url_has_stream_ticket)
                .unwrap_or(false)
        }) {
            let mut st = self.state.write();
            st.capabilities.uses_stream_tickets = true;
            if !resp.media_sources.iter().any(|s| s.supports_transcoding)
                && st.capabilities.dialect == ServerDialect::Unknown
            {
                st.capabilities.mark_embygo(None);
            }
        }

        if resp.media_sources.is_empty()
            || resp
                .error_code
                .as_deref()
                .map(|e| e.eq_ignore_ascii_case("NoCompatibleStream"))
                .unwrap_or(false)
        {
            return Err(ProtocolError::NoCompatibleStream(item_id.to_string()));
        }

        Ok(resp)
    }

    pub async fn report_playback_start(&self, payload: &PlaybackProgressPayload) -> Result<()> {
        let body = sanitize_progress_payload(payload);
        self.request_empty(Method::POST, "Sessions/Playing", &[], Some(body))
            .await
    }

    pub async fn report_playback_progress(&self, payload: &PlaybackProgressPayload) -> Result<()> {
        let body = sanitize_progress_payload(payload);
        self.request_empty(Method::POST, "Sessions/Playing/Progress", &[], Some(body))
            .await
    }

    pub async fn report_playback_stopped(&self, payload: &PlaybackProgressPayload) -> Result<()> {
        let body = sanitize_progress_payload(payload);
        self.request_empty(Method::POST, "Sessions/Playing/Stopped", &[], Some(body))
            .await
    }

    pub async fn report_playback_ping(&self, play_session_id: &str) -> Result<()> {
        if play_session_id.is_empty() {
            return Ok(());
        }
        match self
            .request_empty(
                Method::POST,
                "Sessions/Playing/Ping",
                &[("PlaySessionId", play_session_id.to_string())],
                None,
            )
            .await
        {
            Ok(()) => Ok(()),
            Err(ProtocolError::NotFound(_)) => Ok(()),
            Err(e) => Err(e),
        }
    }

    // -------------------------------------------------------------------------
    // User State: Favorites, Watched, Playlists (片单)
    // -------------------------------------------------------------------------

    pub async fn set_favorite(&self, item_id: &str, favorite: bool) -> Result<UserItemDataDto> {
        let uid = self.require_user_id()?;
        let method = if favorite {
            Method::POST
        } else {
            Method::DELETE
        };
        self.request_json(
            method,
            &format!("Users/{uid}/FavoriteItems/{item_id}"),
            &[],
            None,
        )
        .await
    }

    pub async fn set_played(&self, item_id: &str, played: bool) -> Result<UserItemDataDto> {
        let uid = self.require_user_id()?;
        let method = if played { Method::POST } else { Method::DELETE };
        self.request_json(
            method,
            &format!("Users/{uid}/PlayedItems/{item_id}"),
            &[],
            None,
        )
        .await
    }

    pub async fn playlists(&self) -> Result<ItemsResult<BaseItemDto>> {
        self.request_json(Method::GET, "Playlists", &[], None).await
    }

    pub async fn playlist_items(&self, playlist_id: &str) -> Result<ItemsResult<BaseItemDto>> {
        self.request_json(
            Method::GET,
            &format!("Playlists/{playlist_id}/Items"),
            &[("EnableUserData", "true".into())],
            None,
        )
        .await
    }

    pub async fn create_playlist(
        &self,
        name: &str,
        item_ids: &[String],
    ) -> Result<PlaylistCreated> {
        let mut q = vec![("Name", name.to_string()), ("MediaType", "Video".into())];
        if !item_ids.is_empty() {
            q.push(("Ids", item_ids.join(",")));
        }
        self.request_json(Method::POST, "Playlists", &q, None).await
    }

    pub async fn add_to_playlist(&self, playlist_id: &str, item_ids: &[String]) -> Result<()> {
        if item_ids.is_empty() {
            return Ok(());
        }
        self.request_empty(
            Method::POST,
            &format!("Playlists/{playlist_id}/Items"),
            &[("Ids", item_ids.join(","))],
            None,
        )
        .await
    }

    pub async fn remove_from_playlist(
        &self,
        playlist_id: &str,
        entry_ids: &[String],
    ) -> Result<()> {
        if entry_ids.is_empty() {
            return Ok(());
        }
        self.request_empty(
            Method::DELETE,
            &format!("Playlists/{playlist_id}/Items"),
            &[("EntryIds", entry_ids.join(","))],
            None,
        )
        .await
    }

    // -------------------------------------------------------------------------
    // EmbyGo Admin & Diagnostics
    // -------------------------------------------------------------------------

    pub async fn embygo_status(&self) -> Result<EmbyGoStatus> {
        self.request_json(Method::GET, "emby-compat/status", &[], None)
            .await
    }

    pub async fn item_counts(&self) -> Result<ItemCounts> {
        self.request_json(Method::GET, "Items/Counts", &[], None)
            .await
    }

    pub async fn sessions(&self, now_playing_only: bool) -> Result<Vec<SessionInfoDto>> {
        let mut q = Vec::new();
        if now_playing_only {
            q.push(("NowPlaying", "true".to_string()));
        }
        self.request_json(Method::GET, "Sessions", &q, None).await
    }

    pub async fn trigger_library_refresh(&self) -> Result<()> {
        self.request_empty(Method::POST, "Library/Refresh", &[], None)
            .await
    }

    /// Build the authenticated WebSocket URL (`/embywebsocket` or `/socket`).
    pub fn websocket_url(&self) -> Result<Url> {
        let token = self
            .access_token()
            .ok_or_else(|| ProtocolError::Unauthorized("not signed in".into()))?;
        let ws_path = self.capabilities().websocket_path;
        let mut url = self.endpoint_url(&ws_path)?;
        let scheme = match url.scheme() {
            "https" => "wss",
            _ => "ws",
        };
        url.set_scheme(scheme)
            .map_err(|_| ProtocolError::WebSocket("failed to switch scheme to ws/wss".into()))?;
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("api_key", &token);
            q.append_pair("deviceId", &self.identity.device_id);
        }
        Ok(url)
    }
}

fn normalize_base_url(raw: &str) -> Result<Url> {
    let trimmed = raw.trim().trim_end_matches('/');
    let candidate = if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
        trimmed.to_string()
    } else {
        format!("http://{trimmed}")
    };
    let parsed = Url::parse(&candidate)?;
    Ok(parsed)
}

fn sanitize_progress_payload(payload: &PlaybackProgressPayload) -> serde_json::Value {
    let mut copy = payload.clone();
    // embygo strictly rejects PlayMethod=Transcode; Vedro always direct-plays.
    if copy.play_method.is_empty() || copy.play_method.eq_ignore_ascii_case("transcode") {
        warn!("forcing PlayMethod=DirectPlay for direct-play server compliance");
        copy.play_method = "DirectPlay".to_string();
    }
    serde_json::to_value(copy).unwrap_or_default()
}
