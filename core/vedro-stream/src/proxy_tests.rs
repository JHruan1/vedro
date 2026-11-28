use super::*;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

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
    let dir = std::env::temp_dir().join(format!("vedro_img_cache_test_{}", uuid::Uuid::new_v4()));
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

#[tokio::test]
async fn caches_302_redirect_across_chunks_and_re_resolves_on_403() {
    let redirect_hits = Arc::new(AtomicUsize::new(0));
    let cdn_v1_hits = Arc::new(AtomicUsize::new(0));
    let cdn_v2_hits = Arc::new(AtomicUsize::new(0));
    let expire_v1 = Arc::new(AtomicBool::new(false));
    let payload = Arc::new(vec![0xABu8; (DEFAULT_CHUNK_SIZE as usize) * 4]);

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let r_hits = Arc::clone(&redirect_hits);
    let c1_hits = Arc::clone(&cdn_v1_hits);
    let c2_hits = Arc::clone(&cdn_v2_hits);
    let exp_v1 = Arc::clone(&expire_v1);
    let data = Arc::clone(&payload);

    let srv = tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                break;
            };
            let r_hits = Arc::clone(&r_hits);
            let c1_hits = Arc::clone(&c1_hits);
            let c2_hits = Arc::clone(&c2_hits);
            let exp_v1 = Arc::clone(&exp_v1);
            let data = Arc::clone(&data);
            tokio::spawn(async move {
                let io = TokioIo::new(stream);
                let svc = service_fn(move |req: Request<Incoming>| {
                    let r_hits = Arc::clone(&r_hits);
                    let c1_hits = Arc::clone(&c1_hits);
                    let c2_hits = Arc::clone(&c2_hits);
                    let exp_v1 = Arc::clone(&exp_v1);
                    let data = Arc::clone(&data);
                    async move {
                        let path = req.uri().path().to_string();
                        if path == "/emby/stream" {
                            let n = r_hits.fetch_add(1, Ordering::SeqCst);
                            let target = if !exp_v1.load(Ordering::SeqCst) && n == 0 {
                                "/cdn/v1"
                            } else {
                                "/cdn/v2"
                            };
                            return Ok::<_, hyper::Error>(
                                Response::builder()
                                    .status(StatusCode::FOUND)
                                    .header(header::LOCATION, format!("http://{addr}{target}"))
                                    .body(full_body(Bytes::new()))
                                    .unwrap(),
                            );
                        }
                        if path == "/cdn/v1" && exp_v1.load(Ordering::SeqCst) {
                            return Ok(simple_response(StatusCode::FORBIDDEN, "expired"));
                        }
                        if path == "/cdn/v1" {
                            c1_hits.fetch_add(1, Ordering::SeqCst);
                        } else {
                            c2_hits.fetch_add(1, Ordering::SeqCst);
                        }
                        let rh = req
                            .headers()
                            .get(header::RANGE)
                            .and_then(|v| v.to_str().ok())
                            .unwrap_or("bytes=0-1048575");
                        let (s, e) = parse_range_header(rh, data.len() as u64).unwrap();
                        let slice = Bytes::copy_from_slice(&data[s as usize..=e as usize]);
                        Ok(Response::builder()
                            .status(StatusCode::PARTIAL_CONTENT)
                            .header(
                                header::CONTENT_RANGE,
                                format!("bytes {s}-{e}/{}", data.len()),
                            )
                            .header(header::CONTENT_LENGTH, slice.len())
                            .body(full_body(slice))
                            .unwrap())
                    }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(io, svc)
                    .await;
            });
        }
    });

    let proxy = StreamProxy::start(StreamProxyConfig {
        prefetch_chunks: 0,
        ..StreamProxyConfig::default()
    })
    .await
    .unwrap();
    let (sid, _) = proxy.register_stream(
        format!("http://{addr}/emby/stream"),
        HeaderMap::new(),
        Some(payload.len() as u64),
        Some("video/mp4".into()),
    );

    let entry = proxy.streams.get(&sid).unwrap().clone();
    // Fetch chunk 0 (follows 302 -> /cdn/v1 and caches it with ZERO duplicate 302 race!)
    let c0 = proxy.fetch_chunk(&entry, 0).await.unwrap();
    assert_eq!(c0.len(), DEFAULT_CHUNK_SIZE as usize);
    assert_eq!(redirect_hits.load(Ordering::SeqCst), 1);

    // Fetch chunk 1 — must hit /cdn/v1 directly with ZERO additional /emby/stream redirects!
    let c1 = proxy.fetch_chunk(&entry, 1).await.unwrap();
    assert_eq!(c1.len(), DEFAULT_CHUNK_SIZE as usize);
    assert_eq!(redirect_hits.load(Ordering::SeqCst), 1);
    assert!(cdn_v1_hits.load(Ordering::SeqCst) >= 2);

    // Expire /cdn/v1 (403) and fetch chunk 2 (not tail-prewarmed) — proxy must automatically
    // invalidate & re-resolve to /cdn/v2!
    expire_v1.store(true, Ordering::SeqCst);
    let c2 = proxy.fetch_chunk(&entry, 2).await.unwrap();
    assert_eq!(c2.len(), DEFAULT_CHUNK_SIZE as usize);
    assert!(cdn_v2_hits.load(Ordering::SeqCst) >= 1);

    srv.abort();
}

