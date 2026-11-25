use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, USER_AGENT};
use serde::{Deserialize, Serialize};

/// Client identity sent in `X-Emby-Authorization` and `Authorization` headers.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientIdentity {
    pub client_name: String,
    pub device_name: String,
    pub device_id: String,
    pub app_version: String,
}

impl Default for ClientIdentity {
    fn default() -> Self {
        Self {
            client_name: "Prism Player".to_string(),
            device_name: default_device_name(),
            device_id: uuid::Uuid::new_v4().to_string(),
            app_version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }
}

fn default_device_name() -> String {
    match std::env::consts::OS {
        "macos" => "macOS".to_string(),
        "ios" => "iOS".to_string(),
        "android" => "Android".to_string(),
        "windows" => "Windows".to_string(),
        other => other.to_string(),
    }
}

fn sanitize_header_value(input: &str) -> String {
    input
        .chars()
        .filter(|c| !matches!(c, '"' | '\r' | '\n' | '\\'))
        .collect()
}

impl ClientIdentity {
    /// Emby/Jellyfin/embygo compatible authorization header string.
    /// Always sends `MediaBrowser Client="...", Device="...", DeviceId="...", Version="..."`
    /// plus `Token="..."` when authenticated.
    pub fn authorization_header(&self, token: Option<&str>) -> String {
        let mut parts = vec![
            format!("Client=\"{}\"", sanitize_header_value(&self.client_name)),
            format!("Device=\"{}\"", sanitize_header_value(&self.device_name)),
            format!("DeviceId=\"{}\"", sanitize_header_value(&self.device_id)),
            format!("Version=\"{}\"", sanitize_header_value(&self.app_version)),
        ];
        if let Some(tok) = token.filter(|t| !t.is_empty()) {
            parts.push(format!("Token=\"{}\"", sanitize_header_value(tok)));
        }
        format!("MediaBrowser {}", parts.join(", "))
    }

    pub fn user_agent(&self) -> String {
        format!(
            "{}/{} ({})",
            sanitize_header_value(&self.client_name),
            sanitize_header_value(&self.app_version),
            sanitize_header_value(&self.device_name),
        )
    }

    /// Build request headers for REST API calls.
    /// Credentials live strictly in headers (never query params) so the client works even
    /// when `embygo` sets `security.allow_query_credentials: false`.
    pub fn build_headers(&self, token: Option<&str>) -> HeaderMap {
        let mut headers = HeaderMap::new();
        let auth = self.authorization_header(token);
        if let Ok(val) = HeaderValue::from_str(&auth) {
            headers.insert("X-Emby-Authorization", val.clone());
            headers.insert(AUTHORIZATION, val);
        }
        if let Some(tok) = token.filter(|t| !t.is_empty()) {
            if let Ok(val) = HeaderValue::from_str(tok) {
                headers.insert("X-Emby-Token", val);
            }
        }
        if let Ok(ua) = HeaderValue::from_str(&self.user_agent()) {
            headers.insert(USER_AGENT, ua);
        }
        headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
        headers
    }
}

/// Checks whether a resolved media/subtitle URL already carries a short-lived `StreamTicket`.
/// Per embygo security contract: when `StreamTicket` is present, NEVER append `api_key` or
/// a long-lived bearer token to the URL query string.
pub fn url_has_stream_ticket(url_str: &str) -> bool {
    if let Ok(parsed) = url::Url::parse(url_str) {
        return parsed
            .query_pairs()
            .any(|(k, v)| k.eq_ignore_ascii_case("StreamTicket") && !v.is_empty());
    }
    url_str.contains("StreamTicket=") || url_str.contains("streamticket=")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_clean_auth_headers_and_detects_stream_ticket() {
        let id = ClientIdentity {
            client_name: "Prism Player".into(),
            device_name: "MacBook Pro".into(),
            device_id: "dev-123".into(),
            app_version: "0.1.0".into(),
        };
        let hdr = id.authorization_header(Some("tok-secret"));
        assert!(hdr.starts_with("MediaBrowser "));
        assert!(hdr.contains("Client=\"Prism Player\""));
        assert!(hdr.contains("DeviceId=\"dev-123\""));
        assert!(hdr.contains("Token=\"tok-secret\""));

        let headers = id.build_headers(Some("tok-secret"));
        assert_eq!(headers.get("X-Emby-Token").unwrap(), "tok-secret");
        assert!(headers.get("X-Emby-Authorization").is_some());
        assert!(headers.get(AUTHORIZATION).is_some());

        assert!(url_has_stream_ticket(
            "https://media.example/Videos/1/stream.mkv?MediaSourceId=2&StreamTicket=abc123"
        ));
        assert!(!url_has_stream_ticket(
            "https://media.example/Videos/1/stream.mkv?MediaSourceId=2&Static=true"
        ));
    }
}
