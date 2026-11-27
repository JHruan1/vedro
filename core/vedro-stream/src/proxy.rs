use std::net::SocketAddr;
use std::num::NonZeroUsize;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use bytes::Bytes;
use dashmap::mapref::entry::Entry;
use dashmap::DashMap;
use futures_util::StreamExt;
use http::header::HeaderValue;
use http::{header, Method, Request, Response, StatusCode};
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Full, StreamBody};
use hyper::body::{Frame, Incoming};
use hyper::service::service_fn;
use hyper_util::rt::{TokioIo, TokioTimer};
use lru::LruCache;
use parking_lot::{Mutex, RwLock};
use reqwest::header::HeaderMap;
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch, Semaphore};
use tracing::{debug, info, warn};

use crate::cache::{CacheStats, ChunkCache, DEFAULT_CHUNK_SIZE};

type ProxyBody = BoxBody<Bytes, std::io::Error>;

const MAX_IMAGE_BYTES: usize = 12 * 1024 * 1024;
const MAX_RAM_IMAGE_CACHE_BYTES: usize = if cfg!(any(target_os = "android", target_os = "ios")) {
    24 * 1024 * 1024
} else {
    64 * 1024 * 1024
};
const MAX_DISK_IMAGE_CACHE_BYTES: u64 = 256 * 1024 * 1024;
const MAX_DISK_IMAGE_FILES: usize = 2400;
const MAX_REDIRECT_HOPS: usize = 10;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamProxyConfig {
    /// Total RAM cache budget across active sessions (default: 64 MiB).
    pub cache_bytes: u64,
    /// Size of each cached chunk (default: 1 MiB).
    pub chunk_size: u64,
    /// Max concurrent upstream HTTP connections per session.
    /// embygo defaults to `max_connections_per_session = 4`; keeping this at 2 guarantees
    /// smooth playback + seek + lookahead without ever tripping HTTP 429!
    pub max_upstream_conns_per_session: usize,
    /// Number of sequential chunks to read ahead after a read miss.
    pub prefetch_chunks: u64,
}

impl Default for StreamProxyConfig {
    fn default() -> Self {
        Self {
            cache_bytes: if cfg!(any(target_os = "android", target_os = "ios")) {
                32 * 1024 * 1024
            } else {
                64 * 1024 * 1024
            },
            chunk_size: DEFAULT_CHUNK_SIZE,
            max_upstream_conns_per_session: 2,
            prefetch_chunks: 4,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StreamProxyStats {
    pub listen_addr: String,
    pub active_sessions: usize,
    pub active_upstream_connections: usize,
    pub total_upstream_bytes: u64,
    pub total_served_bytes: u64,
    pub rate_limit_retries: u64,
    pub ticket_rotations: u64,
    pub throughput_mbps: f64,
    pub current_speed_bytes_per_sec: u64,
    pub cache: CacheStats,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ImageCacheStats {
    pub disk_files: usize,
    pub disk_bytes: u64,
    pub memory_entries: usize,
    pub cache_dir: Option<String>,
}

struct RegisteredStream {
    cache_key: u64,
    upstream_url: RwLock<String>,
    headers: RwLock<HeaderMap>,
    total_size: AtomicU64,
    content_type: RwLock<String>,
    /// Strict per-session connection semaphore to respect embygo's connection cap.
    upstream_sem: Arc<Semaphore>,
    /// Cancel-safe singleflight deduplication via `watch` channel (zero lost wakeups).
    in_flight: DashMap<u64, watch::Receiver<bool>>,
    ticket_rotations: AtomicU64,
}

struct ByteBoundedImageCache {
    lru: LruCache<String, (String, Bytes)>,
    total_bytes: usize,
    max_bytes: usize,
}

impl ByteBoundedImageCache {
    fn new(max_entries: usize, max_bytes: usize) -> Self {
        Self {
            lru: LruCache::new(NonZeroUsize::new(max_entries.max(16)).expect("max_entries >= 16")),
            total_bytes: 0,
            max_bytes,
        }
    }

    fn get(&mut self, key: &str) -> Option<(String, Bytes)> {
        self.lru.get(key).cloned()
    }

    fn put(&mut self, key: String, ct: String, data: Bytes) {
        let sz = data.len();
        if sz > self.max_bytes {
            return;
        }
        if let Some((_, old)) = self.lru.pop(&key) {
            self.total_bytes = self.total_bytes.saturating_sub(old.len());
        }
        while self.total_bytes + sz > self.max_bytes {
            if let Some((_, (_, evicted))) = self.lru.pop_lru() {
                self.total_bytes = self.total_bytes.saturating_sub(evicted.len());
            } else {
                break;
            }
        }
        if let Some((_, (_, evicted))) = self.lru.push(key, (ct, data)) {
            self.total_bytes = self.total_bytes.saturating_sub(evicted.len());
        }
        self.total_bytes = self.total_bytes.saturating_add(sz);
    }

    fn len(&self) -> usize {
        self.lru.len()
    }

    fn clear(&mut self) {
        self.lru.clear();
        self.total_bytes = 0;
    }
}

/// RAII guard that removes a singleflight key and wakes all waiters even on task cancel/panic.
struct SingleflightGuard<'a, K: Eq + std::hash::Hash + Clone> {
    map: &'a DashMap<K, watch::Receiver<bool>>,
    key: K,
    tx: Option<watch::Sender<bool>>,
}

impl<K: Eq + std::hash::Hash + Clone> Drop for SingleflightGuard<'_, K> {
    fn drop(&mut self) {
        self.map.remove(&self.key);
        if let Some(tx) = self.tx.take() {
            let _ = tx.send(true);
        }
    }
}

/// RAII guard for accurate `active_conns` tracking even on async cancellation.
struct ActiveConnGuard<'a>(&'a AtomicUsize);

impl<'a> ActiveConnGuard<'a> {
    fn new(counter: &'a AtomicUsize) -> Self {
        counter.fetch_add(1, Ordering::Relaxed);
        Self(counter)
    }
}

impl Drop for ActiveConnGuard<'_> {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

/// High-performance local loopback HTTP Range streaming proxy & prefetch buffer.
///
/// Sits between `libmpv` / native players and `embygo` / `Emby` / `Jellyfin`:
/// - Streams chunks zero-copy as they arrive via `StreamBody` (cuts seek latency & prevents OOM).
/// - Strictly bounds upstream connections (`<= 2` per play session) to stay under embygo's cap.
/// - Strips auth headers (`Authorization`, `X-Emby-Token`, `X-Emby-Authorization`, `Cookie`) on
///   cross-origin 302 redirects (Alist/OSS/S3/CDN safety).
/// - Locks down `/img/` and `/img-srv/` to validated image paths and `image/*` responses only.
/// - Handles HTTP 429 `Retry-After` backoff cleanly with cancel-safe singleflight deduplication.
pub struct StreamProxy {
    listen_addr: SocketAddr,
    http: RwLock<reqwest::Client>,
    transport_sig: RwLock<(Option<String>, bool)>,
    config: StreamProxyConfig,
    cache: ChunkCache,
    next_session_key: AtomicU64,
    streams: Arc<DashMap<String, Arc<RegisteredStream>>>,
    image_upstream_base: RwLock<Option<String>>,
    image_upstream_headers: RwLock<HeaderMap>,
    server_image_upstreams: DashMap<String, (String, HeaderMap)>,
    image_cache: Mutex<ByteBoundedImageCache>,
    image_cache_dir: RwLock<Option<PathBuf>>,
    image_sem: Semaphore,
    image_in_flight: DashMap<String, watch::Receiver<bool>>,
    disk_write_counter: AtomicUsize,
    active_conns: Arc<AtomicUsize>,
    conn_sem: Arc<Semaphore>,
    total_upstream_bytes: Arc<AtomicU64>,
    total_served_bytes: Arc<AtomicU64>,
    rate_limit_retries: Arc<AtomicU64>,
    /// 4-second 1s-bucket ring buffer `(epoch_sec, bytes)` for smooth, idempotent live speed readout.
    speed_buckets: Mutex<[(u64, u64); 4]>,
    started_at: Instant,
    shutdown_tx: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
}

fn build_proxy_http_client(
    proxy_url: Option<&str>,
    accept_invalid_certs: bool,
) -> std::io::Result<reqwest::Client> {
    let custom_proxy = proxy_url.map(str::trim).filter(|s| !s.is_empty());
    let build_once = |disable_native_certs: bool, disable_sys_proxy: bool| {
        let mut builder = reqwest::Client::builder()
            .pool_max_idle_per_host(12)
            .connect_timeout(Duration::from_secs(12))
            .timeout(Duration::from_secs(30))
            .tcp_nodelay(true)
            // Manual redirect loop strips X-Emby-Token / X-Emby-Authorization across origins!
            .redirect(reqwest::redirect::Policy::none())
            .danger_accept_invalid_certs(accept_invalid_certs);
        if disable_native_certs {
            builder = builder.tls_built_in_native_certs(false);
        }
        if disable_sys_proxy {
            builder = builder.no_proxy();
        } else if let Some(p) = custom_proxy {
            let proxy = reqwest::Proxy::all(p).map_err(std::io::Error::other)?;
            builder = builder.proxy(proxy);
        }
        builder.build().map_err(std::io::Error::other)
    };
    match build_once(false, false) {
        Ok(client) => Ok(client),
        Err(first_err) => {
            if custom_proxy.is_some() {
                // Retry with bundled WebPKI roots only in case the OS cert store failed
                build_once(true, false).map_err(|_| first_err)
            } else {
                warn!(
                    error = %first_err,
                    "proxy http client build failed with OS certs/proxy; falling back to bundled WebPKI roots + direct"
                );
                build_once(true, false)
                    .or_else(|_| build_once(true, true))
                    .map_err(|_| first_err)
            }
        }
    }
}

fn strip_auth_headers(headers: &mut HeaderMap) {
    headers.remove(reqwest::header::AUTHORIZATION);
    headers.remove(reqwest::header::COOKIE);
    headers.remove("x-emby-authorization");
    headers.remove("x-emby-token");
    headers.remove("x-mediabrowser-token");
    headers.remove("X-Emby-Authorization");
    headers.remove("X-Emby-Token");
    headers.remove("X-MediaBrowser-Token");
}

fn same_origin(a: &url::Url, b: &url::Url) -> bool {
    a.scheme().eq_ignore_ascii_case(b.scheme())
        && a.host_str()
            .map(|h| h.to_ascii_lowercase())
            .eq(&b.host_str().map(|h| h.to_ascii_lowercase()))
        && a.port_or_known_default() == b.port_or_known_default()
}

fn is_loopback_or_link_local(u: &url::Url) -> bool {
    let Some(host) = u.host_str() else {
        return true;
    };
    let lower = host.trim_matches(['[', ']']).to_ascii_lowercase();
    if lower == "localhost" || lower.ends_with(".localhost") {
        return true;
    }
    if let Ok(ip) = lower.parse::<std::net::IpAddr>() {
        return match ip {
            std::net::IpAddr::V4(v4) => {
                v4.is_loopback() || v4.is_link_local() || v4.is_unspecified()
            }
            std::net::IpAddr::V6(v6) => {
                if let Some(v4) = v6.to_ipv4_mapped().or_else(|| v6.to_ipv4()) {
                    return v4.is_loopback() || v4.is_link_local() || v4.is_unspecified();
                }
                v6.is_loopback() || v6.is_unspecified() || (v6.segments()[0] & 0xffc0) == 0xfe80
            }
        };
    }
    false
}

/// Follow up to `MAX_REDIRECT_HOPS` redirects while stripping auth headers on any cross-origin jump
/// and blocking public -> loopback/link-local SSRF pivots.
async fn send_with_safe_redirects(
    client: &reqwest::Client,
    initial_url: &str,
    initial_headers: HeaderMap,
) -> Result<reqwest::Response, reqwest::Error> {
    let initial_is_local = url::Url::parse(initial_url)
        .map(|u| is_loopback_or_link_local(&u))
        .unwrap_or(false);
    let mut current_url = initial_url.to_string();
    let mut current_headers = initial_headers;
    for _ in 0..=MAX_REDIRECT_HOPS {
        let resp = client
            .get(&current_url)
            .headers(current_headers.clone())
            .send()
            .await?;
        if resp.status().is_redirection() {
            if let Some(loc) = resp
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|v| v.to_str().ok())
            {
                if let Ok(base) = url::Url::parse(&current_url) {
                    if let Ok(next) = base.join(loc) {
                        if matches!(next.scheme(), "http" | "https") {
                            if !initial_is_local && is_loopback_or_link_local(&next) {
                                return Ok(resp);
                            }
                            let same_host = base
                                .host_str()
                                .map(|h| h.to_ascii_lowercase())
                                .eq(&next.host_str().map(|h| h.to_ascii_lowercase()));
                            let is_downgrade = base.scheme().eq_ignore_ascii_case("https")
                                && next.scheme().eq_ignore_ascii_case("http");
                            let is_https_upgrade = same_host
                                && base.scheme().eq_ignore_ascii_case("http")
                                && next.scheme().eq_ignore_ascii_case("https");
                            if is_downgrade || (!same_origin(&base, &next) && !is_https_upgrade) {
                                strip_auth_headers(&mut current_headers);
                            }
                            current_url = next.to_string();
                            continue;
                        }
                    }
                }
            }
        }
        return Ok(resp);
    }
    client
        .get(&current_url)
        .headers(current_headers)
        .send()
        .await
}