#[tokio::test]
async fn singleflight_302_prevents_concurrent_redirect_stampede() {
    let redirect_hits = Arc::new(AtomicUsize::new(0));
    let payload: Arc<Vec<u8>> = Arc::new(
        (0..((DEFAULT_CHUNK_SIZE as usize) * 3))
            .map(|i| (i % 251) as u8)
            .collect(),
    );

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let r_hits = Arc::clone(&redirect_hits);
    let data = Arc::clone(&payload);
    let srv = tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                break;
            };
            let r_hits = Arc::clone(&r_hits);
            let data = Arc::clone(&data);
            tokio::spawn(async move {
                let io = TokioIo::new(stream);
                let svc = service_fn(move |req: Request<Incoming>| {
                    let r_hits = Arc::clone(&r_hits);
                    let data = Arc::clone(&data);
                    async move {
                        if req.uri().path() == "/cloud/302" {
                            r_hits.fetch_add(1, Ordering::SeqCst);
                            // Simulate slow cloud-drive 302 link generation (115/Quark/Alist)
                            tokio::time::sleep(Duration::from_millis(80)).await;
                            return Ok::<_, hyper::Error>(
                                Response::builder()
                                    .status(StatusCode::FOUND)
                                    .header(header::LOCATION, format!("http://{addr}/cdn/file"))
                                    .body(full_body(Bytes::new()))
                                    .unwrap(),
                            );
                        }
                        let rh = req
                            .headers()
                            .get(header::RANGE)
                            .and_then(|v| v.to_str().ok())
                            .unwrap_or("bytes=0-1048575");
                        let (s, e) = parse_range_header(rh, data.len() as u64).unwrap();
                        let slice = Bytes::copy_from_slice(&data[s as usize..=e as usize]);
                        Ok(Response::builder()
                            .status(StatusCode::PARTIAL_CONTENT)
                            .header(
                                header::CONTENT_RANGE,
                                format!("bytes {s}-{e}/{}", data.len()),
                            )
                            .header(header::CONTENT_LENGTH, slice.len())
                            .body(full_body(slice))
                            .unwrap())
                    }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(io, svc)
                    .await;
            });
        }
    });

    let proxy = StreamProxy::start(StreamProxyConfig {
        prefetch_chunks: 0,
        ..StreamProxyConfig::default()
    })
    .await
    .unwrap();
    let (sid, _) = proxy.register_stream(
        format!("http://{addr}/cloud/302"),
        HeaderMap::new(),
        Some(payload.len() as u64),
        Some("video/x-matroska".into()),
    );
    let entry = proxy.streams.get(&sid).unwrap().clone();

    // Fire 3 concurrent chunk fetches at T=0; `resolve_lock` must collapse 302 resolution to 1 hit!
    let (r0, r1, r2) = tokio::join!(
        proxy.fetch_chunk(&entry, 0),
        proxy.fetch_chunk(&entry, 1),
        proxy.fetch_chunk(&entry, 2),
    );
    let cs = DEFAULT_CHUNK_SIZE as usize;
    assert_eq!(r0.unwrap().as_ref(), &payload[0..cs]);
    assert_eq!(r1.unwrap().as_ref(), &payload[cs..cs * 2]);
    assert_eq!(r2.unwrap().as_ref(), &payload[cs * 2..cs * 3]);
    assert_eq!(redirect_hits.load(Ordering::SeqCst), 1);

    srv.abort();
}

