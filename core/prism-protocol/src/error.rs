use thiserror::Error;

/// Unified error type for Emby / Jellyfin / embygo protocol operations.
#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("invalid server URL: {0}")]
    InvalidUrl(#[from] url::ParseError),

    #[error("network transport error: {0}")]
    Transport(#[from] reqwest::Error),

    #[error("serialization error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("authentication required or expired (HTTP 401): {0}")]
    Unauthorized(String),

    #[error("access forbidden (HTTP 403): {0}")]
    Forbidden(String),

    #[error("resource not found (HTTP 404): {0}")]
    NotFound(String),

    #[error("rate or connection limit exceeded (HTTP 429, retry after {retry_after_secs:?}s): {message}")]
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

pub type Result<T> = std::result::Result<T, ProtocolError>;