/// Read an upstream response body up to `max_bytes`, incrementing an optional live byte counter
/// per network frame. When `strict_reject_overflow` is true (e.g. cached artwork), returns an
/// error instead of returning a truncated corrupt payload.
async fn read_response_capped<F>(
    resp: reqwest::Response,
    max_bytes: usize,
    strict_reject_overflow: bool,
    mut on_bytes: F,
) -> Result<Bytes, StatusCode>
where
    F: FnMut(u64),
{
    if let Some(cl) = resp.content_length() {
        let cl_usize = usize::try_from(cl).unwrap_or(usize::MAX);
        if cl_usize > max_bytes
            && (strict_reject_overflow || resp.status() == reqwest::StatusCode::PARTIAL_CONTENT)
        {
            return Err(StatusCode::BAD_GATEWAY);
        }
    }
    let cap = resp
        .content_length()
        .and_then(|n| usize::try_from(n).ok())
        .map(|n| n.min(max_bytes))
        .unwrap_or_else(|| max_bytes.min(256 * 1024));
    let mut buf = Vec::with_capacity(cap);
    let mut stream = resp.bytes_stream();
    while let Some(chunk_res) = stream.next().await {
        let chunk = chunk_res.map_err(|_| StatusCode::BAD_GATEWAY)?;
        if strict_reject_overflow && buf.len().saturating_add(chunk.len()) > max_bytes {
            return Err(StatusCode::BAD_GATEWAY);
        }
        let remaining = max_bytes.saturating_sub(buf.len());
        if remaining == 0 {
            break;
        }
        let take = chunk.len().min(remaining);
        buf.extend_from_slice(&chunk[..take]);
        on_bytes(take as u64);
        if buf.len() >= max_bytes && !strict_reject_overflow {
            break;
        }
    }
    Ok(Bytes::from(buf))
}

fn is_safe_raster_image_mime(ct_lower: &str) -> bool {
    let media = ct_lower.split(';').next().unwrap_or("").trim();
    matches!(
        media,
        "image/jpeg"
            | "image/jpg"
            | "image/pjpeg"
            | "image/png"
            | "image/webp"
            | "image/gif"
            | "image/avif"
            | "image/heic"
            | "image/heif"
            | "image/bmp"
            | "image/x-ms-bmp"
            | "image/x-icon"
            | "image/vnd.microsoft.icon"
    )
}

/// Sniff raster image format from binary magic headers so valid images served with
/// `application/octet-stream` (common on CDN/OSS/EmbyGo caches) still render cleanly,
/// while HTML/JSON/SVG/JS payloads remain strictly blocked.
fn sniff_raster_image_mime(bytes: &[u8]) -> Option<&'static str> {
    if bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return Some("image/jpeg");
    }
    if bytes.len() >= 8 && &bytes[..8] == b"\x89PNG\r\n\x1A\n" {
        return Some("image/png");
    }
    if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    if bytes.len() >= 6 && (&bytes[..6] == b"GIF87a" || &bytes[..6] == b"GIF89a") {
        return Some("image/gif");
    }
    if bytes.len() >= 2 && &bytes[..2] == b"BM" {
        return Some("image/bmp");
    }
    if bytes.len() >= 12 && &bytes[4..8] == b"ftyp" {
        let brand = &bytes[8..12];
        if brand == b"avif" || brand == b"avis" {
            return Some("image/avif");
        }
        if brand == b"heic" || brand == b"heix" || brand == b"heif" || brand == b"mif1" {
            return Some("image/heif");
        }
    }
    if bytes.len() >= 4
        && bytes[0] == 0x00
        && bytes[1] == 0x00
        && bytes[2] == 0x01
        && bytes[3] == 0x00
    {
        return Some("image/x-icon");
    }
    None
}