#[tokio::test]
async fn assembles_short_capped_206_chunks_and_oversized_206_responses() {
    let cs = DEFAULT_CHUNK_SIZE as usize;
    let payload: Arc<Vec<u8>> = Arc::new((0..(cs * 2)).map(|i| ((i * 7) % 253) as u8).collect());

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let data = Arc::clone(&payload);
    let srv = tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                break;
            };
            let data = Arc::clone(&data);
            tokio::spawn(async move {
                let io = TokioIo::new(stream);
                let svc = service_fn(move |req: Request<Incoming>| {
                    let data = Arc::clone(&data);
                    async move {
                        let path = req.uri().path().to_string();
                        let rh = req
                            .headers()
                            .get(header::RANGE)
                            .and_then(|v| v.to_str().ok())
                            .unwrap_or("bytes=0-1048575");
                        let (s, e) = parse_range_header(rh, data.len() as u64).unwrap();
                        let actual_end = if path == "/short-cap" {
                            // Cloud CDN caps each 206 Range response to 256 KiB!
                            e.min(s + (256 * 1024) - 1)
                        } else {
                            // Proxy ignores Range end and serves through EOF (> 1 MiB)!
                            (data.len() as u64) - 1
                        };
                        let slice = Bytes::copy_from_slice(&data[s as usize..=actual_end as usize]);
                        Ok::<_, hyper::Error>(
                            Response::builder()
                                .status(StatusCode::PARTIAL_CONTENT)
                                .header(
                                    header::CONTENT_RANGE,
                                    format!("bytes {s}-{actual_end}/{}", data.len()),
                                )
                                .header(header::CONTENT_LENGTH, slice.len())
                                .body(full_body(slice))
                                .unwrap(),
                        )
                    }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(io, svc)
                    .await;
            });
        }
    });

    let proxy = StreamProxy::start(StreamProxyConfig {
        prefetch_chunks: 0,
        ..StreamProxyConfig::default()
    })
    .await
    .unwrap();

    // 1. Short-capped 256 KiB CDN responses must top-up into a complete, exact 1 MiB chunk
    let (sid_short, _) = proxy.register_stream(
        format!("http://{addr}/short-cap"),
        HeaderMap::new(),
        Some(payload.len() as u64),
        Some("video/mp4".into()),
    );
    let entry_short = proxy.streams.get(&sid_short).unwrap().clone();
    let c0 = proxy.fetch_chunk(&entry_short, 0).await.unwrap();
    assert_eq!(c0.len(), cs);
    assert_eq!(c0.as_ref(), &payload[0..cs]);

    // 2. Oversized 206 response (ignoring Range end) must cap cleanly to 1 MiB instead of 502!
    let (sid_over, _) = proxy.register_stream(
        format!("http://{addr}/oversized-206"),
        HeaderMap::new(),
        Some(payload.len() as u64),
        Some("video/mp4".into()),
    );
    let entry_over = proxy.streams.get(&sid_over).unwrap().clone();
    let c0_over = proxy.fetch_chunk(&entry_over, 0).await.unwrap();
    assert_eq!(c0_over.len(), cs);
    assert_eq!(c0_over.as_ref(), &payload[0..cs]);

    srv.abort();
}

