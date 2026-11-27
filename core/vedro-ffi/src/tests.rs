use std::ffi::{CStr, CString};

use super::*;
use crate::c_abi::*;
use crate::updater::*;

#[test]
fn c_abi_lifecycle_and_settings_roundtrip() {
    let rt = vedro_init(std::ptr::null());
    assert!(!rt.is_null());

    let m = CString::new("version").unwrap();
    let res_ptr = vedro_invoke(rt, m.as_ptr(), std::ptr::null());
    let res_str = unsafe { CStr::from_ptr(res_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    vedro_free_string(res_ptr);

    let v: Value = serde_json::from_str(&res_str).unwrap();
    assert_eq!(v["ok"], true);
    assert!(v["data"]["proxy_addr"]
        .as_str()
        .unwrap()
        .starts_with("127.0.0.1:"));

    let ev_ptr = vedro_poll_events(rt);
    let ev_str = unsafe { CStr::from_ptr(ev_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    vedro_free_string(ev_ptr);
    assert_eq!(ev_str, "[]");

    vedro_destroy(rt);
}

#[test]
fn c_abi_init_with_real_file_db_and_nested_dir_and_error_reporting() {
    let uniq = format!(
        "vedro_ffi_test_{}_{}",
        std::process::id(),
        uuid::Uuid::new_v4().simple()
    );
    let root = std::env::temp_dir().join(uniq);
    let nested_db = root.join("nested").join("app_support").join("vedro.db");
    let db_c = CString::new(nested_db.to_string_lossy().as_ref()).unwrap();

    // 1. Fresh install with non-existent nested parent directory must succeed
    let rt1 = vedro_init(db_c.as_ptr());
    assert!(!rt1.is_null(), "vedro_init failed for nested file db");
    assert!(nested_db.exists());
    assert!(vedro_last_init_error().is_null());
    vedro_destroy(rt1);

    // 2. Subsequent cold launch with existing directory & existing DB must succeed
    let rt2 = vedro_init(db_c.as_ptr());
    assert!(!rt2.is_null(), "vedro_init failed for existing file db");
    vedro_destroy(rt2);

    // 3. Invalid DB path (pointing at a directory) fails and exposes diagnostic via vedro_last_init_error()
    let dir_c = CString::new(root.to_string_lossy().as_ref()).unwrap();
    let rt_bad = vedro_init(dir_c.as_ptr());
    assert!(rt_bad.is_null());
    let err_ptr = vedro_last_init_error();
    assert!(!err_ptr.is_null());
    let err_msg = unsafe { CStr::from_ptr(err_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    vedro_free_string(err_ptr);
    assert!(
        err_msg.contains("failed to open storage"),
        "unexpected init error: {err_msg}"
    );

    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn e2e_mock_emby_login_images_stream_cold_restart_and_update_sha256() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let uniq = format!(
        "vedro_e2e_{}_{}",
        std::process::id(),
        uuid::Uuid::new_v4().simple()
    );
    let root = std::env::temp_dir().join(uniq);
    let db_path = root.join("vedro.db");
    let db_str = db_path.to_string_lossy().into_owned();

    // Build deterministic mock media & image payloads
    let fake_png: Vec<u8> = vec![
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ];
    let fake_jpeg: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, b'J', b'F', b'I', b'F'];
    let fake_video: Vec<u8> = (0..(128 * 1024u32)).map(|i| (i % 251) as u8).collect();
    let fake_update_bin: Vec<u8> = b"VEDRO_UPDATE_PAYLOAD_V102_BINARY_TEST".to_vec();
    let expected_update_sha =
        bytes_to_lower_hex(ring::digest::digest(&ring::digest::SHA256, &fake_update_bin).as_ref());

    // Start a real local mock Emby/EmbyGo HTTP server in a dedicated Tokio thread
    let (addr_tx, addr_rx) = std::sync::mpsc::channel::<std::net::SocketAddr>();
    let (stop_tx, stop_rx) = std::sync::mpsc::channel::<()>();
    let srv_png = fake_png.clone();
    let srv_jpg = fake_jpeg.clone();
    let srv_vid = fake_video.clone();
    let srv_upd = fake_update_bin.clone();

    let server_thread = std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async move {
                let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let addr = listener.local_addr().unwrap();
                let _ = addr_tx.send(addr);
                loop {
                    if stop_rx.try_recv().is_ok() {
                        break;
                    }
                    let accept_res = tokio::time::timeout(
                        Duration::from_millis(50),
                        listener.accept(),
                    )
                    .await;
                    let Ok(Ok((mut sock, _))) = accept_res else {
                        continue;
                    };
                    let png = srv_png.clone();
                    let jpg = srv_jpg.clone();
                    let vid = srv_vid.clone();
                    let upd = srv_upd.clone();
                    tokio::spawn(async move {
                        let mut buf = vec![0u8; 8192];
                        let n = sock.read(&mut buf).await.unwrap_or(0);
                        if n == 0 {
                            return;
                        }
                        let req_str = String::from_utf8_lossy(&buf[..n]);
                        let mut lines = req_str.lines();
                        let req_line = lines.next().unwrap_or("");
                        let mut parts = req_line.split_whitespace();
                        let method = parts.next().unwrap_or("GET");
                        let target = parts.next().unwrap_or("/");
                        let path = target.split('?').next().unwrap_or("/");

                        let mut has_token = false;
                        let mut range_hdr: Option<String> = None;
                        for line in lines {
                            if line.is_empty() {
                                break;
                            }
                            let lower = line.to_ascii_lowercase();
                            if (lower.starts_with("x-emby-token:")
                                || lower.starts_with("x-emby-authorization:"))
                                && line.contains("tok-e2e-secret")
                            {
                                has_token = true;
                            }
                            if let Some(rv) = lower.strip_prefix("range:") {
                                range_hdr = Some(rv.trim().to_string());
                            }
                        }

                        let (status, ctype, extra_hdrs, body): (&str, &str, String, Vec<u8>) =
                            match path {
                                "/System/Info/Public" | "/emby/System/Info/Public" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"Id":"srv-e2e-1","ServerName":"E2E Mock Emby","Version":"4.8.10"}"#.to_vec(),
                                ),
                                "/emby-compat/status" => (
                                    "404 Not Found",
                                    "text/plain",
                                    String::new(),
                                    b"not embygo".to_vec(),
                                ),
                                "/Users/AuthenticateByName" | "/emby/Users/AuthenticateByName" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"User":{"Id":"u-e2e-1","Name":"Alice","Policy":{"IsAdministrator":true}},"AccessToken":"tok-e2e-secret","ServerId":"srv-e2e-1"}"#.to_vec(),
                                ),
                                "/Users/u-e2e-1" | "/emby/Users/u-e2e-1" => {
                                    if !has_token {
                                        ("401 Unauthorized", "text/plain", String::new(), b"no token".to_vec())
                                    } else {
                                        (
                                            "200 OK",
                                            "application/json",
                                            String::new(),
                                            br#"{"Id":"u-e2e-1","Name":"Alice","Policy":{"IsAdministrator":true}}"#.to_vec(),
                                        )
                                    }
                                }
                                "/Users/u-e2e-1/Views" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"Items":[{"Id":"lib-1","Name":"Movies","Type":"CollectionFolder"}],"TotalRecordCount":1}"#.to_vec(),
                                ),
                                "/Users/u-e2e-1/Items/Latest" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"[{"Id":"movie-1","Name":"Blade Runner","Type":"Movie","ImageTags":{"Primary":"tag1"}}]"#.to_vec(),
                                ),
                                "/Users/u-e2e-1/Items/Resume"
                                | "/Shows/NextUp"
                                | "/Users/u-e2e-1/Suggestions"
                                | "/Users/u-e2e-1/Items" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"Items":[],"TotalRecordCount":0}"#.to_vec(),
                                ),
                                "/Users/u-e2e-1/Items/movie-1" => {
                                    if !has_token {
                                        ("401 Unauthorized", "text/plain", String::new(), b"no token".to_vec())
                                    } else {
                                        (
                                            "200 OK",
                                            "application/json",
                                            String::new(),
                                            br#"{"Id":"movie-1","Name":"Blade Runner","Type":"Movie","RunTimeTicks":6000000000,"MediaSources":[{"Id":"ms-1","Container":"mkv","Size":131072,"DirectStreamUrl":"/Videos/movie-1/stream.mkv"}]}"#.to_vec(),
                                        )
                                    }
                                }
                                "/Items/movie-1/Similar" | "/Items/movie-1/Segments" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"Items":[],"TotalRecordCount":0}"#.to_vec(),
                                ),
                                // Auth-gated JPEG poster
                                "/Items/movie-1/Images/Primary" => {
                                    if !has_token {
                                        ("401 Unauthorized", "text/plain", String::new(), b"auth required".to_vec())
                                    } else {
                                        ("200 OK", "image/jpeg", String::new(), jpg)
                                    }
                                }
                                // Auth-gated PNG delivered with `application/octet-stream` (EmbyGo/CDN case!)
                                "/Items/movie-1/Images/Backdrop/0" => {
                                    if !has_token {
                                        ("401 Unauthorized", "text/plain", String::new(), b"auth required".to_vec())
                                    } else {
                                        ("200 OK", "application/octet-stream", String::new(), png)
                                    }
                                }
                                "/Items/movie-1/PlaybackInfo" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"PlaySessionId":"ps-e2e-1","MediaSources":[{"Id":"ms-1","Container":"mkv","Size":131072,"SupportsDirectPlay":true,"DirectStreamUrl":"/Videos/movie-1/stream.mkv"}]}"#.to_vec(),
                                ),
                                "/Videos/movie-1/stream.mkv" => {
                                    let total = vid.len();
                                    if method == "HEAD" {
                                        (
                                            "200 OK",
                                            "video/x-matroska",
                                            format!("Accept-Ranges: bytes\r\nContent-Length: {total}\r\n"),
                                            Vec::new(),
                                        )
                                    } else if let Some(rh) = range_hdr {
                                        let spec = rh.strip_prefix("bytes=").unwrap_or("0-");
                                        let (s_str, e_str) = spec.split_once('-').unwrap_or(("0", ""));
                                        let s: usize = s_str.parse().unwrap_or(0);
                                        let e: usize = if e_str.is_empty() {
                                            total - 1
                                        } else {
                                            e_str.parse().unwrap_or(total - 1).min(total - 1)
                                        };
                                        let slice = vid[s..=e].to_vec();
                                        (
                                            "206 Partial Content",
                                            "video/x-matroska",
                                            format!(
                                                "Accept-Ranges: bytes\r\nContent-Range: bytes {s}-{e}/{total}\r\n"
                                            ),
                                            slice,
                                        )
                                    } else {
                                        ("200 OK", "video/x-matroska", "Accept-Ranges: bytes\r\n".to_string(), vid)
                                    }
                                }
                                "/update/vedro-1.0.2.bin" => (
                                    "200 OK",
                                    "application/octet-stream",
                                    String::new(),
                                    upd,
                                ),
                                "/github-api/latest" => (
                                    "403 Forbidden",
                                    "application/json",
                                    "X-RateLimit-Remaining: 0\r\n".to_string(),
                                    br#"{"message":"API rate limit exceeded"}"#.to_vec(),
                                ),
                                "/github-web/releases/latest" => (
                                    "302 Found",
                                    "text/plain",
                                    "Location: /github-web/releases/tag/v1.0.3\r\n".to_string(),
                                    Vec::new(),
                                ),
                                "/github-web/releases/tag/v1.0.3" => (
                                    "200 OK",
                                    "application/json",
                                    String::new(),
                                    br#"{"id":1,"tag_name":"v1.0.3"}"#.to_vec(),
                                ),
                                "/github-web/releases/download/v1.0.3/SHA256SUMS.txt" => {
                                    let hash = "a".repeat(64);
                                    let body = format!(
                                        "{hash}  vedro-v1.0.3-windows-x64-setup.exe\n{hash}  vedro-v1.0.3-android-arm64-v8a.apk\n"
                                    );
                                    ("200 OK", "text/plain", String::new(), body.into_bytes())
                                }
                                _ => ("404 Not Found", "text/plain", String::new(), b"not found".to_vec()),
                            };

                        let resp_head = if method == "HEAD" {
                            format!(
                                "HTTP/1.1 {status}\r\nContent-Type: {ctype}\r\n{extra_hdrs}Connection: close\r\n\r\n"
                            )
                        } else {
                            format!(
                                "HTTP/1.1 {status}\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\n{extra_hdrs}Connection: close\r\n\r\n",
                                body.len()
                            )
                        };
                        let _ = sock.write_all(resp_head.as_bytes()).await;
                        if method != "HEAD" {
                            let _ = sock.write_all(&body).await;
                        }
                    });
                }
            });
    });

    let mock_addr = addr_rx.recv_timeout(Duration::from_secs(5)).unwrap();
    let mock_base = format!("http://{mock_addr}");
    let http = reqwest::Client::builder()
        .no_proxy()
        .timeout(Duration::from_secs(5))
        .build()
        .unwrap();

    // === Session 1: Connect, Login, Home, Auth-Gated Images, Range Stream, Track Prefs ===
    {
        let rt1 = VedroRuntime::new(Some(&db_str)).expect("rt1 init");
        let tok_rt1 = rt1.rt.as_ref().unwrap();
        let conn = rt1
            .invoke("connect_server", json!({ "url": mock_base }))
            .expect("connect_server");
        let proxy_addr = conn["proxy_addr"].as_str().unwrap().to_string();

        let login = rt1
            .invoke("login", json!({ "username": "Alice", "password": "pw" }))
            .expect("login");
        assert_eq!(login["auth"]["AccessToken"], "tok-e2e-secret");

        let home = rt1.invoke("get_home", json!({})).expect("get_home");
        assert_eq!(home["views"][0]["Name"], "Movies");
        assert_eq!(home["latest_by_library"][0]["items"][0]["Id"], "movie-1");

        // 1. Auth-gated JPEG poster through StreamProxy must return 200 OK
        let (img_status, img_bytes) = tok_rt1.block_on(async {
            let r = http
                .get(format!(
                    "http://{proxy_addr}/img/Items/movie-1/Images/Primary"
                ))
                .send()
                .await
                .expect("poster fetch");
            let st = r.status().as_u16();
            let b = r.bytes().await.unwrap();
            (st, b)
        });
        assert_eq!(img_status, 200);
        assert_eq!(img_bytes.as_ref(), fake_jpeg.as_slice());

        // 2. Auth-gated PNG with `application/octet-stream` must sniff to `image/png` and return 200 OK!
        let (bd_status, bd_ct, bd_bytes) = tok_rt1.block_on(async {
            let r = http
                .get(format!(
                    "http://{proxy_addr}/img/Items/movie-1/Images/Backdrop/0"
                ))
                .send()
                .await
                .expect("backdrop fetch");
            let st = r.status().as_u16();
            let ct = r
                .headers()
                .get("content-type")
                .unwrap()
                .to_str()
                .unwrap()
                .to_string();
            let b = r.bytes().await.unwrap();
            (st, ct, b)
        });
        assert_eq!(bd_status, 200);
        assert_eq!(bd_ct, "image/png");
        assert_eq!(bd_bytes.as_ref(), fake_png.as_slice());

        // 3. Prepare playback + Range 206 streaming through StreamProxy
        let prep = rt1
            .invoke("prepare_playback", json!({ "item_id": "movie-1" }))
            .expect("prepare_playback");
        let stream_url = prep["proxy_url"].as_str().unwrap().to_string();
        let (s_status, s_bytes) = tok_rt1.block_on(async {
            let r = http
                .get(&stream_url)
                .header("Range", "bytes=1024-4095")
                .send()
                .await
                .expect("stream range fetch");
            let st = r.status().as_u16();
            let b = r.bytes().await.unwrap();
            (st, b)
        });
        assert_eq!(s_status, 206);
        assert_eq!(s_bytes.as_ref(), &fake_video[1024..=4095]);

        // 4. Track preferences with BOTH `series_or_item_id` (Flutter param!) AND `scope_id`
        rt1.invoke(
            "set_track_preference",
            json!({ "series_or_item_id": "movie-1", "audio_lang": "jpn", "subtitle_lang": "chi" }),
        )
        .expect("set_track_preference");
        let tp = rt1
            .invoke(
                "get_track_preference",
                json!({ "series_or_item_id": "movie-1" }),
            )
            .expect("get_track_preference");
        assert_eq!(tp["preference"]["audio_lang"], "jpn");
        assert_eq!(tp["preference"]["subtitle_lang"], "chi");
    }

    // === Session 2: COLD RESTART — NO `restore_session` called! ===
    // Verifies zero "no server connected" AND millisecond-0 artwork loading!
    {
        let rt2 = VedroRuntime::new(Some(&db_str)).expect("rt2 cold restart init");
        let tok_rt2 = rt2.rt.as_ref().unwrap();
        let boot = rt2
            .invoke("bootstrap_state", json!({}))
            .expect("bootstrap_state");
        let proxy_addr = boot["proxy_addr"].as_str().unwrap().to_string();

        // Immediately call `get_item` WITHOUT calling `connect_server` or `restore_session`!
        let item = rt2
            .invoke("get_item", json!({ "item_id": "movie-1" }))
            .expect("cold-start get_item must NOT fail with no server connected");
        assert_eq!(item["item"]["Name"], "Blade Runner");

        // Immediately fetch auth-gated poster on cold start!
        let (img_status, img_bytes) = tok_rt2.block_on(async {
            let r = http
                .get(format!(
                    "http://{proxy_addr}/img/Items/movie-1/Images/Primary"
                ))
                .send()
                .await
                .expect("cold-start poster fetch");
            let st = r.status().as_u16();
            let b = r.bytes().await.unwrap();
            (st, b)
        });
        assert_eq!(img_status, 200);
        assert_eq!(img_bytes.as_ref(), fake_jpeg.as_slice());

        // Verify auto-updater SHA-256 download passes on match & rejects on mismatch!
        let upd_http = reqwest::Client::builder().no_proxy().build().unwrap();
        let part_ok = root.join("upd_ok.part");
        let final_ok = root.join("upd_ok.bin");
        let st_ok = Arc::new(Mutex::new(UpdateDownloadState::default()));
        let cancel_ok = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let ok_res = rt2
            .rt
            .as_ref()
            .unwrap()
            .block_on(download_and_verify_update_file(
                upd_http.clone(),
                format!("{mock_base}/update/vedro-1.0.2.bin"),
                part_ok,
                final_ok.clone(),
                Some(expected_update_sha.clone()),
                false,
                st_ok,
                cancel_ok,
            ))
            .expect("valid sha256 update download");
        assert_eq!(ok_res.status, "ready");
        assert!(ok_res.sha256_verified);
        assert_eq!(ok_res.sha256.as_deref(), Some(expected_update_sha.as_str()));
        assert!(final_ok.is_file());

        // Tampered SHA-256 MUST fail and delete `.part` file!
        let part_bad = root.join("upd_bad.part");
        let final_bad = root.join("upd_bad.bin");
        let st_bad = Arc::new(Mutex::new(UpdateDownloadState::default()));
        let cancel_bad = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let bad_res = rt2
            .rt
            .as_ref()
            .unwrap()
            .block_on(download_and_verify_update_file(
                upd_http,
                format!("{mock_base}/update/vedro-1.0.2.bin"),
                part_bad.clone(),
                final_bad.clone(),
                Some("0".repeat(64)),
                false,
                st_bad,
                cancel_bad,
            ));
        assert!(bad_res.is_err());
        assert!(!part_bad.exists());
        assert!(!final_bad.exists());

        // Verify GitHub API 403 rate-limit seamlessly falls back to rate-limit-free
        // `/releases/latest` + `SHA256SUMS.txt` and builds verified asset URLs + SHA-256!
        let fallback_rel = rt2
            .rt
            .as_ref()
            .unwrap()
            .block_on(fetch_github_latest_release(
                &reqwest::Client::builder().no_proxy().build().unwrap(),
                &format!("{mock_base}/github-api/latest"),
                &format!("{mock_base}/github-web/releases/latest"),
                &format!("{mock_base}/github-web/releases/download"),
                false,
            ))
            .expect("403 rate limit must fall back to web releases/latest");
        assert_eq!(fallback_rel["tag_name"], "v1.0.3");
        assert_eq!(fallback_rel["version"], "1.0.3");
        assert_eq!(fallback_rel["source"], "github_web_fallback");
        let fb_assets = fallback_rel["assets"].as_array().expect("fallback assets");
        assert_eq!(fb_assets.len(), 2);
        assert!(fb_assets.iter().any(|a| {
            a["name"] == "vedro-v1.0.3-windows-x64-setup.exe"
                && a["sha256"] == "a".repeat(64)
                && a["url"]
                    .as_str()
                    .unwrap()
                    .ends_with("/v1.0.3/vedro-v1.0.3-windows-x64-setup.exe")
        }));

        // Logout must clear client & proxy streams/upstreams cleanly
        rt2.invoke("logout", json!({})).expect("logout");
        assert!(rt2
            .invoke("get_item", json!({ "item_id": "movie-1" }))
            .is_err());
    }

    let _ = stop_tx.send(());
    let _ = server_thread.join();
    let _ = std::fs::remove_dir_all(&root);
}