fn prepare_image_headers(mut headers: HeaderMap) -> HeaderMap {
    headers.insert(
        reqwest::header::ACCEPT,
        HeaderValue::from_static("image/avif,image/webp,image/apng,image/*,*/*;q=0.8"),
    );
    headers
}

/// Deterministic 128-bit FNV-1a hex key for persistent on-disk artwork cache files.
fn image_disk_cache_filename(key: &str) -> String {
    let mut h1: u64 = 0xcbf29ce484222325;
    let mut h2: u64 = 0x84222325cbf29ce4;
    for &b in key.as_bytes() {
        h1 ^= b as u64;
        h1 = h1.wrapping_mul(0x100000001b3);
        h2 = h2.wrapping_mul(0x100000001b3) ^ (b as u64);
    }
    format!("{h1:016x}{h2:016x}")
}

/// Strict allowlist for `/img/` and `/img-srv/` relative paths so the local proxy can ONLY
/// fetch media artwork endpoints and can NEVER be abused to access Emby API / admin routes.
fn is_allowed_image_rel_path(rel_path: &str) -> bool {
    if rel_path.is_empty() || rel_path.len() > 512 {
        return false;
    }
    let lower = rel_path.to_ascii_lowercase();
    if lower.contains("..")
        || lower.contains('\\')
        || lower.contains('@')
        || lower.contains("%2e")
        || lower.contains("%5c")
        || lower.contains("%00")
        || rel_path.bytes().any(|b| b < 0x20 || b == 0x7F)
    {
        return false;
    }
    // Emby / Jellyfin / EmbyGo artwork paths always contain `/images/` segment
    let segs: Vec<&str> = rel_path.split('/').collect();
    segs.len() >= 3
        && segs
            .iter()
            .all(|s| !s.is_empty() && *s != "." && *s != "..")
        && segs.iter().any(|s| s.eq_ignore_ascii_case("Images"))
}

fn safe_header_value(raw: &str, fallback: &'static str) -> HeaderValue {
    HeaderValue::from_str(raw.trim()).unwrap_or_else(|_| HeaderValue::from_static(fallback))
}

fn full_body(bytes: Bytes) -> ProxyBody {
    Full::new(bytes).map_err(|never| match never {}).boxed()
}

fn simple_response(status: StatusCode, body: &'static str) -> Response<ProxyBody> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "text/plain; charset=utf-8")
        .body(full_body(Bytes::from_static(body.as_bytes())))
        .unwrap_or_else(|_| Response::new(full_body(Bytes::new())))
}

impl StreamProxy {
    pub async fn start(config: StreamProxyConfig) -> std::io::Result<Arc<Self>> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let listen_addr = listener.local_addr()?;

        let http = build_proxy_http_client(None, false)?;