#[tokio::test]
async fn resumes_mid_body_tcp_reset_and_ignores_tiny_strm_known_size() {
    let cs = DEFAULT_CHUNK_SIZE as usize;
    let payload: Arc<Vec<u8>> = Arc::new((0..(cs * 2)).map(|i| ((i * 13) % 241) as u8).collect());
    let drop_once = Arc::new(AtomicBool::new(true));
    let saw_resume_offset = Arc::new(AtomicBool::new(false));

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let data = Arc::clone(&payload);
    let drop_flag = Arc::clone(&drop_once);
    let resume_flag = Arc::clone(&saw_resume_offset);

    // Raw TCP server so we can faithfully simulate a mid-body TCP drop after 300 KiB!
    let srv = tokio::spawn(async move {
        loop {
            let Ok((mut sock, _)) = listener.accept().await else {
                break;
            };
            let data = Arc::clone(&data);
            let drop_flag = Arc::clone(&drop_flag);
            let resume_flag = Arc::clone(&resume_flag);
            tokio::spawn(async move {
                let mut req_buf = vec![0u8; 4096];
                let Ok(n) = sock.read(&mut req_buf).await else {
                    return;
                };
                if n == 0 {
                    return;
                }
                let req_text = String::from_utf8_lossy(&req_buf[..n]);
                let range_hdr = req_text
                    .lines()
                    .find_map(|l| {
                        let (k, v) = l.split_once(':')?;
                        if k.eq_ignore_ascii_case("range") {
                            Some(v.trim().to_string())
                        } else {
                            None
                        }
                    })
                    .unwrap_or_else(|| "bytes=0-1048575".to_string());
                let (s, e) = parse_range_header(&range_hdr, data.len() as u64).unwrap();
                let slice = &data[s as usize..=e as usize];
                let headers = format!(
                    "HTTP/1.1 206 Partial Content\r\nContent-Type: video/x-matroska\r\nContent-Range: bytes {s}-{e}/{}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    data.len(),
                    slice.len()
                );
                let _ = sock.write_all(headers.as_bytes()).await;

                if s == 0 && drop_flag.swap(false, Ordering::SeqCst) {
                    // Send first 300 KiB and abruptly sever the socket mid-chunk!
                    let cut = 300 * 1024;
                    let _ = sock.write_all(&slice[..cut]).await;
                    let _ = sock.flush().await;
                    drop(sock);
                    return;
                }
                if s == 300 * 1024 {
                    resume_flag.store(true, Ordering::SeqCst);
                }
                let _ = sock.write_all(slice).await;
                let _ = sock.flush().await;
            });
        }
    });

    let proxy = StreamProxy::start(StreamProxyConfig {
        prefetch_chunks: 0,
        ..StreamProxyConfig::default()
    })
    .await
    .unwrap();
    // Register with bogus 128-byte `.strm` placeholder size; proxy must ignore it and learn real 2 MiB size!
    let (_sid, local_url) = proxy.register_stream(
        format!("http://{addr}/cloud/file.mkv"),
        HeaderMap::new(),
        Some(128),
        Some("video/x-matroska".into()),
    );

    let client = reqwest::Client::new();
    let resp = client.get(&local_url).send().await.unwrap();
    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    assert_eq!(resp.content_length(), Some(payload.len() as u64));
    let body = resp.bytes().await.unwrap();
    assert_eq!(body.len(), payload.len());
    assert_eq!(body.as_ref(), payload.as_slice());
    assert!(
        saw_resume_offset.load(Ordering::SeqCst),
        "expected proxy to resume cleanly from exact byte offset 307200 after mid-body TCP drop"
    );

    srv.abort();
}
