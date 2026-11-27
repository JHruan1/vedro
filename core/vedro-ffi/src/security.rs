use std::time::Duration;

use parking_lot::Mutex;
use serde_json::Value;
use vedro_protocol::EmbyClient;

pub(crate) const MAX_SUBTITLE_BYTES: usize = 16 * 1024 * 1024;
pub(crate) const MAX_DANMAKU_BYTES: usize = 16 * 1024 * 1024;
pub(crate) const MAX_AI_JSON_BYTES: usize = 4 * 1024 * 1024;
pub(crate) const MAX_UPDATE_BYTES: u64 = 512 * 1024 * 1024;

/// Process-wide respectful rate limiter for shared public Bilibili APIs (`*.bilibili.com`).
/// Guarantees strictly 1 concurrent request, >= 2400ms inter-completion pacing, and shared
/// exponential cooldown on 429/5xx across ALL translation / model-list / test entrypoints.
struct BilibiliLimiterState {
    last_completed_at: Option<std::time::Instant>,
    cooldown_until: Option<std::time::Instant>,
    consecutive_errors: u32,
}

pub(crate) struct BilibiliRateLimiter {
    sem: tokio::sync::Semaphore,
    state: Mutex<BilibiliLimiterState>,
}

static BILIBILI_LIMITER: std::sync::OnceLock<BilibiliRateLimiter> = std::sync::OnceLock::new();

pub(crate) fn bilibili_limiter() -> &'static BilibiliRateLimiter {
    BILIBILI_LIMITER.get_or_init(|| BilibiliRateLimiter {
        sem: tokio::sync::Semaphore::new(1),
        state: Mutex::new(BilibiliLimiterState {
            last_completed_at: None,
            cooldown_until: None,
            consecutive_errors: 0,
        }),
    })
}

impl BilibiliRateLimiter {
    pub(crate) async fn acquire_slot(&self) -> Result<tokio::sync::SemaphorePermit<'_>, String> {
        let permit = self
            .sem
            .acquire()
            .await
            .map_err(|_| "限流器已关闭".to_string())?;
        let wait_dur = {
            let st = self.state.lock();
            let now = std::time::Instant::now();
            let mut wait = Duration::ZERO;
            if let Some(until) = st.cooldown_until {
                if until > now {
                    wait = wait.max(until.duration_since(now));
                }
            }
            if let Some(last) = st.last_completed_at {
                let elapsed = now.duration_since(last);
                let min_gap = Duration::from_millis(2400);
                if elapsed < min_gap {
                    wait = wait.max(min_gap - elapsed);
                }
            }
            wait
        };
        if !wait_dur.is_zero() {
            tokio::time::sleep(wait_dur).await;
        }
        Ok(permit)
    }

    pub(crate) fn record_success(&self) {
        let mut st = self.state.lock();
        st.last_completed_at = Some(std::time::Instant::now());
        st.cooldown_until = None;
        st.consecutive_errors = 0;
    }

    pub(crate) fn record_failure(&self, is_rate_or_server_err: bool) {
        let mut st = self.state.lock();
        let now = std::time::Instant::now();
        st.last_completed_at = Some(now);
        if is_rate_or_server_err {
            st.consecutive_errors = st.consecutive_errors.saturating_add(1);
            let backoff_secs = match st.consecutive_errors {
                1 => 6,
                2 => 15,
                _ => 45,
            };
            st.cooldown_until = Some(now + Duration::from_secs(backoff_secs));
        }
    }
}

pub(crate) fn validate_http_url(raw: &str) -> Result<url::Url, String> {
    let parsed = url::Url::parse(raw.trim()).map_err(|e| format!("无效的 URL: {e}"))?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return Err("仅支持 http:// 或 https:// 协议地址".to_string());
    }
    Ok(parsed)
}

pub(crate) fn is_safe_path_token(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

pub(crate) fn is_bilibili_index_url(base_url: &str) -> bool {
    url::Url::parse(base_url.trim())
        .ok()
        .and_then(|u| {
            u.host_str().map(|h| {
                let lower = h.to_ascii_lowercase();
                lower == "index-translate.bilibili.com" || lower.ends_with(".bilibili.com")
            })
        })
        .unwrap_or(false)
}

pub(crate) fn same_origin_as_client(client: &EmbyClient, target_url: &str) -> bool {
    let Ok(target) = url::Url::parse(target_url) else {
        return false;
    };
    let base = client.base_url();
    target.scheme().eq_ignore_ascii_case(base.scheme())
        && target
            .host_str()
            .map(|h| h.to_ascii_lowercase())
            .eq(&base.host_str().map(|h| h.to_ascii_lowercase()))
        && target.port_or_known_default() == base.port_or_known_default()
}

pub(crate) async fn read_reqwest_body_capped(
    resp: reqwest::Response,
    max_bytes: usize,
) -> Result<Vec<u8>, String> {
    use futures_util::StreamExt;
    if let Some(cl) = resp.content_length() {
        if usize::try_from(cl).unwrap_or(usize::MAX) > max_bytes {
            return Err(format!(
                "响应体积超过上限 ({} MB)",
                (max_bytes / (1024 * 1024)).max(1)
            ));
        }
    }
    let mut buf = Vec::with_capacity(
        resp.content_length()
            .and_then(|n| usize::try_from(n).ok())
            .map(|n| n.min(max_bytes))
            .unwrap_or(64 * 1024),
    );
    let mut stream = resp.bytes_stream();
    while let Some(chunk_res) = stream.next().await {
        let chunk = chunk_res.map_err(|e| vedro_protocol::error::format_transport_error(&e))?;
        if buf.len().saturating_add(chunk.len()) > max_bytes {
            return Err(format!(
                "响应体积超过上限 ({} MB)",
                (max_bytes / (1024 * 1024)).max(1)
            ));
        }
        buf.extend_from_slice(&chunk);
    }
    Ok(buf)
}

pub(crate) async fn read_json_capped(
    resp: reqwest::Response,
    max_bytes: usize,
) -> Result<Value, String> {
    let raw = read_reqwest_body_capped(resp, max_bytes).await?;
    serde_json::from_slice(&raw).map_err(|e| e.to_string())
}

pub(crate) fn str_param(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(ToString::to_string)
        .ok_or_else(|| format!("missing required string parameter `{key}`"))
}

pub(crate) fn container_mime_type(container: &str) -> String {
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
