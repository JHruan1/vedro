use std::net::SocketAddr;
use std::num::NonZeroUsize;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use bytes::Bytes;
use dashmap::DashMap;
use http::{header, Method, Request, Response, StatusCode};
use http_body_util::Full;
use hyper::body::Incoming;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use lru::LruCache;
use parking_lot::{Mutex, RwLock};
use reqwest::header::HeaderMap;
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use tokio::sync::{Notify, Semaphore};
use tracing::{debug, info, warn};

use crate::cache::{CacheStats, ChunkCache, DEFAULT_CHUNK_SIZE};

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
            cache_bytes: 64 * 1024 * 1024,
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
    id: String,
    upstream_url: RwLock<String>,
    headers: RwLock<HeaderMap>,
    total_size: AtomicU64,
    content_type: RwLock<String>,
    /// Strict per-session connection semaphore to respect embygo's connection cap.
    upstream_sem: Arc<Semaphore>,
    /// Deduplicates concurrent fetches for the same chunk index.
    in_flight: DashMap<u64, Arc<Notify>>,
    ticket_rotations: AtomicU64,
}

/// High-performance local loopback HTTP Range proxy & prefetch buffer.
///
/// Sits between `libmpv` / native players and `embygo` / `Emby` / `Jellyfin`:
/// - Strictly bounds upstream connections (`<= 2` per play session) to stay under embygo's cap.
/// - Caches head + tail chunks + sliding read-ahead window for zero-stutter 4K Remux playback.
/// - Allows transparent `StreamTicket` URL hot-swapping without restarting the media player.
/// - Handles HTTP 429 `Retry-After` backoff cleanly.
pub struct StreamProxy {
    listen_addr: SocketAddr,
    http: RwLock<reqwest::Client>,
    transport_sig: RwLock<(Option<String>, bool)>,
    config: StreamProxyConfig,
    cache: ChunkCache,
    streams: Arc<DashMap<String, Arc<RegisteredStream>>>,
    image_upstream_base: RwLock<Option<String>>,
    image_upstream_headers: RwLock<HeaderMap>,
    server_image_upstreams: DashMap<String, (String, HeaderMap)>,
    image_cache: Mutex<LruCache<String, (String, Bytes)>>,
    image_cache_dir: RwLock<Option<PathBuf>>,
    image_sem: Semaphore,
    image_in_flight: DashMap<String, Arc<Notify>>,
    disk_write_counter: AtomicUsize,
    active_conns: Arc<AtomicUsize>,
    total_upstream_bytes: Arc<AtomicU64>,
    total_served_bytes: Arc<AtomicU64>,
    rate_limit_retries: Arc<AtomicU64>,
    speed_sample: Mutex<(Instant, u64, u64)>,
    started_at: Instant,
    shutdown_tx: Option<tokio::sync::oneshot::Sender<()>>,
}

