use serde::{Deserialize, Serialize};

use crate::models::PublicSystemInfo;

/// Detected media server implementation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ServerDialect {
    /// Native embygo server: zero-transcode direct play, StreamTicket URLs,
    /// Popular, Suggestions, HideFromResume, numeric facet IDs, bounded connections.
    #[serde(rename = "embygo")]
    EmbyGo,
    /// Official Emby Server (4.7/4.8/4.9+).
    Emby,
    /// Jellyfin Server (10.8/10.9/10.10+).
    Jellyfin,
    /// Unknown server speaking Emby-compatible REST API.
    #[default]
    Unknown,
}

impl ServerDialect {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::EmbyGo => "embygo",
            Self::Emby => "emby",
            Self::Jellyfin => "jellyfin",
            Self::Unknown => "unknown",
        }
    }
}

/// Runtime capability profile inferred from server probe & responses.
/// Designed to gracefully adopt future embygo / Emby / Jellyfin endpoints
/// without hard-coding rigid version gates.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerCapabilities {
    pub dialect: ServerDialect,
    pub server_id: String,
    pub server_name: String,
    pub advertised_version: String,
    pub embygo_build_version: Option<String>,
    /// True only when server supports transcoding; always false on embygo.
    pub supports_transcoding: bool,
    /// Always true on embygo/Emby/Jellyfin for Vedro's native decoder.
    pub supports_direct_play: bool,
    /// embygo extension: `GET /Users/{id}/Items/Popular`.
    pub supports_popular: bool,
    /// `GET /Users/{id}/Suggestions`.
    pub supports_suggestions: bool,
    /// `POST/DELETE /Users/{id}/Items/{itemId}/HideFromResume`.
    pub supports_hide_from_resume: bool,
    /// `POST /Sessions/Playing/Ping` keepalive.
    pub supports_playing_ping: bool,
    /// `GET /MediaSegments/{id}` (Skip Intro / Credits).
    pub supports_media_segments: bool,
    /// True if server uses short-lived `StreamTicket` query tokens on media URLs.
    pub uses_stream_tickets: bool,
    /// True when omitting `DeviceProfile` in `PlaybackInfo` yields all direct sources
    /// without false rejections (recommended for embygo).
    pub omit_device_profile_on_playback_info: bool,
    /// Conservative max concurrent HTTP stream connections per play session.
    /// embygo defaults to 4; we stay at <= 2 so seeks never trigger HTTP 429.
    pub max_stream_connections_per_session: usize,
    /// Preferred WebSocket path (`/embywebsocket` for Emby/embygo, `/socket` for Jellyfin).
    pub websocket_path: String,
    /// Optional path prefix (`/emby` or empty `""`).
    pub api_prefix: String,
}

impl Default for ServerCapabilities {
    fn default() -> Self {
        Self {
            dialect: ServerDialect::Unknown,
            server_id: String::new(),
            server_name: String::new(),
            advertised_version: String::new(),
            embygo_build_version: None,
            supports_transcoding: false,
            supports_direct_play: true,
            supports_popular: false,
            supports_suggestions: true,
            supports_hide_from_resume: true,
            supports_playing_ping: true,
            supports_media_segments: true,
            uses_stream_tickets: false,
            omit_device_profile_on_playback_info: false,
            max_stream_connections_per_session: 2,
            websocket_path: "/embywebsocket".to_string(),
            api_prefix: String::new(),
        }
    }
}

impl ServerCapabilities {
    pub fn is_embygo(&self) -> bool {
        self.dialect == ServerDialect::EmbyGo
    }

