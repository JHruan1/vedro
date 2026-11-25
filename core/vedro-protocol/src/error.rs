use std::error::Error as StdError;
use thiserror::Error;

/// Format a `reqwest::Error` with its full underlying `source()` chain
/// (DNS failure, TLS cert error, proxy error, TCP reset, timeout, etc.).
pub fn format_transport_error(err: &reqwest::Error) -> String {
    let mut parts = vec![err.to_string()];
    let mut current = err.source();
    while let Some(src) = current {
        let msg = src.to_string();
        if !parts.last().map(|p| p.contains(&msg)).unwrap_or(false) {
            parts.push(msg);
        }
        current = src.source();
    }
    parts.join(" -> ")
}

/// Unified error type for Emby / Jellyfin / embygo protocol operations.
#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("invalid server URL: {0}")]
    InvalidUrl(#[from] url::ParseError),

    #[error("network transport error: {0}")]
    Transport(String),

    #[error("serialization error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("authentication required or expired (HTTP 401): {0}")]
    Unauthorized(String),

    #[error("access forbidden (HTTP 403): {0}")]
    Forbidden(String),

    #[error("resource not found (HTTP 404): {0}")]
    NotFound(String),

    #[error(
        "rate or connection limit exceeded (HTTP 429, retry after {retry_after_secs:?}s): {message}"
    )]
    RateLimited {
        retry_after_secs: Option<u64>,
        message: String,
    },

    #[error("server returned HTTP {status}: {message}")]
    Api { status: u16, message: String },

    #[error("no compatible direct-play stream available for item {0}")]
    NoCompatibleStream(String),

    #[error("websocket error: {0}")]
    WebSocket(String),

    #[error("discovery error: {0}")]
    Discovery(String),
}

impl From<reqwest::Error> for ProtocolError {
    fn from(err: reqwest::Error) -> Self {
        Self::Transport(format_transport_error(&err))
    }
}

pub type Result<T> = std::result::Result<T, ProtocolError>;