fn build_proxy_http_client(
    proxy_url: Option<&str>,
    accept_invalid_certs: bool,
) -> std::io::Result<reqwest::Client> {
    let mut builder = reqwest::Client::builder()
        .pool_max_idle_per_host(12)
        .connect_timeout(Duration::from_secs(12))
        .timeout(Duration::from_secs(30))
        .tcp_nodelay(true)
        .danger_accept_invalid_certs(accept_invalid_certs);
    if let Some(p) = proxy_url.map(str::trim).filter(|s| !s.is_empty()) {
        let proxy = reqwest::Proxy::all(p).map_err(std::io::Error::other)?;
        builder = builder.proxy(proxy);
    }
    builder.build().map_err(std::io::Error::other)
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
            streams: Arc::new(DashMap::new()),
            image_upstream_base: RwLock::new(None),
            image_upstream_headers: RwLock::new(HeaderMap::new()),
            server_image_upstreams: DashMap::new(),
            image_cache: Mutex::new(LruCache::new(NonZeroUsize::new(512).unwrap())),
            image_cache_dir: RwLock::new(None),
            // Bound concurrent upstream image fetches to 8 so cold Home mount (70+ posters)
            // never triggers a 70-connection TLS/SOCKS5 handshake stampede or HTTP 429!
            image_sem: Semaphore::new(8),
            image_in_flight: DashMap::new(),
            disk_write_counter: AtomicUsize::new(0),
            active_conns: Arc::new(AtomicUsize::new(0)),
            total_upstream_bytes: Arc::new(AtomicU64::new(0)),
            total_served_bytes: Arc::new(AtomicU64::new(0)),
            rate_limit_retries: Arc::new(AtomicU64::new(0)),
            speed_sample: Mutex::new((Instant::now(), 0, 0)),
            started_at: Instant::now(),
            shutdown_tx: Some(shutdown_tx),
        });

        let server_proxy = Arc::clone(&proxy);
        tokio::spawn(async move {
            info!(addr = %listen_addr, "vedro local stream proxy listening");
            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => {
                        debug!("prism stream proxy shutting down");
                        break;
                    }
                    accepted = listener.accept() => {
                        let Ok((stream, _peer)) = accepted else { continue };
                        let io = TokioIo::new(stream);
                        let p = Arc::clone(&server_proxy);
                        tokio::spawn(async move {
                            let svc = service_fn(move |req| {
                                let p = Arc::clone(&p);
                                async move { p.handle_request(req).await }
                            });
                            if let Err(err) = hyper::server::conn::http1::Builder::new()
                                .keep_alive(true)
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

    pub fn listen_addr(&self) -> SocketAddr {
        self.listen_addr
    }

    pub fn set_image_cache_dir(&self, dir: PathBuf) {
        let _ = std::fs::create_dir_all(&dir);
        *self.image_cache_dir.write() = Some(dir);
    }

    /// Reconfigure upstream HTTP proxy / TLS verification for the local stream proxy.
    /// Idempotent when `(proxy_url, accept_invalid_certs)` has not changed so warm HTTP/2
    /// connection pools and RAM artwork caches are never needlessly torn down mid-render!
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

    /// Configure upstream server base URL + auth headers for local RAM/disk-cached artwork proxying (`/img/...`).
    pub fn set_image_upstream(&self, base_url: String, headers: HeaderMap) {
        let normalized = base_url.trim_end_matches('/').to_string();
        let changed = self.image_upstream_base.read().as_deref() != Some(normalized.as_str());
        *self.image_upstream_base.write() = Some(normalized);
        *self.image_upstream_headers.write() = headers;
        if changed {
            self.image_cache.lock().clear();
        }
    }

    /// Register a server-specific artwork upstream for multi-server aggregated search (`/img-srv/{server_id}/...`).
    pub fn register_server_image_upstream(
        &self,
        server_id: String,
        base_url: String,
        headers: HeaderMap,
    ) {
        let normalized = base_url.trim_end_matches('/').to_string();
        self.server_image_upstreams
            .insert(server_id, (normalized, headers));
    }

    /// Register an upstream media stream and return the local loopback URL for the player.
    pub fn register_stream(
        self: &Arc<Self>,
        upstream_url: String,
        headers: HeaderMap,
        known_size: Option<u64>,
        content_type: Option<String>,
    ) -> (String, String) {
        let id = uuid::Uuid::new_v4().simple().to_string();
        let entry = Arc::new(RegisteredStream {
            id: id.clone(),
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

        // Pre-warm chunk 0 (MKV/MP4 header) and tail chunk (MKV Cues / MP4 moov) in background!
        let this = Arc::clone(self);
        tokio::spawn(async move {
            let _ = this.fetch_chunk(&entry, 0).await;
            let total = entry.total_size.load(Ordering::Acquire);
            if total > this.cache.chunk_size() {
                let last_chunk = (total - 1) / this.cache.chunk_size();
                if last_chunk > 0 {
                    let _ = this.fetch_chunk(&entry, last_chunk).await;
                }
            }
        });

        let local_url = format!("http://{}/stream/{id}", self.listen_addr);
        (id, local_url)
    }

    /// Hot-swap the upstream URL (e.g. when rotating an expiring `embygo` `StreamTicket`)
    /// without interrupting active playback.
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

    /// Remove a stream session and evict its chunks from RAM.
    pub fn unregister_stream(&self, stream_id: &str) {
        self.streams.remove(stream_id);
        self.cache.evict_session(stream_id);
    }

    /// Read a byte slice directly from the proxy's cache/upstream (used by `inspector.rs`
    /// to probe Dolby Vision / Atmos headers without opening an extra connection!).
    pub async fn read_range(
        self: &Arc<Self>,
        stream_id: &str,
        start: u64,
        len: u64,
    ) -> Option<Bytes> {
        let entry = self.streams.get(stream_id)?.clone();
        let total = self.ensure_size(&entry).await?;
        if start >= total {
            return Some(Bytes::new());
        }
        let end = (start + len).min(total) - 1;
        self.read_exact_range(&entry, start, end, total).await.ok()
    }

    pub fn stats(&self) -> StreamProxyStats {
        let elapsed = self.started_at.elapsed().as_secs_f64().max(0.001);
        let up_bytes = self.total_upstream_bytes.load(Ordering::Relaxed);
        let current_bps = {
            let mut sample = self.speed_sample.lock();
            let dt = sample.0.elapsed().as_secs_f64();
            if dt >= 0.35 {
                let delta = up_bytes.saturating_sub(sample.1);
                let bps = (delta as f64 / dt).round() as u64;
                *sample = (Instant::now(), up_bytes, bps);
                bps
            } else {
                sample.2
            }
        };
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
            throughput_mbps: (up_bytes as f64 * 8.0) / (elapsed * 1_000_000.0),
            current_speed_bytes_per_sec: current_bps,
            cache: self.cache.stats(),
        }
    }

    /// Inspect local on-disk & RAM image cache occupancy.
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

    /// Purge both RAM LRU and persistent disk image cache files, returning `(removed_images, freed_bytes)`.
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

    async fn handle_request(
        self: Arc<Self>,
        req: Request<Incoming>,
    ) -> std::result::Result<Response<Full<Bytes>>, hyper::Error> {
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

        let ctype = entry.content_type.read().clone();

        if req.method() == Method::HEAD {
            return Ok(Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, ctype)
                .header(header::CONTENT_LENGTH, total_size)
                .header(header::ACCEPT_RANGES, "bytes")
                .body(Full::new(Bytes::new()))
                .unwrap());
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
                        .body(Full::new(Bytes::new()))
                        .unwrap());
                }
            },
            None => (0, total_size.saturating_sub(1), false),
        };

        // Cap a single HTTP response payload at 4 MiB for responsive streaming & low RAM peak;
        // HTTP/1.1 Range clients (libmpv/FFmpeg/AVPlayer) naturally issue sequential Range requests.
        let capped_end = if is_partial {
            end.min(start + 4 * 1024 * 1024 - 1).min(total_size - 1)
        } else {
            end
        };

        match self
            .read_exact_range(&entry, start, capped_end, total_size)
            .await
        {
            Ok(data) => {
                self.total_served_bytes
                    .fetch_add(data.len() as u64, Ordering::Relaxed);

                // Trigger background sequential read-ahead prefetch
                let next_chunk = (capped_end + 1) / self.cache.chunk_size();
                self.spawn_prefetch(Arc::clone(&entry), next_chunk, total_size);

                let mut builder = Response::builder()
                    .status(if is_partial {
                        StatusCode::PARTIAL_CONTENT
                    } else {
                        StatusCode::OK
                    })
                    .header(header::CONTENT_TYPE, ctype)
                    .header(header::CONTENT_LENGTH, data.len())
                    .header(header::ACCEPT_RANGES, "bytes");

                if is_partial {
                    let actual_end = start + data.len().saturating_sub(1) as u64;
                    builder = builder.header(
                        header::CONTENT_RANGE,
                        format!("bytes {start}-{actual_end}/{total_size}"),
                    );
                }
                Ok(builder.body(Full::new(data)).unwrap())
            }
            Err(status) => Ok(simple_response(status, "upstream range fetch failed")),
        }
    }

    async fn handle_image_request(
        &self,
        server_id: Option<&str>,
        rel_path: &str,
        query: Option<&str>,
    ) -> Response<Full<Bytes>> {
        let rel_with_q = match query {
            Some(q) if !q.is_empty() => format!("{rel_path}?{q}"),
            _ => rel_path.to_string(),
        };
        let (base, hdrs) = if let Some(sid) = server_id {
            let Some(entry) = self.server_image_upstreams.get(sid) else {
                return Response::builder()
                    .status(StatusCode::NOT_FOUND)
                    .header(header::CACHE_CONTROL, "no-store")
                    .body(Full::new(Bytes::from_static(
                        b"unknown server image upstream",
                    )))
                    .unwrap();
            };
            entry.value().clone()
        } else {
            let Some(b) = self.image_upstream_base.read().clone() else {
                return Response::builder()
                    .status(StatusCode::SERVICE_UNAVAILABLE)
                    .header(header::CACHE_CONTROL, "no-store")
                    .body(Full::new(Bytes::from_static(b"no image upstream")))
                    .unwrap();
            };
            (b, self.image_upstream_headers.read().clone())
        };

        let url = format!("{base}/{rel_with_q}");
        let cache_key = url.clone();

        // 1. Sub-microsecond RAM LRU cache hit
        if let Some((ct, body)) = self.image_cache.lock().get(&cache_key).cloned() {
            return Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, ct.as_str())
                .header(header::CONTENT_LENGTH, body.len())
                .header(header::CACHE_CONTROL, "public, max-age=86400, immutable")
                .body(Full::new(body))
                .unwrap();
        }

        // 2. Persistent local disk cache hit (<2ms cold-start posters & hero banners with 0 network I/O!)
        let disk_dir = self.image_cache_dir.read().clone();
        let disk_stem = disk_dir
            .as_ref()
            .map(|_| image_disk_cache_filename(&cache_key));
        if let (Some(ref dir), Some(ref stem)) = (&disk_dir, &disk_stem) {
            let bin_path = dir.join(format!("{stem}.img"));
            let ct_path = dir.join(format!("{stem}.ct"));
            if let Ok(bytes_vec) = tokio::fs::read(&bin_path).await {
                if !bytes_vec.is_empty() {
                    let ct = tokio::fs::read_to_string(&ct_path)
                        .await
                        .ok()
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .unwrap_or_else(|| "image/jpeg".to_string());
                    let body = Bytes::from(bytes_vec);
                    self.image_cache
                        .lock()
                        .put(cache_key.clone(), (ct.clone(), body.clone()));
                    return Response::builder()
                        .status(StatusCode::OK)
                        .header(header::CONTENT_TYPE, ct.as_str())
                        .header(header::CONTENT_LENGTH, body.len())
                        .header(header::CACHE_CONTROL, "public, max-age=86400, immutable")
                        .body(Full::new(body))
                        .unwrap();
                }
            }
        }

        // 3. Singleflight deduplication: coalesce identical concurrent artwork fetches
        if let Some(notify) = self.image_in_flight.get(&cache_key).map(|n| Arc::clone(&n)) {
            notify.notified().await;
            if let Some((ct, body)) = self.image_cache.lock().get(&cache_key).cloned() {
                return Response::builder()
                    .status(StatusCode::OK)
                    .header(header::CONTENT_TYPE, ct.as_str())
                    .header(header::CONTENT_LENGTH, body.len())
                    .header(header::CACHE_CONTROL, "public, max-age=86400, immutable")
                    .body(Full::new(body))
                    .unwrap();
            }
        }

        let notify = Arc::new(Notify::new());
        self.image_in_flight
            .insert(cache_key.clone(), Arc::clone(&notify));

        let fetched = self.fetch_image_upstream_bounded(&url, &hdrs).await;

        if let (StatusCode::OK, ref ct, ref bytes) = fetched {
            if !bytes.is_empty() && bytes.len() <= 4 * 1024 * 1024 && ct.starts_with("image/") {
                self.image_cache
                    .lock()
                    .put(cache_key.clone(), (ct.clone(), bytes.clone()));
                if let (Some(dir), Some(stem)) = (disk_dir, disk_stem) {
                    let ct_clone = ct.clone();
                    let bytes_clone = bytes.clone();
                    let write_idx = self.disk_write_counter.fetch_add(1, Ordering::Relaxed);
                    tokio::spawn(async move {
                        let bin_path = dir.join(format!("{stem}.img"));
                        let ct_path = dir.join(format!("{stem}.ct"));
                        let tmp_path = dir.join(format!("{stem}.tmp"));
                        if tokio::fs::write(&tmp_path, &bytes_clone).await.is_ok() {
                            let _ = tokio::fs::write(&ct_path, ct_clone.as_bytes()).await;
                            let _ = tokio::fs::rename(&tmp_path, &bin_path).await;
                        }
                        if write_idx % 128 == 127 {
                            prune_image_disk_cache(&dir, 2400).await;
                        }
                    });
                }
            }
        }

        self.image_in_flight.remove(&cache_key);
        notify.notify_waiters();

        let (status, ct, bytes) = fetched;
        let cache_hdr = if status == StatusCode::OK {
            "public, max-age=86400"
        } else {
            "no-store"
        };
        Response::builder()
            .status(status)
            .header(header::CONTENT_TYPE, ct)
            .header(header::CONTENT_LENGTH, bytes.len())
            .header(header::CACHE_CONTROL, cache_hdr)
            .body(Full::new(bytes))
            .unwrap()
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
            match client.get(url).headers(hdrs.clone()).send().await {
                Ok(resp) => {
                    let raw_status = resp.status();
                    if raw_status == reqwest::StatusCode::TOO_MANY_REQUESTS {
                        self.rate_limit_retries.fetch_add(1, Ordering::Relaxed);
                        let wait_ms = resp
                            .headers()
                            .get("Retry-After")
                            .and_then(|v| v.to_str().ok())
                            .and_then(|s| s.parse::<u64>().ok())
                            .map(|s| (s * 1000).min(3000))
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
                    match resp.bytes().await {
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
        // Fetch chunk 0 (0..chunk_size-1) which populates total_size from Content-Range!
        let _ = self.fetch_chunk(entry, 0).await.ok()?;
        let discovered = entry.total_size.load(Ordering::Acquire);
        if discovered > 0 {
            Some(discovered)
        } else {
            None
        }
    }

    async fn read_exact_range(
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
            let local_start = (start - first_chunk * cs) as usize;
            let local_end = ((end - first_chunk * cs) as usize + 1).min(chunk.len());
            if local_start >= chunk.len() {
                return Ok(Bytes::new());
            }
            return Ok(chunk.slice(local_start..local_end));
        }

        let expected_len = (end - start + 1) as usize;
        let mut out = Vec::with_capacity(expected_len);
        for chunk_idx in first_chunk..=last_chunk {
            let chunk = self.fetch_chunk(entry, chunk_idx).await?;
            let chunk_start = chunk_idx * cs;
            let local_start = start.saturating_sub(chunk_start) as usize;
            let local_end = ((end.saturating_sub(chunk_start)) as usize + 1).min(chunk.len());
            if local_start < local_end {
                out.extend_from_slice(&chunk[local_start..local_end]);
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
            for idx in start_chunk..=(start_chunk + count - 1).min(max_chunk) {
                if this.cache.peek_contains(&entry.id, idx) || entry.in_flight.contains_key(&idx) {
                    continue;
                }
                // Only prefetch if semaphore has spare capacity so live seeks stay instant
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
        if let Some(hit) = self.cache.get(&entry.id, chunk_idx) {
            return Ok(hit);
        }

        // Singleflight deduplication: if another task is already fetching this chunk, await it.
        if let Some(notify) = entry.in_flight.get(&chunk_idx).map(|n| Arc::clone(&n)) {
            notify.notified().await;
            if let Some(hit) = self.cache.get(&entry.id, chunk_idx) {
                return Ok(hit);
            }
        }

        let notify = Arc::new(Notify::new());
        entry.in_flight.insert(chunk_idx, Arc::clone(&notify));
        let result = self.fetch_chunk_from_upstream(entry, chunk_idx).await;
        entry.in_flight.remove(&chunk_idx);
        notify.notify_waiters();
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
        let start = chunk_idx * cs;
        let known_total = entry.total_size.load(Ordering::Acquire);
        let end = if known_total > 0 {
            (start + cs - 1).min(known_total - 1)
        } else {
            start + cs - 1
        };

        let range_val = format!("bytes={start}-{end}");

        for attempt in 0..3 {
            let url = entry.upstream_url.read().clone();
            let mut hdrs = entry.headers.read().clone();
            hdrs.insert(
                reqwest::header::RANGE,
                reqwest::header::HeaderValue::from_str(&range_val).unwrap(),
            );

            self.active_conns.fetch_add(1, Ordering::Relaxed);
            let http_client = self.http.read().clone();
            let resp_res = http_client.get(&url).headers(hdrs).send().await;
            self.active_conns.fetch_sub(1, Ordering::Relaxed);

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
                        tokio::time::sleep(Duration::from_secs(wait_secs)).await;
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
                        if let Some(total) = parse_content_range_total(cr) {
                            entry.total_size.store(total, Ordering::Release);
                        }
                    } else if status == reqwest::StatusCode::OK {
                        if let Some(cl) = resp.content_length() {
                            entry.total_size.store(cl, Ordering::Release);
                        }
                    }

                    let data = resp.bytes().await.map_err(|_| StatusCode::BAD_GATEWAY)?;
                    self.total_upstream_bytes
                        .fetch_add(data.len() as u64, Ordering::Relaxed);
                    self.cache.put(&entry.id, chunk_idx, data.clone());
                    return Ok(data);
                }
                Err(e) => {
                    warn!(error = %e, attempt, chunk_idx, "upstream network error");
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
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
    }
}

fn simple_response(status: StatusCode, body: &'static str) -> Response<Full<Bytes>> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "text/plain; charset=utf-8")
        .body(Full::new(Bytes::from_static(body.as_bytes())))
        .unwrap()
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

async fn prune_image_disk_cache(dir: &std::path::Path, max_images: usize) {
    let Ok(mut rd) = tokio::fs::read_dir(dir).await else {
        return;
    };
    let mut entries = Vec::new();
    while let Ok(Some(entry)) = rd.next_entry().await {
        let p = entry.path();
        if p.extension().and_then(|e| e.to_str()) != Some("img") {
            continue;
        }
        let mtime = entry
            .metadata()
            .await
            .ok()
            .and_then(|m| m.modified().ok())
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        entries.push((mtime, p));
    }
    if entries.len() <= max_images {
        return;
    }
    entries.sort_by_key(|(m, _)| *m);
    let remove_count = entries.len().saturating_sub(max_images * 3 / 4);
    for (_, img_path) in entries.into_iter().take(remove_count) {
        let ct_path = img_path.with_extension("ct");
        let _ = tokio::fs::remove_file(&img_path).await;
        let _ = tokio::fs::remove_file(&ct_path).await;
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