    /// Build capability profile from `System/Info/Public`, response headers,
    /// and optional embygo signature hints.
    pub fn detect(
        info: &PublicSystemInfo,
        server_header: Option<&str>,
        emby_version_header: Option<&str>,
        is_embygo_hint: bool,
    ) -> Self {
        let product = info.product_name.as_deref().unwrap_or("").to_lowercase();
        let server_name = info.server_name.clone().unwrap_or_default();
        let name_lower = server_name.to_lowercase();
        let hdr_lower = server_header.unwrap_or("").to_lowercase();
        let version = info
            .version
            .clone()
            .or_else(|| emby_version_header.map(ToString::to_string))
            .unwrap_or_default();

        let dialect = if is_embygo_hint
            || product.contains("embygo")
            || hdr_lower.contains("embygo")
            || name_lower.contains("embygo")
        {
            ServerDialect::EmbyGo
        } else if product.contains("jellyfin")
            || hdr_lower.contains("jellyfin")
            || version.starts_with("10.")
        {
            ServerDialect::Jellyfin
        } else if product.contains("emby")
            || emby_version_header.is_some()
            || version.starts_with("4.")
        {
            ServerDialect::Emby
        } else {
            ServerDialect::Unknown
        };

        match dialect {
            ServerDialect::EmbyGo => Self {
                dialect,
                server_id: info.id.clone().unwrap_or_default(),
                server_name,
                advertised_version: version,
                embygo_build_version: None,
                supports_transcoding: false,
                supports_direct_play: true,
                supports_popular: true,
                supports_suggestions: true,
                supports_hide_from_resume: true,
                supports_playing_ping: true,
                supports_media_segments: true,
                uses_stream_tickets: true,
                omit_device_profile_on_playback_info: true,
                max_stream_connections_per_session: 2,
                websocket_path: "/embywebsocket".to_string(),
                api_prefix: String::new(),
            },
            ServerDialect::Jellyfin => Self {
                dialect,
                server_id: info.id.clone().unwrap_or_default(),
                server_name,
                advertised_version: version,
                embygo_build_version: None,
                supports_transcoding: true,
                supports_direct_play: true,
                supports_popular: false,
                supports_suggestions: true,
                supports_hide_from_resume: false,
                supports_playing_ping: false,
                supports_media_segments: true,
                uses_stream_tickets: false,
                omit_device_profile_on_playback_info: false,
                max_stream_connections_per_session: 2,
                websocket_path: "/socket".to_string(),
                api_prefix: String::new(),
            },
            ServerDialect::Emby | ServerDialect::Unknown => Self {
                dialect,
                server_id: info.id.clone().unwrap_or_default(),
                server_name,
                advertised_version: version,
                embygo_build_version: None,
                supports_transcoding: true,
                supports_direct_play: true,
                supports_popular: false,
                supports_suggestions: true,
                supports_hide_from_resume: true,
                supports_playing_ping: true,
                supports_media_segments: true,
                uses_stream_tickets: false,
                omit_device_profile_on_playback_info: false,
                max_stream_connections_per_session: 2,
                websocket_path: "/embywebsocket".to_string(),
                api_prefix: String::new(),
            },
        }
    }

    /// Upgrade capabilities in-place if a subsequent probe discovers embygo-specific
    /// signals (e.g. `StreamTicket` in `DirectStreamUrl`, `/emby-compat/status` 200/403,
    /// or `/Users/{id}/Items/Popular` 200).
    pub fn mark_embygo(&mut self, build_version: Option<String>) {
        self.dialect = ServerDialect::EmbyGo;
        if build_version.is_some() {
            self.embygo_build_version = build_version;
        }
        self.supports_transcoding = false;
        self.supports_popular = true;
        self.supports_suggestions = true;
        self.supports_hide_from_resume = true;
        self.supports_playing_ping = true;
        self.uses_stream_tickets = true;
        self.omit_device_profile_on_playback_info = true;
        self.max_stream_connections_per_session = 2;
        self.websocket_path = "/embywebsocket".to_string();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_embygo_emby_and_jellyfin() {
        let embygo_info = PublicSystemInfo {
            id: Some("srv-1".into()),
            server_name: Some("My EmbyGo".into()),
            version: Some("4.8.11.0".into()),
            product_name: Some("embygo".into()),
            ..Default::default()
        };
        let caps = ServerCapabilities::detect(&embygo_info, None, Some("4.8.11.0"), false);
        assert_eq!(caps.dialect, ServerDialect::EmbyGo);
        assert_eq!(serde_json::to_string(&caps.dialect).unwrap(), "\"embygo\"");
        assert!(!caps.supports_transcoding);
        assert!(caps.supports_popular);
        assert!(caps.uses_stream_tickets);
        assert_eq!(caps.max_stream_connections_per_session, 2);

        let jf_info = PublicSystemInfo {
            id: Some("jf-1".into()),
            server_name: Some("Home Jellyfin".into()),
            version: Some("10.10.3".into()),
            product_name: Some("Jellyfin Server".into()),
            ..Default::default()
        };
        let jf_caps = ServerCapabilities::detect(&jf_info, None, None, false);
        assert_eq!(jf_caps.dialect, ServerDialect::Jellyfin);
        assert_eq!(jf_caps.websocket_path, "/socket");

        let emby_info = PublicSystemInfo {
            id: Some("em-1".into()),
            server_name: Some("Media".into()),
            version: Some("4.8.10.0".into()),
            product_name: Some("Emby Server".into()),
            ..Default::default()
        };
        let em_caps = ServerCapabilities::detect(&emby_info, None, Some("4.8.10.0"), false);
        assert_eq!(em_caps.dialect, ServerDialect::Emby);
        assert_eq!(em_caps.websocket_path, "/embywebsocket");
    }
}