        let (shutdown_tx, mut shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let cache = ChunkCache::new(config.cache_bytes, config.chunk_size);

        let proxy = Arc::new(Self {
            listen_addr,
            http: RwLock::new(http),
            transport_sig: RwLock::new((None, false)),
            config,
            cache,
            next_session_key: AtomicU64::new(1),
            streams: Arc::new(DashMap::new()),
            image_upstream_base: RwLock::new(None),
            image_upstream_headers: RwLock::new(HeaderMap::new()),
            server_image_upstreams: DashMap::new(),
            image_cache: Mutex::new(ByteBoundedImageCache::new(512, MAX_RAM_IMAGE_CACHE_BYTES)),
            image_cache_dir: RwLock::new(None),
            image_sem: Semaphore::new(8),
            image_in_flight: DashMap::new(),
            disk_write_counter: AtomicUsize::new(0),
            active_conns: Arc::new(AtomicUsize::new(0)),
            conn_sem: Arc::new(Semaphore::new(64)),
            total_upstream_bytes: Arc::new(AtomicU64::new(0)),
            total_served_bytes: Arc::new(AtomicU64::new(0)),
            rate_limit_retries: Arc::new(AtomicU64::new(0)),
            speed_buckets: Mutex::new([(0, 0); 4]),
            started_at: Instant::now(),
            shutdown_tx: Mutex::new(Some(shutdown_tx)),
        });

        let server_proxy = Arc::downgrade(&proxy);
        tokio::spawn(async move {
            info!(addr = %listen_addr, "vedro local stream proxy listening");
            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => {
                        debug!("vedro stream proxy shutting down");
                        break;
                    }
                    accepted = listener.accept() => {
                        let Ok((stream, _peer)) = accepted else { continue };
                        let Some(p) = server_proxy.upgrade() else {
                            break;
                        };
                        let Ok(permit) = Arc::clone(&p.conn_sem).try_acquire_owned() else {
                            drop(stream);
                            continue;
                        };
                        // Disable Nagle algorithm on loopback to eliminate 40ms delayed-ACK stalls!
                        let _ = stream.set_nodelay(true);
                        let io = TokioIo::new(stream);
                        tokio::spawn(async move {
                            let _permit = permit;
                            let svc = service_fn(move |req| {
                                let p = Arc::clone(&p);
                                async move { p.handle_request(req).await }
                            });
                            if let Err(err) = hyper::server::conn::http1::Builder::new()
                                .timer(TokioTimer::new())
                                .keep_alive(true)
                                .header_read_timeout(Duration::from_secs(10))
                                .serve_connection(io, svc)
                                .await
                            {
                                debug!(error = %err, "local proxy connection ended");
                            }
                        });
                    }
                }
            }
        });

        Ok(proxy)
    }

    pub fn shutdown(&self) {
        if let Some(tx) = self.shutdown_tx.lock().take() {
            let _ = tx.send(());
        }
    }

    pub fn listen_addr(&self) -> SocketAddr {
        self.listen_addr
    }

    pub fn set_image_cache_dir(&self, dir: PathBuf) {
        let _ = std::fs::create_dir_all(&dir);
        *self.image_cache_dir.write() = Some(dir.clone());
        // Clean up any stale `.tmp` files left from prior crashes in background without
        // ever panicking if called outside an entered Tokio runtime context!
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                if let Ok(mut rd) = tokio::fs::read_dir(&dir).await {
                    while let Ok(Some(entry)) = rd.next_entry().await {
                        let p = entry.path();
                        if p.extension().and_then(|e| e.to_str()) == Some("tmp") {
                            let _ = tokio::fs::remove_file(&p).await;
                        }
                    }
                }
            });
        } else {
            let _ = std::thread::Builder::new()
                .name("vedro-img-gc".to_string())
                .spawn(move || {
                    if let Ok(rd) = std::fs::read_dir(&dir) {
                        for entry in rd.flatten() {
                            let p = entry.path();
                            if p.extension().and_then(|e| e.to_str()) == Some("tmp") {
                                let _ = std::fs::remove_file(&p);
                            }
                        }
                    }
                });
        }
    }

    pub fn configure_transport(
        &self,
        proxy_url: Option<&str>,
        accept_invalid_certs: bool,
    ) -> std::io::Result<()> {
        let norm_proxy = proxy_url
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToString::to_string);
        if *self.transport_sig.read() == (norm_proxy.clone(), accept_invalid_certs) {
            return Ok(());
        }
        let client = build_proxy_http_client(norm_proxy.as_deref(), accept_invalid_certs)?;
        *self.http.write() = client;
        *self.transport_sig.write() = (norm_proxy, accept_invalid_certs);
        Ok(())
    }

    /// Configure upstream server base URL for artwork proxying (`/img/...`).
    /// Keeps auth headers for same-origin Emby/Jellyfin/EmbyGo image endpoints (many private
    /// servers & reverse proxies require `X-Emby-Token` on `/Items/*/Images/*`), while
    /// `is_allowed_image_rel_path`, raster MIME/magic-byte verification, and cross-origin
    /// redirect header stripping protect against API exfiltration and token leakage.
    pub fn set_image_upstream(&self, base_url: String, headers: HeaderMap) {
        let headers = prepare_image_headers(headers);
        let normalized = base_url.trim_end_matches('/').to_string();
        let changed = self.image_upstream_base.read().as_deref() != Some(normalized.as_str());
        *self.image_upstream_base.write() = Some(normalized);
        *self.image_upstream_headers.write() = headers;
        if changed {
            self.image_cache.lock().clear();
        }
    }

    pub fn register_server_image_upstream(
        &self,
        server_id: String,
        base_url: String,
        headers: HeaderMap,
    ) {
        let headers = prepare_image_headers(headers);
        let normalized = base_url.trim_end_matches('/').to_string();
        self.server_image_upstreams
            .insert(server_id, (normalized, headers));
    }

    pub fn unregister_server_image_upstream(&self, server_id: &str) {
        self.server_image_upstreams.remove(server_id);
    }

    /// Clear active streams, image upstreams, and in-memory image cache (called on logout).
    pub fn clear_all_streams_and_upstreams(&self) {
        let keys: Vec<(String, u64)> = self
            .streams
            .iter()
            .map(|e| (e.key().clone(), e.value().cache_key))
            .collect();
        self.streams.clear();
        for (_, cache_key) in keys {
            self.cache.evict_session(cache_key);
        }
        *self.image_upstream_base.write() = None;
        self.image_upstream_headers.write().clear();
        self.image_cache.lock().clear();
    }

    /// Register an upstream media stream and return `(stream_id, local_url)`.
    pub fn register_stream(
        self: &Arc<Self>,
        upstream_url: String,
        headers: HeaderMap,
        known_size: Option<u64>,
        content_type: Option<String>,
    ) -> (String, String) {
        // Bound registered streams so external_play_url or abandoned sessions never leak unboundedly.
        if self.streams.len() >= 16 {
            if let Some((oldest_id, oldest_key)) = self
                .streams
                .iter()
                .min_by_key(|e| e.value().cache_key)
                .map(|e| (e.key().clone(), e.value().cache_key))
            {
                self.streams.remove(&oldest_id);
                self.cache.evict_session(oldest_key);
            }
        }
        let id = uuid::Uuid::new_v4().simple().to_string();
        let cache_key = self.next_session_key.fetch_add(1, Ordering::Relaxed);
        let entry = Arc::new(RegisteredStream {
            cache_key,
            upstream_url: RwLock::new(upstream_url),
            headers: RwLock::new(headers),
            total_size: AtomicU64::new(known_size.unwrap_or(0)),
            content_type: RwLock::new(
                content_type.unwrap_or_else(|| "application/octet-stream".to_string()),
            ),
            upstream_sem: Arc::new(Semaphore::new(
                self.config.max_upstream_conns_per_session.max(1),
            )),
            in_flight: DashMap::new(),
            ticket_rotations: AtomicU64::new(0),
        });
        self.streams.insert(id.clone(), Arc::clone(&entry));

        // Pre-warm chunk 0 (MKV/MP4 header) and tail chunk (MKV Cues / MP4 moov) IN PARALLEL
        // when `known_size` is known!
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            let this = Arc::clone(self);
            handle.spawn(async move {
                let total = entry.total_size.load(Ordering::Acquire);
                if total > this.cache.chunk_size() {
                    let last_chunk = (total - 1) / this.cache.chunk_size();
                    if last_chunk > 0 {
                        let _ = tokio::join!(
                            this.fetch_chunk(&entry, 0),
                            this.fetch_chunk(&entry, last_chunk),
                        );
                        return;
                    }
                }
                let _ = this.fetch_chunk(&entry, 0).await;
                let discovered = entry.total_size.load(Ordering::Acquire);
                if discovered > this.cache.chunk_size() {
                    let last_chunk = (discovered - 1) / this.cache.chunk_size();
                    if last_chunk > 0 {
                        let _ = this.fetch_chunk(&entry, last_chunk).await;
                    }
                }
            });
        }

        let local_url = format!("http://{}/stream/{id}", self.listen_addr);
        (id, local_url)
    }

    pub fn update_upstream_url(
        &self,
        stream_id: &str,
        new_url: String,
        new_headers: Option<HeaderMap>,
    ) -> bool {
        if let Some(entry) = self.streams.get(stream_id) {
            *entry.upstream_url.write() = new_url;
            if let Some(hdrs) = new_headers {
                *entry.headers.write() = hdrs;
            }
            entry.ticket_rotations.fetch_add(1, Ordering::Relaxed);
            true
        } else {
            false
        }
    }

    pub fn unregister_stream(&self, stream_id: &str) {
        if let Some((_, entry)) = self.streams.remove(stream_id) {
            self.cache.evict_session(entry.cache_key);
        }
    }

    /// Read a bounded byte slice directly from the proxy's cache/upstream (used by `inspector.rs`).
    pub async fn read_range(
        self: &Arc<Self>,
        stream_id: &str,
        start: u64,
        len: u64,
    ) -> Option<Bytes> {
        if len == 0 {
            return Some(Bytes::new());
        }
        let entry = self.streams.get(stream_id)?.clone();
        let total = self.ensure_size(&entry).await?;
        if start >= total {
            return Some(Bytes::new());
        }
        let capped_len = len.min(4 * 1024 * 1024);
        let end = start
            .saturating_add(capped_len)
            .min(total)
            .saturating_sub(1);
        if start > end {
            return Some(Bytes::new());
        }
        self.read_exact_range_bounded(&entry, start, end, total)
            .await
            .ok()
    }

    fn record_upstream_bytes(&self, bytes: u64) {
        if bytes == 0 {
            return;
        }
        self.total_upstream_bytes
            .fetch_add(bytes, Ordering::Relaxed);
        let sec = self.started_at.elapsed().as_secs() + 1;
        let idx = (sec as usize) & 3;
        let mut buckets = self.speed_buckets.lock();
        if buckets[idx].0 == sec {
            buckets[idx].1 = buckets[idx].1.saturating_add(bytes);
        } else {
            buckets[idx] = (sec, bytes);
        }
    }

    /// Smooth, idempotent instantaneous upstream bytes/sec readout over a rolling 3s window
    /// (unaffected by idle gaps or concurrent NerdStats/HUD polling).
    pub fn current_speed_bps(&self) -> u64 {
        let now_sec = self.started_at.elapsed().as_secs() + 1;
        let buckets = self.speed_buckets.lock();
        let mut recent_bytes = 0u64;
        let mut active_secs = 0u64;
        for &(sec, bytes) in buckets.iter() {
            if sec > 0 && now_sec >= sec && now_sec.saturating_sub(sec) <= 2 {
                recent_bytes = recent_bytes.saturating_add(bytes);
                if bytes > 0 {
                    active_secs += 1;
                }
            }
        }
        if recent_bytes == 0 {
            return 0;
        }
        // Divide by rolling window span (1..=3s) so startup burst isn't diluted while steady flow is smooth
        let window_secs = active_secs.clamp(1, 3);
        recent_bytes / window_secs
    }

    pub fn stats(&self) -> StreamProxyStats {
        let up_bytes = self.total_upstream_bytes.load(Ordering::Relaxed);
        let current_bps = self.current_speed_bps();
        let rotations: u64 = self
            .streams
            .iter()
            .map(|e| e.ticket_rotations.load(Ordering::Relaxed))
            .sum();
        StreamProxyStats {
            listen_addr: self.listen_addr.to_string(),
            active_sessions: self.streams.len(),
            active_upstream_connections: self.active_conns.load(Ordering::Relaxed),
            total_upstream_bytes: up_bytes,
            total_served_bytes: self.total_served_bytes.load(Ordering::Relaxed),
            rate_limit_retries: self.rate_limit_retries.load(Ordering::Relaxed),
            ticket_rotations: rotations,
            throughput_mbps: (current_bps as f64 * 8.0) / 1_000_000.0,
            current_speed_bytes_per_sec: current_bps,
            cache: self.cache.stats(),
        }
    }

    pub fn image_cache_stats(&self) -> ImageCacheStats {
        let mem_entries = self.image_cache.lock().len();
        let dir_opt = self.image_cache_dir.read().clone();
        let mut disk_files = 0usize;
        let mut disk_bytes = 0u64;
        if let Some(ref dir) = dir_opt {
            if let Ok(rd) = std::fs::read_dir(dir) {
                for entry in rd.flatten() {
                    let path = entry.path();
                    if let Ok(meta) = entry.metadata() {
                        if meta.is_file() {
                            disk_bytes = disk_bytes.saturating_add(meta.len());
                            if path.extension().and_then(|e| e.to_str()) == Some("img") {
                                disk_files += 1;
                            }
                        }
                    }
                }
            }
        }
        ImageCacheStats {
            disk_files,
            disk_bytes,
            memory_entries: mem_entries,
            cache_dir: dir_opt.map(|p| p.to_string_lossy().into_owned()),
        }
    }

    pub fn clear_image_cache(&self) -> (usize, u64) {
        self.image_cache.lock().clear();
        let dir_opt = self.image_cache_dir.read().clone();
        let mut removed_images = 0usize;
        let mut freed_bytes = 0u64;
        if let Some(dir) = dir_opt {
            if let Ok(rd) = std::fs::read_dir(&dir) {
                for entry in rd.flatten() {
                    let path = entry.path();
                    if let Ok(meta) = entry.metadata() {
                        if meta.is_file() {
                            let len = meta.len();
                            if std::fs::remove_file(&path).is_ok() {
                                freed_bytes = freed_bytes.saturating_add(len);
                                if path.extension().and_then(|e| e.to_str()) == Some("img") {
                                    removed_images += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        (removed_images, freed_bytes)
    }

    fn is_valid_loopback_host(&self, req: &Request<Incoming>) -> bool {
        let host_val = req
            .headers()
            .get(header::HOST)
            .and_then(|v| v.to_str().ok())
            .or_else(|| req.uri().authority().map(|a| a.as_str()));
        let Some(host_val) = host_val else {
            return false;
        };
        let port = self.listen_addr.port();
        let expected_ip = format!("127.0.0.1:{port}");
        let expected_lh = format!("localhost:{port}");
        let expected_v6 = format!("[::1]:{port}");
        host_val.eq_ignore_ascii_case(&expected_ip)
            || host_val.eq_ignore_ascii_case(&expected_lh)
            || host_val.eq_ignore_ascii_case(&expected_v6)
            || host_val == "127.0.0.1"
            || host_val == "[::1]"
            || host_val.eq_ignore_ascii_case("localhost")
    }

    async fn handle_request(
        self: Arc<Self>,
        req: Request<Incoming>,
    ) -> std::result::Result<Response<ProxyBody>, hyper::Error> {
        if !matches!(*req.method(), Method::GET | Method::HEAD) {
            return Ok(simple_response(
                StatusCode::METHOD_NOT_ALLOWED,
                "method not allowed",
            ));
        }
        if !self.is_valid_loopback_host(&req) {
            return Ok(simple_response(StatusCode::FORBIDDEN, "invalid host"));
        }

        let path = req.uri().path();
        if let Some(srv_rest) = path.strip_prefix("/img-srv/") {
            if let Some((srv_id, img_rel)) = srv_rest.split_once('/') {
                return Ok(self
                    .handle_image_request(Some(srv_id), img_rel, req.uri().query())
                    .await);
            }
            return Ok(simple_response(StatusCode::NOT_FOUND, "invalid image path"));
        }
        if let Some(img_rel) = path.strip_prefix("/img/") {
            return Ok(self
                .handle_image_request(None, img_rel, req.uri().query())
                .await);
        }
        let Some(stream_id) = path.strip_prefix("/stream/") else {
            return Ok(simple_response(StatusCode::NOT_FOUND, "not found"));
        };
        let Some(entry) = self.streams.get(stream_id).map(|e| Arc::clone(&e)) else {
            return Ok(simple_response(StatusCode::NOT_FOUND, "unknown stream"));
        };

        let Some(total_size) = self.ensure_size(&entry).await else {
            return Ok(simple_response(
                StatusCode::BAD_GATEWAY,
                "failed to resolve upstream stream size",
            ));
        };

        let ctype = safe_header_value(&entry.content_type.read(), "application/octet-stream");

        if req.method() == Method::HEAD {
            return Ok(Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, ctype)
                .header(header::CONTENT_LENGTH, total_size)
                .header(header::ACCEPT_RANGES, "bytes")
                .body(full_body(Bytes::new()))
                .unwrap_or_else(|_| {
                    simple_response(StatusCode::INTERNAL_SERVER_ERROR, "header error")
                }));
        }

        let range_hdr = req
            .headers()
            .get(header::RANGE)
            .and_then(|v| v.to_str().ok());

        let (start, end, is_partial) = match range_hdr {
            Some(rh) => match parse_range_header(rh, total_size) {
                Some((s, e)) => (s, e, true),
                None => {
                    return Ok(Response::builder()
                        .status(StatusCode::RANGE_NOT_SATISFIABLE)
                        .header(header::CONTENT_RANGE, format!("bytes */{total_size}"))
                        .body(full_body(Bytes::new()))
                        .unwrap_or_else(|_| {
                            simple_response(StatusCode::RANGE_NOT_SATISFIABLE, "range error")
                        }));
                }
            },
            None => (0, total_size.saturating_sub(1), false),
        };

        // Zero-copy streaming response via StreamBody!
        // Never buffers full movie or even 4 MiB before first byte; delivers chunk 0 immediately!
        let cs = self.cache.chunk_size();
        let first_chunk = start / cs;
        let last_chunk = end.min(total_size.saturating_sub(1)) / cs;

        // Fetch first chunk synchronously so upstream errors still map to accurate HTTP status codes
        let first_data = match self.fetch_chunk(&entry, first_chunk).await {
            Ok(d) => d,
            Err(status) => return Ok(simple_response(status, "upstream range fetch failed")),
        };

        let first_chunk_start = first_chunk.saturating_mul(cs);
        let first_capped_len = (first_data.len() as u64).min(cs);
        let first_local_start = start
            .saturating_sub(first_chunk_start)
            .min(first_capped_len) as usize;
        let first_local_end = end
            .saturating_sub(first_chunk_start)
            .saturating_add(1)
            .min(first_capped_len) as usize;
        let first_slice = if first_local_start < first_local_end {
            first_data.slice(first_local_start..first_local_end)
        } else {
            Bytes::new()
        };
        if first_slice.is_empty() {
            return Ok(simple_response(
                StatusCode::BAD_GATEWAY,
                "upstream returned empty range slice",
            ));
        }

        if first_chunk == last_chunk {
            self.total_served_bytes
                .fetch_add(first_slice.len() as u64, Ordering::Relaxed);
            self.spawn_prefetch(Arc::clone(&entry), first_chunk + 1, total_size);
            let mut builder = Response::builder()
                .status(if is_partial {
                    StatusCode::PARTIAL_CONTENT
                } else {
                    StatusCode::OK
                })
                .header(header::CONTENT_TYPE, ctype)
                .header(header::CONTENT_LENGTH, first_slice.len())
                .header(header::ACCEPT_RANGES, "bytes");
            if is_partial {
                let actual_end = start.saturating_add(first_slice.len().saturating_sub(1) as u64);
                builder = builder.header(
                    header::CONTENT_RANGE,
                    format!("bytes {start}-{actual_end}/{total_size}"),
                );
            }
            return Ok(builder.body(full_body(first_slice)).unwrap_or_else(|_| {
                simple_response(StatusCode::INTERNAL_SERVER_ERROR, "resp error")
            }));
        }

        // Guard against byte-shift corruption when upstream truncates chunk `first_chunk`
        // (e.g. CDN caps 206 responses below `cs`): never silently skip missing bytes before `first_chunk + 1`!
        let first_is_short = (first_data.len() as u64) < cs;
        // Multi-chunk streaming body (works for both open-ended Range AND non-Range full GETs with O(1) RAM!)
        let content_len = end.saturating_sub(start).saturating_add(1);
        let (tx, rx) = mpsc::channel::<Result<Frame<Bytes>, std::io::Error>>(3);
        let this = Arc::clone(&self);
        let entry_clone = Arc::clone(&entry);
        tokio::spawn(async move {
            if !first_slice.is_empty() {
                this.total_served_bytes
                    .fetch_add(first_slice.len() as u64, Ordering::Relaxed);
                if tx.send(Ok(Frame::data(first_slice))).await.is_err() {
                    return;
                }
            }
            if first_is_short {
                // Abort stream cleanly so mpv re-requests from the exact short-read offset instead of
                // receiving byte-shifted data from chunk `first_chunk + 1`.
                let _ = tx
                    .send(Err(std::io::Error::new(
                        std::io::ErrorKind::UnexpectedEof,
                        "upstream returned short initial chunk",
                    )))
                    .await;
                return;
            }
            for chunk_idx in (first_chunk + 1)..=last_chunk {
                // Keep 1-2 chunks pipelined ahead while streaming!
                this.spawn_prefetch(Arc::clone(&entry_clone), chunk_idx + 1, total_size);
                match this.fetch_chunk(&entry_clone, chunk_idx).await {
                    Ok(chunk) => {
                        if chunk.is_empty() {
                            break;
                        }
                        let chunk_start = chunk_idx.saturating_mul(cs);
                        let capped_len = (chunk.len() as u64).min(cs);
                        let local_start =
                            start.saturating_sub(chunk_start).min(capped_len) as usize;
                        let local_end = end
                            .saturating_sub(chunk_start)
                            .saturating_add(1)
                            .min(capped_len) as usize;
                        if local_start >= local_end {
                            break;
                        }
                        let slice = chunk.slice(local_start..local_end);
                        this.total_served_bytes
                            .fetch_add(slice.len() as u64, Ordering::Relaxed);
                        if tx.send(Ok(Frame::data(slice))).await.is_err() {
                            return;
                        }
                        // If upstream returned a short chunk before the final chunk, abort stream cleanly
                        // so mpv sees EOF instead of silent byte-shift corruption!
                        if chunk_idx < last_chunk && (chunk.len() as u64) < cs {
                            let _ = tx
                                .send(Err(std::io::Error::new(
                                    std::io::ErrorKind::UnexpectedEof,
                                    "upstream returned short chunk",
                                )))
                                .await;
                            return;
                        }
                    }
                    Err(_) => {
                        let _ = tx
                            .send(Err(std::io::Error::other("upstream chunk fetch failed")))
                            .await;
                        return;
                    }
                }
            }
        });

        let stream = futures_util::stream::unfold(rx, |mut rx| async move {
            rx.recv().await.map(|item| (item, rx))
        });
        let body: ProxyBody = BodyExt::boxed(StreamBody::new(stream));

        let mut builder = Response::builder()
            .status(if is_partial {
                StatusCode::PARTIAL_CONTENT
            } else {
                StatusCode::OK
            })
            .header(header::CONTENT_TYPE, ctype)
            .header(header::CONTENT_LENGTH, content_len)
            .header(header::ACCEPT_RANGES, "bytes");
        if is_partial {
            builder = builder.header(
                header::CONTENT_RANGE,
                format!("bytes {start}-{end}/{total_size}"),
            );
        }
        Ok(builder
            .body(body)
            .unwrap_or_else(|_| simple_response(StatusCode::INTERNAL_SERVER_ERROR, "resp error")))
    }

    async fn handle_image_request(
        &self,
        server_id: Option<&str>,
        rel_path: &str,
        query: Option<&str>,
    ) -> Response<ProxyBody> {
        if !is_allowed_image_rel_path(rel_path) {
            return simple_response(StatusCode::FORBIDDEN, "disallowed image path");
        }
        let rel_with_q = match query {
            Some(q) if !q.is_empty() => format!("{rel_path}?{q}"),
            _ => rel_path.to_string(),
        };
        let (base, hdrs) = if let Some(sid) = server_id {
            let Some(entry) = self.server_image_upstreams.get(sid) else {
                return simple_response(StatusCode::NOT_FOUND, "unknown server image upstream");
            };
            entry.value().clone()
        } else {
            let Some(b) = self.image_upstream_base.read().clone() else {
                return simple_response(StatusCode::SERVICE_UNAVAILABLE, "no image upstream");
            };
            (b, self.image_upstream_headers.read().clone())
        };

        let url = format!("{base}/{rel_with_q}");
        let cache_key = url.clone();

        // 1. Sub-microsecond RAM LRU cache hit
        if let Some((ct, body)) = self.image_cache.lock().get(&cache_key) {
            return build_image_response(
                StatusCode::OK,
                &ct,
                body,
                "public, max-age=86400, immutable",
            );
        }

        // 2. Persistent local disk cache hit
        let disk_dir = self.image_cache_dir.read().clone();
        let disk_stem = disk_dir
            .as_ref()
            .map(|_| image_disk_cache_filename(&cache_key));
        if let (Some(ref dir), Some(ref stem)) = (&disk_dir, &disk_stem) {
            let bin_path = dir.join(format!("{stem}.img"));
            let ct_path = dir.join(format!("{stem}.ct"));
            if let Ok(bytes_vec) = tokio::fs::read(&bin_path).await {
                if !bytes_vec.is_empty() && bytes_vec.len() <= MAX_IMAGE_BYTES {
                    let ct = tokio::fs::read_to_string(&ct_path)
                        .await
                        .ok()
                        .map(|s| s.trim().to_string())
                        .filter(|s| {
                            s.starts_with("image/") && !s.contains('\n') && !s.contains('\r')
                        })
                        .unwrap_or_else(|| "image/jpeg".to_string());
                    let body = Bytes::from(bytes_vec);
                    self.image_cache
                        .lock()
                        .put(cache_key.clone(), ct.clone(), body.clone());
                    return build_image_response(
                        StatusCode::OK,
                        &ct,
                        body,
                        "public, max-age=86400, immutable",
                    );
                }
            }
        }

        // 3. Cancel-safe atomic singleflight deduplication via DashMap::entry + watch channel
        let guard = match self.image_in_flight.entry(cache_key.clone()) {
            Entry::Occupied(occ) => {
                let mut rx = occ.get().clone();
                drop(occ);
                let _ = rx.wait_for(|done| *done).await;
                if let Some((ct, body)) = self.image_cache.lock().get(&cache_key) {
                    return build_image_response(
                        StatusCode::OK,
                        &ct,
                        body,
                        "public, max-age=86400, immutable",
                    );
                }
                None
            }
            Entry::Vacant(vac) => {
                let (tx, rx) = watch::channel(false);
                vac.insert(rx);
                Some(SingleflightGuard {
                    map: &self.image_in_flight,
                    key: cache_key.clone(),
                    tx: Some(tx),
                })
            }
        };

        let (status, raw_ct, bytes) = self.fetch_image_upstream_bounded(&url, &hdrs).await;
        let resolved_ct = if status == StatusCode::OK {
            let ct_lower = raw_ct.to_ascii_lowercase();
            if is_safe_raster_image_mime(&ct_lower) {
                Some(raw_ct.clone())
            } else {
                sniff_raster_image_mime(&bytes).map(ToString::to_string)
            }
        } else {
            None
        };

        if let Some(ref ct) = resolved_ct {
            if !bytes.is_empty() && bytes.len() <= MAX_IMAGE_BYTES {
                self.image_cache
                    .lock()
                    .put(cache_key.clone(), ct.clone(), bytes.clone());
                if let (Some(dir), Some(stem)) = (disk_dir, disk_stem) {
                    let ct_clone = ct.clone();
                    let bytes_clone = bytes.clone();
                    let write_idx = self.disk_write_counter.fetch_add(1, Ordering::Relaxed);
                    tokio::spawn(async move {
                        let uniq = uuid::Uuid::new_v4().simple().to_string();
                        let bin_path = dir.join(format!("{stem}.img"));
                        let ct_path = dir.join(format!("{stem}.ct"));
                        let tmp_bin = dir.join(format!("{stem}.{uniq}.tmp"));
                        let tmp_ct = dir.join(format!("{stem}.{uniq}.ct.tmp"));
                        if tokio::fs::write(&tmp_bin, &bytes_clone).await.is_ok()
                            && tokio::fs::write(&tmp_ct, ct_clone.as_bytes()).await.is_ok()
                        {
                            let _ = tokio::fs::rename(&tmp_ct, &ct_path).await;
                            let _ = tokio::fs::rename(&tmp_bin, &bin_path).await;
                        } else {
                            let _ = tokio::fs::remove_file(&tmp_bin).await;
                            let _ = tokio::fs::remove_file(&tmp_ct).await;
                        }
                        if write_idx % 128 == 127 {
                            prune_image_disk_cache(
                                &dir,
                                MAX_DISK_IMAGE_FILES,
                                MAX_DISK_IMAGE_CACHE_BYTES,
                            )
                            .await;
                        }
                    });
                }
            }
        }

        drop(guard);

        // Security gate: NEVER return non-image or SVG payloads from `/img/`!
        if status == StatusCode::OK {
            let Some(ct) = resolved_ct else {
                warn!(path = %rel_path, "image proxy rejected non-raster upstream payload");
                return simple_response(
                    StatusCode::BAD_GATEWAY,
                    "upstream did not return a raster image",
                );
            };
            return build_image_response(StatusCode::OK, &ct, bytes, "public, max-age=86400");
        }
        build_image_response(status, &raw_ct, bytes, "no-store")
    }

    async fn fetch_image_upstream_bounded(
        &self,
        url: &str,
        hdrs: &HeaderMap,
    ) -> (StatusCode, String, Bytes) {
        let Ok(_permit) = self.image_sem.acquire().await else {
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                "text/plain; charset=utf-8".to_string(),
                Bytes::from_static(b"image proxy shutting down"),
            );
        };

        let mut last_status = StatusCode::BAD_GATEWAY;
        for attempt in 0..3u64 {
            let client = self.http.read().clone();
            match send_with_safe_redirects(&client, url, hdrs.clone()).await {
                Ok(resp) => {
                    let raw_status = resp.status();
                    if raw_status == reqwest::StatusCode::TOO_MANY_REQUESTS {
                        self.rate_limit_retries.fetch_add(1, Ordering::Relaxed);
                        let wait_ms = resp
                            .headers()
                            .get("Retry-After")
                            .and_then(|v| v.to_str().ok())
                            .and_then(|s| s.parse::<u64>().ok())
                            .map(|s| s.saturating_mul(1000).min(3000))
                            .unwrap_or(350 * (attempt + 1));
                        if attempt < 2 {
                            tokio::time::sleep(Duration::from_millis(wait_ms)).await;
                            continue;
                        }
                    }
                    if raw_status.is_server_error() && attempt < 2 {
                        tokio::time::sleep(Duration::from_millis(250 * (attempt + 1))).await;
                        continue;
                    }
                    let status = StatusCode::from_u16(raw_status.as_u16())
                        .unwrap_or(StatusCode::BAD_GATEWAY);
                    let ct = resp
                        .headers()
                        .get(reqwest::header::CONTENT_TYPE)
                        .and_then(|v| v.to_str().ok())
                        .unwrap_or("image/jpeg")
                        .to_string();
                    match read_response_capped(resp, MAX_IMAGE_BYTES, true, |_| {}).await {
                        Ok(bytes) => return (status, ct, bytes),
                        Err(_) if attempt < 2 => {
                            tokio::time::sleep(Duration::from_millis(200 * (attempt + 1))).await;
                            continue;
                        }
                        Err(_) => {
                            last_status = StatusCode::BAD_GATEWAY;
                        }
                    }
                }
                Err(_) => {
                    last_status = StatusCode::BAD_GATEWAY;
                    if attempt < 2 {
                        tokio::time::sleep(Duration::from_millis(220 * (attempt + 1))).await;
                        continue;
                    }
                }
            }
        }
        (
            last_status,
            "text/plain; charset=utf-8".to_string(),
            Bytes::from_static(b"image upstream unreachable"),
        )
    }

    async fn ensure_size(&self, entry: &Arc<RegisteredStream>) -> Option<u64> {
        let existing = entry.total_size.load(Ordering::Acquire);
        if existing > 0 {
            return Some(existing);
        }
        let _ = self.fetch_chunk(entry, 0).await.ok()?;
        let discovered = entry.total_size.load(Ordering::Acquire);
        if discovered > 0 {
            Some(discovered)
        } else {
            None
        }
    }

    async fn read_exact_range_bounded(
        &self,
        entry: &Arc<RegisteredStream>,
        start: u64,
        end: u64,
        total_size: u64,
    ) -> Result<Bytes, StatusCode> {
        let cs = self.cache.chunk_size();
        let first_chunk = start / cs;
        let last_chunk = end.min(total_size.saturating_sub(1)) / cs;

        if first_chunk == last_chunk {
            let chunk = self.fetch_chunk(entry, first_chunk).await?;
            let chunk_start = first_chunk.saturating_mul(cs);
            let local_start = start.saturating_sub(chunk_start).min(chunk.len() as u64) as usize;
            let local_end = end
                .saturating_sub(chunk_start)
                .saturating_add(1)
                .min(chunk.len() as u64) as usize;
            if local_start >= local_end {
                return Ok(Bytes::new());
            }
            return Ok(chunk.slice(local_start..local_end));
        }

        let expected_len =
            (end.saturating_sub(start).saturating_add(1)).min(4 * 1024 * 1024) as usize;
        let mut out = Vec::with_capacity(expected_len);
        for chunk_idx in first_chunk..=last_chunk {
            let chunk = self.fetch_chunk(entry, chunk_idx).await?;
            let chunk_start = chunk_idx.saturating_mul(cs);
            let local_start = start.saturating_sub(chunk_start).min(chunk.len() as u64) as usize;
            let local_end = end
                .saturating_sub(chunk_start)
                .saturating_add(1)
                .min(chunk.len() as u64) as usize;
            if local_start < local_end {
                out.extend_from_slice(&chunk[local_start..local_end]);
            }
            if chunk_idx < last_chunk && (chunk.len() as u64) < cs {
                break;
            }
        }
        Ok(Bytes::from(out))
    }

    fn spawn_prefetch(
        self: &Arc<Self>,
        entry: Arc<RegisteredStream>,
        start_chunk: u64,
        total_size: u64,
    ) {
        let max_chunk = total_size.saturating_sub(1) / self.cache.chunk_size();
        let count = self.config.prefetch_chunks;
        if count == 0 || start_chunk > max_chunk {
            return;
        }
        let this = Arc::clone(self);
        tokio::spawn(async move {
            let end_chunk = start_chunk.saturating_add(count - 1).min(max_chunk);
            for idx in start_chunk..=end_chunk {
                if this.cache.peek_contains(entry.cache_key, idx)
                    || entry.in_flight.contains_key(&idx)
                {
                    continue;
                }
                if entry.upstream_sem.available_permits() == 0 {
                    break;
                }
                let _ = this.fetch_chunk(&entry, idx).await;
            }
        });
    }

    async fn fetch_chunk(
        &self,
        entry: &Arc<RegisteredStream>,
        chunk_idx: u64,
    ) -> Result<Bytes, StatusCode> {
        if let Some(hit) = self.cache.get(entry.cache_key, chunk_idx) {
            return Ok(hit);
        }

        // Cancel-safe atomic singleflight deduplication via DashMap::entry + watch channel
        let guard = match entry.in_flight.entry(chunk_idx) {
            Entry::Occupied(occ) => {
                let mut rx = occ.get().clone();
                drop(occ);
                let _ = rx.wait_for(|done| *done).await;
                if let Some(hit) = self.cache.get(entry.cache_key, chunk_idx) {
                    return Ok(hit);
                }
                None
            }
            Entry::Vacant(vac) => {
                let (tx, rx) = watch::channel(false);
                vac.insert(rx);
                Some(SingleflightGuard {
                    map: &entry.in_flight,
                    key: chunk_idx,
                    tx: Some(tx),
                })
            }
        };

        let result = self.fetch_chunk_from_upstream(entry, chunk_idx).await;
        drop(guard);
        result
    }

    async fn fetch_chunk_from_upstream(
        &self,
        entry: &Arc<RegisteredStream>,
        chunk_idx: u64,
    ) -> Result<Bytes, StatusCode> {
        let _permit = entry
            .upstream_sem
            .acquire()
            .await
            .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;

        let cs = self.cache.chunk_size();
        let start = chunk_idx.saturating_mul(cs);
        let known_total = entry.total_size.load(Ordering::Acquire);
        if known_total > 0 && start >= known_total {
            return Err(StatusCode::RANGE_NOT_SATISFIABLE);
        }
        let end = if known_total > 0 {
            start.saturating_add(cs - 1).min(known_total - 1)
        } else {
            start.saturating_add(cs - 1)
        };

        let range_val = format!("bytes={start}-{end}");
        // Cap strictly to `cs` so a chunk-0 HTTP 200 fallback never caches > `cs` bytes
        // and corrupts subsequent chunk boundaries or overflows Content-Length!
        let max_chunk_bytes = cs as usize;

        for attempt in 0..3 {
            let url = entry.upstream_url.read().clone();
            let mut hdrs = entry.headers.read().clone();
            if let Ok(rv) = reqwest::header::HeaderValue::from_str(&range_val) {
                hdrs.insert(reqwest::header::RANGE, rv);
            }

            let _conn_guard = ActiveConnGuard::new(&self.active_conns);
            let http_client = self.http.read().clone();
            let resp_res = send_with_safe_redirects(&http_client, &url, hdrs).await;

            match resp_res {
                Ok(resp) => {
                    let status = resp.status();
                    if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
                        self.rate_limit_retries.fetch_add(1, Ordering::Relaxed);
                        let wait_secs = resp
                            .headers()
                            .get("Retry-After")
                            .and_then(|v| v.to_str().ok())
                            .and_then(|s| s.parse::<u64>().ok())
                            .unwrap_or(1)
                            .min(5);
                        warn!(
                            chunk_idx,
                            wait_secs, "upstream returned 429; backing off cleanly"
                        );
                        drop(_conn_guard);
                        tokio::time::sleep(Duration::from_secs(wait_secs)).await;
                        continue;
                    }

                    if status.is_server_error() && attempt < 2 {
                        warn!(
                            status = status.as_u16(),
                            attempt, chunk_idx, "upstream transient 5xx; retrying"
                        );
                        drop(_conn_guard);
                        tokio::time::sleep(Duration::from_millis(300 * (attempt + 1) as u64)).await;
                        continue;
                    }

                    if !status.is_success() {
                        warn!(
                            status = status.as_u16(),
                            chunk_idx, "upstream chunk fetch error"
                        );
                        return Err(StatusCode::from_u16(status.as_u16())
                            .unwrap_or(StatusCode::BAD_GATEWAY));
                    }

                    // Critical integrity guard: if we requested chunk_idx > 0 (Range: bytes=start-end)
                    // and upstream ignored Range returning 200 OK (starting at byte 0), NEVER cache
                    // offset-0 bytes under chunk_idx (that causes silent demuxer byte-shift corruption!).
                    if chunk_idx > 0 && status == reqwest::StatusCode::OK {
                        warn!(
                            chunk_idx,
                            "upstream ignored Range header and returned 200 OK for non-zero chunk"
                        );
                        return Err(StatusCode::BAD_GATEWAY);
                    }

                    if let Some(ct) = resp
                        .headers()
                        .get(reqwest::header::CONTENT_TYPE)
                        .and_then(|v| v.to_str().ok())
                    {
                        *entry.content_type.write() = ct.to_string();
                    }
                    if let Some(cr) = resp
                        .headers()
                        .get(reqwest::header::CONTENT_RANGE)
                        .and_then(|v| v.to_str().ok())
                    {
                        if chunk_idx > 0 {
                            if let Some(range_start) = cr
                                .trim()
                                .strip_prefix("bytes ")
                                .and_then(|r| r.split('-').next())
                                .and_then(|s| s.trim().parse::<u64>().ok())
                            {
                                if range_start != start {
                                    warn!(
                                        chunk_idx,
                                        expected = start,
                                        actual = range_start,
                                        "upstream Content-Range offset mismatch"
                                    );
                                    return Err(StatusCode::BAD_GATEWAY);
                                }
                            }
                        }
                        if let Some(total) = parse_content_range_total(cr) {
                            entry.total_size.store(total, Ordering::Release);
                        }
                    } else if status == reqwest::StatusCode::OK {
                        if let Some(cl) = resp.content_length() {
                            entry.total_size.store(cl, Ordering::Release);
                        }
                    }

                    // Bounded read protects against servers ignoring Range and returning a 4GB 200 OK!
                    // Accounts bytes per frame into the rolling speed ring buffer (zero sawtooth).
                    let data = read_response_capped(resp, max_chunk_bytes, false, |n| {
                        self.record_upstream_bytes(n);
                    })
                    .await?;
                    self.cache.put(entry.cache_key, chunk_idx, data.clone());
                    return Ok(data);
                }
                Err(e) => {
                    let msg = e.to_string();
                    let safe_msg = msg.split('?').next().unwrap_or(&msg);
                    warn!(error = %safe_msg, attempt, chunk_idx, "upstream network error");
                    drop(_conn_guard);
                    if attempt == 2 {
                        return Err(StatusCode::BAD_GATEWAY);
                    }
                    tokio::time::sleep(Duration::from_millis(250 * (attempt + 1) as u64)).await;
                }
            }
        }
        Err(StatusCode::BAD_GATEWAY)
    }
}

impl Drop for StreamProxy {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn build_image_response(
    status: StatusCode,
    ct: &str,
    body: Bytes,
    cache_control: &'static str,
) -> Response<ProxyBody> {
    Response::builder()
        .status(status)
        .header(
            header::CONTENT_TYPE,
            safe_header_value(ct, "application/octet-stream"),
        )
        .header(header::CONTENT_LENGTH, body.len())
        .header(header::CACHE_CONTROL, cache_control)
        .header("X-Content-Type-Options", "nosniff")
        .header("Content-Security-Policy", "default-src 'none'; sandbox")
        .body(full_body(body))
        .unwrap_or_else(|_| simple_response(StatusCode::INTERNAL_SERVER_ERROR, "image resp error"))
}

pub fn parse_range_header(header_val: &str, total_size: u64) -> Option<(u64, u64)> {
    if total_size == 0 {
        return None;
    }
    let spec = header_val.trim().strip_prefix("bytes=")?;
    let first = spec.split(',').next()?.trim();
    let (start_s, end_s) = first.split_once('-')?;
    if start_s.is_empty() {
        let suffix: u64 = end_s.parse().ok()?;
        if suffix == 0 {
            return None;
        }
        let start = total_size.saturating_sub(suffix);
        return Some((start, total_size - 1));
    }
    let start: u64 = start_s.parse().ok()?;
    if start >= total_size {
        return None;
    }
    let end = if end_s.is_empty() {
        total_size - 1
    } else {
        end_s.parse::<u64>().ok()?.min(total_size - 1)
    };
    if start > end {
        return None;
    }
    Some((start, end))
}

fn parse_content_range_total(header_val: &str) -> Option<u64> {
    let (_, total_str) = header_val.rsplit_once('/')?;
    total_str.trim().parse::<u64>().ok()
}

async fn prune_image_disk_cache(dir: &std::path::Path, max_images: usize, max_bytes: u64) {
    let Ok(mut rd) = tokio::fs::read_dir(dir).await else {
        return;
    };
    let mut entries: Vec<(std::time::SystemTime, u64, PathBuf)> = Vec::new();
    let mut total_bytes: u64 = 0;
    while let Ok(Some(entry)) = rd.next_entry().await {
        let p = entry.path();
        if p.extension().and_then(|e| e.to_str()) != Some("img") {
            continue;
        }
        let meta = entry.metadata().await.ok();
        let len = meta.as_ref().map(|m| m.len()).unwrap_or(0);
        let mtime = meta
            .and_then(|m| m.modified().ok())
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        total_bytes = total_bytes.saturating_add(len);
        entries.push((mtime, len, p));
    }
    if entries.len() <= max_images && total_bytes <= max_bytes {
        return;
    }
    entries.sort_by_key(|(m, _, _)| *m);
    let target_count = max_images * 3 / 4;
    let target_bytes = max_bytes * 3 / 4;
    let mut remaining_count = entries.len();
    let mut remaining_bytes = total_bytes;
    for (_, len, img_path) in entries {
        if remaining_count <= target_count && remaining_bytes <= target_bytes {
            break;
        }
        let ct_path = img_path.with_extension("ct");
        let _ = tokio::fs::remove_file(&img_path).await;
        let _ = tokio::fs::remove_file(&ct_path).await;
        remaining_count = remaining_count.saturating_sub(1);
        remaining_bytes = remaining_bytes.saturating_sub(len);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_rfc7233_byte_ranges() {
        assert_eq!(parse_range_header("bytes=0-1023", 4096), Some((0, 1023)));
        assert_eq!(parse_range_header("bytes=100-", 4096), Some((100, 4095)));
        assert_eq!(parse_range_header("bytes=-512", 4096), Some((3584, 4095)));
        assert_eq!(parse_range_header("bytes=5000-", 4096), None);
        assert_eq!(
            parse_content_range_total("bytes 0-1048575/123456789"),
            Some(123_456_789)
        );
    }

    #[test]
    fn image_path_allowlist_blocks_traversal_and_non_image_routes() {
        assert!(is_allowed_image_rel_path("Items/12345/Images/Primary"));
        assert!(is_allowed_image_rel_path("Users/u1/Images/Primary"));
        assert!(!is_allowed_image_rel_path("Users"));
        assert!(!is_allowed_image_rel_path("Sessions"));
        assert!(!is_allowed_image_rel_path("Items/../Users/Images/Primary"));
        assert!(!is_allowed_image_rel_path("Items/%2e%2e/Images/Primary"));
        assert!(!is_allowed_image_rel_path("emby-compat/status"));
    }

    #[tokio::test]
    async fn image_cache_stats_and_clear_work() {
        let dir =
            std::env::temp_dir().join(format!("vedro_img_cache_test_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("aaa.img"), vec![1u8; 4096]).unwrap();
        std::fs::write(dir.join("aaa.ct"), b"image/jpeg").unwrap();
        std::fs::write(dir.join("bbb.img"), vec![2u8; 2048]).unwrap();
        std::fs::write(dir.join("bbb.ct"), b"image/webp").unwrap();

        let proxy = StreamProxy::start(StreamProxyConfig::default())
            .await
            .unwrap();
        proxy.set_image_cache_dir(dir.clone());

        let stats = proxy.image_cache_stats();
        assert_eq!(stats.disk_files, 2);
        assert!(stats.disk_bytes >= 6144);
        assert_eq!(stats.memory_entries, 0);

        let (removed, freed) = proxy.clear_image_cache();
        assert_eq!(removed, 2);
        assert!(freed >= 6144);

        let after = proxy.image_cache_stats();
        assert_eq!(after.disk_files, 0);
        assert_eq!(after.disk_bytes, 0);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
